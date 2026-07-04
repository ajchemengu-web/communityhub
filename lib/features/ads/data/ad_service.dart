import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/constants/app_constants.dart';

/// Thin wrapper around the Google Mobile Ads SDK — mirrors the
/// singleton-service pattern used by [SupabaseService]/[YouTubeService].
class AdService {
  AdService._();
  static final instance = AdService._();

  Future<void> initialize() => MobileAds.instance.initialize();

  String get bannerAdUnitId => Platform.isIOS
      ? AppConstants.admobIosBannerAdUnitId
      : AppConstants.admobAndroidBannerAdUnitId;
}
