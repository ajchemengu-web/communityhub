import 'package:flutter/material.dart';

import '../../shared/widgets/web_feature_unavailable_screen.dart';

/// Web builder — the story creator is built on dart:io (compression,
/// temp-file round trips) and the `camera` package, neither of which
/// are available on web. Gated off rather than rewritten for now; not
/// yet covered by the New Post web picker's simpler flow. Selected via
/// story_route.dart's conditional export.
Widget buildStoryCreatorScreen() => const WebFeatureUnavailableScreen(
      feature: 'Creating stories',
      icon: Icons.auto_stories_outlined,
    );
