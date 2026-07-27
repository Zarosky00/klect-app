import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_checker.dart';

/// What Android did after Klect handed it a verified APK.
enum InstallRequestResult {
  /// Android's package installer is now asking the user to approve the update.
  installerOpened,

  /// Android opened the one-time "Allow from this source" settings screen.
  permissionRequired,
}

/// Downloads a GitHub release inside Klect, verifies it, then asks Android to
/// install it. Android always owns the final confirmation UI.
class UpdateInstaller {
  /// Creates the production installer.
  UpdateInstaller({
    this.client,
    Future<Directory> Function()? temporaryDirectory,
    Future<String?> Function(String apkPath)? requestNativeInstall,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _requestNativeInstall =
           requestNativeInstall ??
           ((path) => _channel.invokeMethod<String>(
             'installApk',
             <String, String>{'path': path},
           ));

  static const MethodChannel _channel = MethodChannel(
    'com.klect.klect/updater',
  );

  static const Duration _connectionTimeout = Duration(seconds: 30);

  /// Optional reusable client, primarily for deterministic tests.
  final http.Client? client;

  final Future<Directory> Function() _temporaryDirectory;
  final Future<String?> Function(String apkPath) _requestNativeInstall;

  /// Downloads and verifies [update], reporting a `0..1` byte progress value.
  ///
  /// The final file stays in Klect's private cache and is only exposed to
  /// Android's installer through a one-time read grant.
  Future<File> download(
    AvailableUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    final requestClient = client ?? http.Client();
    File? partial;
    try {
      final request = http.Request('GET', Uri.parse(update.downloadUrl))
        ..headers['Accept'] = 'application/octet-stream';
      final response = await requestClient
          .send(request)
          .timeout(_connectionTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateInstallException(
          'The update server returned ${response.statusCode}.',
        );
      }

      final cache = await _temporaryDirectory();
      final updates = Directory(
        '${cache.path}${Platform.pathSeparator}updates',
      );
      await updates.create(recursive: true);
      for (final cachedFile in updates.listSync().whereType<File>()) {
        if (cachedFile.path.endsWith('.apk') ||
            cachedFile.path.endsWith('.apk.part')) {
          cachedFile.deleteSync();
        }
      }
      partial = File(
        '${updates.path}${Platform.pathSeparator}'
        'klect-${update.version}.apk.part',
      );
      final ready = File(
        '${updates.path}${Platform.pathSeparator}'
        'klect-${update.version}.apk',
      );
      if (partial.existsSync()) partial.deleteSync();
      if (ready.existsSync()) ready.deleteSync();

      final expectedBytes = update.sizeBytes ?? response.contentLength;
      var receivedBytes = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response.stream.timeout(_connectionTimeout)) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (expectedBytes != null && expectedBytes > 0) {
            onProgress?.call((receivedBytes / expectedBytes).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }

      if (update.sizeBytes != null && receivedBytes != update.sizeBytes) {
        throw const UpdateInstallException(
          'The downloaded update is incomplete.',
        );
      }
      if (update.sha256 != null) {
        final actual = (await sha256.bind(partial.openRead()).first).toString();
        if (actual != update.sha256) {
          throw const UpdateInstallException(
            'The downloaded update failed its security check.',
          );
        }
      }

      onProgress?.call(1.0);
      return partial.rename(ready.path);
    } on UpdateInstallException {
      if (partial != null && partial.existsSync()) partial.deleteSync();
      rethrow;
    } on Exception {
      if (partial != null && partial.existsSync()) partial.deleteSync();
      throw const UpdateInstallException(
        'Could not download the update. Check your connection and try again.',
      );
    } finally {
      if (client == null) requestClient.close();
    }
  }

  /// Opens Android's installer, or its one-time source-permission screen.
  Future<InstallRequestResult> install(File apk) async {
    if (!Platform.isAndroid) {
      throw const UpdateInstallException(
        'In-app APK updates are available only on Android.',
      );
    }
    try {
      final result = await _requestNativeInstall(apk.path);
      return switch (result) {
        'installerOpened' => InstallRequestResult.installerOpened,
        'permissionRequired' => InstallRequestResult.permissionRequired,
        _ => throw const UpdateInstallException(
          'Android could not open the update installer.',
        ),
      };
    } on PlatformException {
      throw const UpdateInstallException(
        'Android could not open the update installer.',
      );
    }
  }
}

/// A safe, user-facing failure from the download/install pipeline.
class UpdateInstallException implements Exception {
  /// Creates an update failure with copy suitable for a toast.
  const UpdateInstallException(this.message);

  /// Explanation shown to the user.
  final String message;

  @override
  String toString() => message;
}
