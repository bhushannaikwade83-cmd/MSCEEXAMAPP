import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Test script to verify MiniFASNet-V2 output class mapping
///
/// This helps determine:
/// 1. Which output index corresponds to [live, print_spoof, replay_spoof]
/// 2. Whether current formula (probs[2]) matches reference (1 - p[print] - p[replay])
///
/// Usage:
/// ```dart
/// final tester = MiniFasClassMappingTester();
/// await tester.runTests(photoPath: '/path/to/test/face.jpg');
/// ```

class MiniFasClassMappingTester {
  static const int _miniFasSize = 80;
  static const double _miniFasBboxScale = 2.7;

  Interpreter? _interpreter;
  bool _miniFasInputNormalized = true;

  Future<void> loadModel() async {
    try {
      final bundle = await rootBundle.load('assets/models/minifas_v1se_80x80.tflite');
      final bytes = bundle.buffer.asUint8List();
      _interpreter = await Interpreter.fromBuffer(bytes);
      _miniFasInputNormalized = _interpreter!.getInputTensor(0).type == TensorType.float32;
      debugPrint('✅ Model loaded. Normalized: $_miniFasInputNormalized');
    } catch (e) {
      debugPrint('❌ Failed to load model: $e');
    }
  }

  /// Run comprehensive test on a photo
  Future<void> runTests({required String photoPath}) async {
    if (_interpreter == null) {
      await loadModel();
    }
    if (_interpreter == null) {
      debugPrint('❌ Model not loaded, cannot run tests');
      return;
    }

    try {
      final bytes = await File(photoPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint('❌ Failed to decode image');
        return;
      }

      debugPrint('\n🔬 MiniFASNet-V2 CLASS MAPPING TEST');
      debugPrint('════════════════════════════════════════════════════════════');
      debugPrint('Test Image: $photoPath');
      debugPrint('Image Size: ${decoded.width}×${decoded.height}');

      // Create face box (center of image)
      final faceBox = Rect.fromCenter(
        center: Offset(decoded.width / 2, decoded.height / 2),
        width: decoded.width * 0.45,
        height: decoded.height * 0.55,
      );

      // Extract patch
      final patch = _miniFasPatchFromImage(decoded, faceBox);
      if (patch == null) {
        debugPrint('❌ Failed to extract face patch');
        return;
      }

      debugPrint('\n📊 Raw Inference Results:');
      debugPrint('─' * 60);

      final logits = _runInferenceAndGetLogits(patch);
      debugPrint('Raw logits: [${logits[0].toStringAsFixed(4)}, '
          '${logits[1].toStringAsFixed(4)}, ${logits[2].toStringAsFixed(4)}]');

      final probs = _softmax3(logits);
      debugPrint('Softmax probs: [${probs[0].toStringAsFixed(4)}, '
          '${probs[1].toStringAsFixed(4)}, ${probs[2].toStringAsFixed(4)}]');

      debugPrint('\n📋 CLASS MAPPING HYPOTHESES:');
      debugPrint('─' * 60);

      // Hypothesis 1: Current code assumption [spoof_A, spoof_B, live]
      final h1_liveScore = probs[2];
      debugPrint('\nHypothesis 1: Output order = [spoof_A, spoof_B, live]');
      debugPrint('  → Using current code: liveProb = probs[2]');
      debugPrint('  → Live probability = ${(h1_liveScore * 100).toStringAsFixed(1)}%');
      debugPrint('  → Decision: ${_decideH1(h1_liveScore)}');

      // Hypothesis 2: Reference formula [live, print_spoof, replay_spoof]
      final h2_liveScore = 1.0 - (probs[1] + probs[2]);
      debugPrint('\nHypothesis 2: Output order = [live, print_spoof, replay_spoof]');
      debugPrint('  → Using reference formula: liveProb = 1 - (probs[1] + probs[2])');
      debugPrint('  → Live probability = ${(h2_liveScore * 100).toStringAsFixed(1)}%');
      debugPrint('  → Decision: ${_decideH2(h2_liveScore)}');

      // Hypothesis 3: Direct [live, spoof1, spoof2]
      final h3_liveScore = probs[0];
      debugPrint('\nHypothesis 3: Output order = [live, spoof1, spoof2]');
      debugPrint('  → Using direct prob: liveProb = probs[0]');
      debugPrint('  → Live probability = ${(h3_liveScore * 100).toStringAsFixed(1)}%');
      debugPrint('  → Decision: ${_decideH3(h3_liveScore)}');

      debugPrint('\n🎯 RECOMMENDATION:');
      debugPrint('─' * 60);
      _printRecommendation(probs);

      debugPrint('\n💡 NEXT STEPS:');
      debugPrint('─' * 60);
      debugPrint('1. Test with KNOWN GOOD face (real person)');
      debugPrint('   → Should show high live probability');
      debugPrint('2. Test with KNOWN BAD face (printed photo/screen)');
      debugPrint('   → Should show low live probability');
      debugPrint('3. Compare results across hypotheses');
      debugPrint('4. Update anti_spoof_service.dart based on findings');

    } catch (e) {
      debugPrint('❌ Test failed: $e');
    }
  }

