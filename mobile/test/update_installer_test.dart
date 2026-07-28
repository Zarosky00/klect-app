import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klect/core/updates/update_checker.dart';
import 'package:klect/core/updates/update_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'klect-update-test-',
    );
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  AvailableUpdate updateFor(List<int> bytes, {String? digest}) =>
      AvailableUpdate(
        version: '9.9.9',
        notes: 'Test update.',
        downloadUrl: 'https://example.test/klect.apk',
        sha256: digest ?? sha256.convert(bytes).toString(),
        sizeBytes: bytes.length,
      );

  test(
    'downloads into the private updates cache and verifies SHA-256',
    () async {
      final bytes = List<int>.generate(4096, (index) => index % 251);
      final progress = <double>[];
      final installer = UpdateInstaller(
        client: MockClient.streaming((request, bodyStream) async {
          expect(request.url, Uri.parse('https://example.test/klect.apk'));
          expect(request.headers['Accept'], 'application/octet-stream');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              bytes.sublist(0, 1024),
              bytes.sublist(1024),
            ]),
            HttpStatus.ok,
            contentLength: bytes.length,
          );
        }),
        temporaryDirectory: () async => temporaryDirectory,
      );

      final apk = await installer.download(
        updateFor(bytes),
        onProgress: progress.add,
      );

      expect(
        apk.path,
        endsWith('updates${Platform.pathSeparator}klect-9.9.9.apk'),
      );
      expect(await apk.readAsBytes(), bytes);
      expect(progress, isNotEmpty);
      expect(progress.last, 1);
      expect(File('${apk.path}.part').existsSync(), isFalse);
    },
  );

  test('rejects and removes an APK with the wrong digest', () async {
    final bytes = <int>[1, 2, 3, 4];
    final installer = UpdateInstaller(
      client: MockClient(
        (request) async => http.Response.bytes(bytes, HttpStatus.ok),
      ),
      temporaryDirectory: () async => temporaryDirectory,
    );

    await expectLater(
      installer.download(updateFor(bytes, digest: List.filled(64, '0').join())),
      throwsA(
        isA<UpdateInstallException>().having(
          (error) => error.message,
          'message',
          contains('security check'),
        ),
      ),
    );

    final updates = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}updates',
    );
    expect(await updates.list().toList(), isEmpty);
  });

  test('rejects a truncated APK before asking Android to install it', () async {
    final completeBytes = <int>[1, 2, 3, 4];
    final installer = UpdateInstaller(
      client: MockClient(
        (request) async =>
            http.Response.bytes(completeBytes.sublist(0, 2), HttpStatus.ok),
      ),
      temporaryDirectory: () async => temporaryDirectory,
    );

    await expectLater(
      installer.download(updateFor(completeBytes)),
      throwsA(
        isA<UpdateInstallException>().having(
          (error) => error.message,
          'message',
          contains('incomplete'),
        ),
      ),
    );
  });
}
