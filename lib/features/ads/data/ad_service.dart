import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/constants/app_constants.dart';

/// Thin wrapper around the Google Mobile Ads SDK — mirrors the
/// singleton-service pattern used by [SupabaseService]/[YouTubeService].
class AdService {
  AdService._();
  static final instance = AdService._();

  Future<void> initialize() async {
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

  String get bannerAdUnitId => Platform.isIOS
      ? AppConstants.admobIosBannerAdUnitId
      : AppConstants.admobAndroidBannerAdUnitId;
}