  List<double>? _miniFasPatchFromImage(img.Image image, Rect faceRect) {
    final box = _scaledBox(
      image.width,
      image.height,
      faceRect,
      _miniFasBboxScale,
    );
    final patch = List<double>.filled(_miniFasSize * _miniFasSize * 3, 0.0);
    final srcW = box.width;
    final srcH = box.height;
    if (srcW < 8 || srcH < 8) return null;

    for (int j = 0; j < _miniFasSize; j++) {
      for (int i = 0; i < _miniFasSize; i++) {
        final sx = (box.left + (i + 0.5) * srcW / _miniFasSize).floor().clamp(0, image.width - 1);
        final sy = (box.top + (j + 0.5) * srcH / _miniFasSize).floor().clamp(0, image.height - 1);
        final pixel = image.getPixel(sx, sy);
        final idx = (j * _miniFasSize + i) * 3;
        patch[idx]     = pixel.b.toDouble(); // BGR
        patch[idx + 1] = pixel.g.toDouble();
        patch[idx + 2] = pixel.r.toDouble();
      }
    }
    return patch;
  }

  List<double> _runInferenceAndGetLogits(List<double> bgrPatch) {
    final input = Float32List(_miniFasSize * _miniFasSize * 3);
    for (int i = 0; i < bgrPatch.length; i++) {
      input[i] = _miniFasInputNormalized ? (bgrPatch[i] / 255.0) : bgrPatch[i];
    }

    final inputTensor = input.reshape([1, _miniFasSize, _miniFasSize, 3]);
    final output = Float32List(3).reshape([1, 3]);
    _interpreter!.run(inputTensor, output);

    return [
      (output[0][0] as num).toDouble(),
      (output[0][1] as num).toDouble(),
      (output[0][2] as num).toDouble(),
    ];
  }

  List<double> _softmax3(List<double> x) {
    import 'dart:math' as math;
    final maxV = x.reduce(math.max);
    final exps = x.map((v) => math.exp(v - maxV)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  String _decideH1(double liveProb) {
    const threshold = 0.85;
    return liveProb >= threshold ? '✅ LIVE' : '❌ SPOOF';
  }

  String _decideH2(double liveProb) {
    const threshold = 0.50;
    return liveProb >= threshold ? '✅ LIVE' : '❌ SPOOF';
  }

  String _decideH3(double liveProb) {
    const threshold = 0.50;
    return liveProb >= threshold ? '✅ LIVE' : '❌ SPOOF';
  }

  void _printRecommendation(List<double> probs) {
    debugPrint('Based on softmax distribution:');

    final max = probs.reduce((a, b) => a > b ? a : b);
    final argmax = probs.indexOf(max);

    debugPrint('Highest probability: probs[$argmax] = ${(max * 100).toStringAsFixed(1)}%');

    if (argmax == 2 && probs[2] > 0.7) {
      debugPrint('→ LIKELY: Hypothesis 1 (current code) is CORRECT');
      debugPrint('→ Keep current implementation: liveProb = probs[2]');
    } else if (argmax == 0 && probs[0] > 0.7) {
      debugPrint('→ LIKELY: Hypothesis 3 is CORRECT');
      debugPrint('→ Change to: liveProb = probs[0]');
    } else if (probs[0] + probs[1] + probs[2] > 0.95) {
      debugPrint('→ LIKELY: Hypothesis 2 (reference formula) is CORRECT');
      debugPrint('→ Change to: liveProb = 1 - (probs[1] + probs[2])');
    } else {
      debugPrint('→ UNCERTAIN: Need more test cases (real vs fake faces)');
    }
  }

  Rect _scaledBox(int srcW, int srcH, Rect box, double bboxScale) {
    import 'dart:math' as math;
    final w = box.width;
    final h = box.height;
    final scale = math.min(
      (srcH - 1) / h,
      math.min((srcW - 1) / w, bboxScale),
    );
    final newW = w * scale;
    final newH = h * scale;
    final cx = w / 2 + box.left;
    final cy = h / 2 + box.top;
    var left = cx - newW / 2;
    var top = cy - newH / 2;
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    var right = left + newW;
    var bottom = top + newH;
    if (right > srcW - 1) {
      right = (srcW - 1).toDouble();
      left = right - newW;
    }
    if (bottom > srcH - 1) {
      bottom = (srcH - 1).toDouble();
      top = bottom - newH;
    }
    return Rect.fromLTRB(
      left.clamp(0.0, srcW.toDouble()),
      top.clamp(0.0, srcH.toDouble()),
      right.clamp(0.0, srcW.toDouble()),
      bottom.clamp(0.0, srcH.toDouble()),
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

// For importing Rect
import 'dart:ui' show Offset, Rect;
import 'package:flutter/services.dart' show rootBundle;
