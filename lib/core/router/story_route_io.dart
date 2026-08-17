import 'package:flutter/widgets.dart';

import '../../features/stories/presentation/screens/story_creator_screen.dart';

/// Native builder — the real story creator (camera capture, RepaintBoundary
/// compositing, video compression). Selected via story_route.dart's
/// conditional export.
Widget buildStoryCreatorScreen() => const StoryCreatorScreen();
