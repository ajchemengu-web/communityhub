import 'package:flutter/widgets.dart';

import '../../features/camera/presentation/screens/camera_recorder_screen.dart';

/// Native builder — the real in-app camera recorder. Selected via
/// camera_route.dart's conditional export.
Widget buildCameraRecorderScreen({void Function(String)? onVideoSaved}) =>
    CameraRecorderScreen(onVideoSaved: onVideoSaved);
