// Generated manually from google-services.json
// Re-generate with: flutterfire configure --project=communitydom-5f0c3

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web not configured.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS not configured.');
      default:
        throw UnsupportedError(
            'Unsupported platform: $defaultTargetPlatform');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyATN42zy6dgV3knpdMGV67mG2zHtFY9sV0',
    appId: '1:1037861382900:android:29a1391ce0b935104a4ca1',
    messagingSenderId: '1037861382900',
    projectId: 'communitydom-5f0c3',
    storageBucket: 'communitydom-5f0c3.firebasestorage.app',
  );
}
