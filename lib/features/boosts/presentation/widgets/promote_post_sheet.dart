import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../payments/domain/models/payment_transaction_model.dart';
import '../../../payments/presentation/widgets/payment_method_sheet.dart';
import '../../data/boosts_repository.dart';
import '../../domain/models/boost_model.dart';

/// Opens the promote flow for [targetId] (a post or event). Returns true
/// if the boost was successfully paid for.
Future<bool> showPromoteSheet(
  BuildContext context, {
  required BoostTargetType targetType,
  required String targetId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.darkSurface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _PromoteSheet(targetType: targetType, targetId: targetId),
  );
  return result ?? false;
}

class _PromoteSheet extends StatefulWidget {
  const _PromoteSheet({required this.targetType, required this.targetId});
  final BoostTargetType targetType;
  final String targetId;

  @override
  State<_PromoteSheet> createState() => _PromoteSheetState();
}

class _PromoteSheetState extends State<_PromoteSheet> {
  BoostPackage _selected = BoostPackage.all.first;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.targetType == BoostTargetType.event
                  ? 'Promote this event'
                  : 'Promote this post',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Boosted content is shown to more people in the feed.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ...BoostPackage.all.map((pkg) => Card(
                  color: _selected == pkg
                      ? AppColors.primaryLight
                      : AppColors.darkSurface2,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(pkg.label),
                    trailing: Text('KES ${pkg.priceKes.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppColors.secondary)),
                    onTap: () => setState(() => _selected = pkg),
                  ),
                )),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _onPromote,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Promote now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPromote() async {
    setState(() => _isSubmitting = true);
    try {
      final repo = BoostsRepository.instance;
      final boostId = await repo.createBoost(
        targetType: widget.targetType,
        targetId: widget.targetId,
        package: _selected,
      );

      if (!mounted) return;
      final PaymentTransactionModel? transaction = await showPaymentMethodSheet(
        context,
        amount: _selected.priceKes,
        purpose: PaymentPurpose.boost,
        referenceId: boostId,
        recipientType: 'platform',
      );

      if (transaction != null) {
        await repo.attachTransaction(boostId, transaction.id);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start promotion: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
