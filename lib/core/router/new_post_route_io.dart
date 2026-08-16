import 'package:flutter/widgets.dart';

import '../../features/post/presentation/screens/new_post_screen.dart';

/// Native builder — the full photo_manager-based picker + dart:ui
/// editor. Selected via new_post_route.dart's conditional export.
Widget buildNewPostScreen({required bool isReelMode}) =>
    NewPostScreen(isReelMode: isReelMode);
