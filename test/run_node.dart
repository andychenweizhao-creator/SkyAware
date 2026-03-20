import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('run test_callable.js', () async {
    final result = await Process.run('node', ['test_callable.js'], workingDirectory: 'test');
    print('stdout: ${result.stdout}');
    print('stderr: ${result.stderr}');
  });
}