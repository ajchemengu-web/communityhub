import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../data/ad_service.dart';

/// A full-slide ad shown between reels every
/// [AppConstants.adFrequency] videos, matching the reels' black
/// full-screen aesthetic. Swipe up/down is wired by the caller
/// (reels_screen.dart) exactly like a regular reel item.
class ReelAdOverlay extends StatefulWidget {
  const ReelAdOverlay({super.key});

  @override
  State<ReelAdOverlay> createState() => _ReelAdOverlayState();
}

class _ReelAdOverlayState extends State<ReelAdOverlay> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
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
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Sponsored',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 12),
          if (_isLoaded && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          else
            const SizedBox(
              height: 250,
              width: 300,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 24),
          const Text('Swipe up to continue',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}
