import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class ReelsScreen extends StatelessWidget {
  const ReelsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: const Center(child: Text('Reels — Building Day 9', style: AppTextStyles.titleSmall)),
    );
  }
}
