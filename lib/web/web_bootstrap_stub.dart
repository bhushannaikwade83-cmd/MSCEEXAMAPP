import 'package:flutter/material.dart';

/// Native (non-web) stand-in for [WebBootstrap].
///
/// Never shown: `main.dart` only builds WebBootstrap when `kIsWeb` is true,
/// and on web the conditional import picks `web_bootstrap.dart` instead.
/// This exists solely so Android/iOS builds don't compile `dart:html` code.
class WebBootstrap extends StatelessWidget {
  const WebBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
