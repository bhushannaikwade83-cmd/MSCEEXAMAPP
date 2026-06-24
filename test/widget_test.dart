import 'package:flutter_test/flutter_test.dart';
import 'package:msce_exam_app/core/theme.dart';

void main() {
  test('app theme builds', () {
    expect(buildAppTheme().colorScheme.primary, isNotNull);
  });
}
