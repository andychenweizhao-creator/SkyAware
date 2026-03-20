import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('run shell', () async {
    final result = await Process.run('firebase', ['functions:log', '--lines', '100'], workingDirectory: 'functions');
    print('stdout: ${result.stdout}');
    print('stderr: ${result.stderr}');
  });
}