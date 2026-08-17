import 'package:flutter/material.dart';

/// Shown instead of a route that depends on a native-only plugin with no
/// Flutter Web implementation at all (in-app camera recording, the story
/// creator's `dart:io`-based compositing pipeline) when running on
/// Flutter Web. Selected via each route's conditional export (see
/// core/router/camera_route.dart, core/router/story_route.dart) rather
/// than a runtime `kIsWeb` check inside the real screen, since the real
/// screen's own dart:io import would otherwise still break the web
/// compile regardless of any runtime branch.
class WebFeatureUnavailableScreen extends StatelessWidget {
  const WebFeatureUnavailableScreen({
    super.key,
    required this.feature,
    this.icon = Icons.phone_iphone_rounded,
    this.hint = 'Use the CommunityHub mobile app for this feature.',
  });

  final String feature;
  final IconData icon;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                '$feature isn\'t available in the web preview yet.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
