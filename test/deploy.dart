import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('deploy', () async {
    final result = await Process.run('firebase', ['deploy', '--only', 'functions'], workingDirectory: 'functions');
    print('stdout: ${result.stdout}');
    print('stderr: ${result.stderr}');
  });
}