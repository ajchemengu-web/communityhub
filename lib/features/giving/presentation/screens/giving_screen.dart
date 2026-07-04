import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../payments/domain/models/payment_transaction_model.dart';
import '../../../payments/presentation/widgets/payment_method_sheet.dart';
import '../../data/giving_repository.dart';

const List<double> _presetAmounts = [100, 250, 500, 1000, 2500];

class GivingScreen extends ConsumerStatefulWidget {
  const GivingScreen({super.key, this.communityId, this.communityName});

  /// null = general platform give, not tied to a specific community.
  final String? communityId;
  final String? communityName;

  @override
  ConsumerState<GivingScreen> createState() => _GivingScreenState();
}

class _GivingScreenState extends ConsumerState<GivingScreen> {
  final _amountController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isAnonymous = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountController.text.trim());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: Text(widget.communityName != null
            ? 'Give to ${widget.communityName}'
            : 'Give'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => context.push(AppRoutes.givingHistory),
            child: const Text('History'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Choose an amount (KES)',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _presetAmounts
                .map((a) => ChoiceChip(
                      label: Text(a.toStringAsFixed(0)),
                      selected: _amount == a,
                      onSelected: (_) => setState(
                          () => _amountController.text = a.toStringAsFixed(0)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Custom amount',
              prefixText: 'KES ',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _messageController,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Message (optional)',
              hintText: 'Leave an encouragement with your gift',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _isAnonymous,
            onChanged: (v) => setState(() => _isAnonymous = v),
            title: const Text('Give anonymously',
                style: TextStyle(color: Colors.white)),
            activeThumbColor: AppColors.secondary,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _amount == null || _amount! <= 0 || _isSubmitting ? null : _onGive,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Give now'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onGive() async {
    final amount = _amount!;
    setState(() => _isSubmitting = true);

    try {
      final repo = GivingRepository.instance;
      final donationId = await repo.createDonation(
        amount: amount,
        currency: 'KES',
        communityId: widget.communityId,
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
        isAnonymous: _isAnonymous,
      );

      if (!mounted) return;
      final PaymentTransactionModel? transaction = await showPaymentMethodSheet(
        context,
        amount: amount,
        purpose: PaymentPurpose.donation,
        referenceId: donationId,
        recipientType: widget.communityId != null ? 'community' : 'platform',
        recipientId: widget.communityId,
      );

      if (transaction != null) {
        await repo.attachTransaction(donationId, transaction.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your gift!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
