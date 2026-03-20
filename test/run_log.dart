import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('run log', () async {
    final result = await Process.run('firebase', ['functions:log', '--lines', '50'], workingDirectory: '../functions');
    print('stdout: ${result.stdout}');
    print('stderr: ${result.stderr}');
  });
}