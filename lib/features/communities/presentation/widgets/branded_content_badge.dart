import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/communities_repository.dart';
import '../../domain/models/brand_partnership_model.dart';

/// Renders a small "Paid Partnership" disclosure badge when [communityId]
/// has an approved brand partnership, otherwise renders nothing. v1
/// partnerships are created/approved directly in Supabase Studio — there
/// is no in-app authoring flow yet.
class BrandedContentBadge extends StatefulWidget {
  const BrandedContentBadge({super.key, required this.communityId});
  final String communityId;

  @override
  State<BrandedContentBadge> createState() => _BrandedContentBadgeState();
}

class _BrandedContentBadgeState extends State<BrandedContentBadge> {
  BrandPartnershipModel? _partnership;

  @override
  void initState() {
    super.initState();
    CommunitiesRepository.instance
        .fetchApprovedPartnership(widget.communityId)
        .then((p) {
      if (mounted) setState(() => _partnership = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final partnership = _partnership;
    if (partnership == null) return const SizedBox.shrink();

    return Tooltip(
      message: 'In partnership with ${partnership.brandName}'
          '${partnership.description != null ? '\n${partnership.description}' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          partnership.disclosureLabel,
          style: const TextStyle(
            color: AppColors.textDarkSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
