import 'package:flutter/material.dart';

import '../../shared/widgets/web_feature_unavailable_screen.dart';

/// Web builder — in-app camera recording depends on the `camera`
/// package and dart:io file writes, neither of which are available (or,
/// for dart:io, even compilable) on web. Users can still upload an
/// existing video from New Post; only live in-app recording is gated
/// off. Selected via camera_route.dart's conditional export.
Widget buildCameraRecorderScreen({void Function(String)? onVideoSaved}) =>
    const WebFeatureUnavailableScreen(
      feature: 'In-app video recording',
      icon: Icons.videocam_off_rounded,
    );
