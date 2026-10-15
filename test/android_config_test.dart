import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android configuration: target SDK and the permission promise
/// (microphone only, never internet in release builds). CI additionally
/// checks the permissions of the built APK with aapt2.
void main() {
  String read(String path) => File(path).readAsStringSync();

  Set<String> usedPermissions(String manifest) =>
      RegExp(r'<uses-permission\s+android:name="([^"]+)"\s*/>')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .toSet();

  test('main manifest only asks for the microphone', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(usedPermissions(manifest), {'android.permission.RECORD_AUDIO'});
    expect(
      manifest,
      contains('android:name="android.hardware.microphone" android:required="false"'),
    );
  });

  test('release builds strip network permissions', () {
    final manifest = read('android/app/src/release/AndroidManifest.xml');
    for (final permission in [
      'android.permission.INTERNET',
      'android.permission.ACCESS_NETWORK_STATE',
    ]) {
      expect(
        manifest,
        contains('<uses-permission android:name="$permission" tools:node="remove" />'),
      );
    }
  });

  test('targets Android 17 (API 37)', () {
    final gradle = read('android/app/build.gradle.kts');
    expect(gradle, contains('compileSdk = 37'));
    expect(gradle, contains('targetSdk = 37'));
  });
}
