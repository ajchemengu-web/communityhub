import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/constants/app_constants.dart';

/// Thin wrapper around the Google Mobile Ads SDK — mirrors the
/// singleton-service pattern used by [SupabaseService]/[YouTubeService].
class AdService {
  AdService._();
  static final instance = AdService._();

  Future<void> initialize() async {
    // google_mobile_ads has no Flutter Web implementation — MobileAds.
    // instance.initialize() talks to a platform channel that doesn't
    // exist on web and would throw. No ad widgets are ever built on web
    // either (see feed_provider.dart / reels_screen.dart), so skipping
    // SDK init there is safe.
    if (kIsWeb) return;
    // Debug builds always request TEST ads on known dev devices, even
    // though the real ad unit/app ids are wired in — prevents accidental
    // invalid-traffic flags from a developer tapping their own real ads.
    if (kDebugMode) {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: AppConstants.admobTestDeviceIds),
      );
    }
    await MobileAds.instance.initialize();
  }

  // `dart:io`'s Platform.isIOS would break the web *compile*, not just
  // throw at runtime — this file is imported unconditionally from
  // main.dart, so it can never import dart:io at all. defaultTargetPlatform
  // (from package:flutter/foundation.dart) gives the same iOS/Android
  // branch without that dependency.
  String get bannerAdUnitId => kIsWeb
      ? ''
      : defaultTargetPlatform == TargetPlatform.iOS
          ? AppConstants.admobIosBannerAdUnitId
          : AppConstants.admobAndroidBannerAdUnitId;
}
