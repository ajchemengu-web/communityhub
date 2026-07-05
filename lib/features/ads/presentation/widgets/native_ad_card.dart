import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/ad_service.dart';

/// A feed-styled ad card, inserted between posts every
/// [AppConstants.adFrequency] items. Uses a standard [BannerAd] (an
/// AdMob "Native" ad requires registering a platform-side ad factory in
/// native Android/iOS code, which is a separate follow-up) styled to sit
/// naturally in the post list.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key});

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final ad = BannerAd(
      adUnitId: AdService.instance.bannerAdUnitId,
      size: AdSize.mediumRectangle,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    );
    ad.load();
    _bannerAd = ad;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reserve the ad's final footprint from the first frame — swapping
    // between SizedBox.shrink() and the loaded ad mid-scroll shifts every
    // item below it, which is the layout-jank equivalent of an ad
    // suddenly shoving the article you were reading down the page.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: AppColors.darkSurface,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Text('Sponsored',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          SizedBox(
            width: AdSize.mediumRectangle.width.toDouble(),
            height: AdSize.mediumRectangle.height.toDouble(),
            child: _isLoaded && _bannerAd != null
                ? AdWidget(ad: _bannerAd!)
                : const ColoredBox(color: AppColors.darkSurface2),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
