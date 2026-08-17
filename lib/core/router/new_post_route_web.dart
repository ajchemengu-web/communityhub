import 'package:flutter/widgets.dart';

import '../../features/post/presentation/screens/new_post_screen_web.dart';

/// Web builder — the simpler image_picker-based flow. Selected via
/// new_post_route.dart's conditional export.
Widget buildNewPostScreen({required bool isReelMode}) =>
    NewPostScreenWeb(isReelMode: isReelMode);
