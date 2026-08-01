import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/app_version.dart';

void main() {
  test('runtime version matches the semantic pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^+\s]+)\+\d+\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(match!.group(1), kAppVersion);
  });
}
