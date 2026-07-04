import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../payments/domain/models/payment_transaction_model.dart';
import '../../../payments/presentation/widgets/payment_method_sheet.dart';
import '../../data/memberships_repository.dart';
import '../../domain/models/membership_tier_model.dart';

class TierPickerScreen extends StatefulWidget {
  const TierPickerScreen({
    super.key,
    required this.communityId,
    this.communityName,
    this.isOwner = false,
  });

  final String communityId;
  final String? communityName;
  final bool isOwner;

  @override
  State<TierPickerScreen> createState() => _TierPickerScreenState();
}

class _TierPickerScreenState extends State<TierPickerScreen> {
  final _repo = MembershipsRepository.instance;
  List<MembershipTierModel> _tiers = [];
  bool _isLoading = true;
  String? _subscribingTierId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final tiers = await _repo.fetchTiersForCommunity(widget.communityId);
    if (!mounted) return;
    setState(() {
      _tiers = tiers;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: Text(widget.communityName != null
            ? '${widget.communityName} · Memberships'
            : 'Memberships'),
        centerTitle: true,
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton(
              onPressed: _showCreateTierSheet,
              child: const Icon(Icons.add),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tiers.isEmpty
              ? const Center(
                  child: Text('No membership tiers yet',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tiers.length,
                  itemBuilder: (context, i) => _TierCard(
                    tier: _tiers[i],
                    isSubscribing: _subscribingTierId == _tiers[i].id,
                    onSubscribe: () => _onSubscribe(_tiers[i]),
                  ),
                ),
    );
  }

  Future<void> _onSubscribe(MembershipTierModel tier) async {
    setState(() => _subscribingTierId = tier.id);
    try {
      final subscriptionId = await _repo.createSubscription(tier);

      if (!mounted) return;
      final PaymentTransactionModel? transaction = await showPaymentMethodSheet(
        context,
        amount: tier.price,
        purpose: PaymentPurpose.membership,
        referenceId: subscriptionId,
        currency: tier.currency,
        recipientType: 'community',
        recipientId: tier.communityId,
      );

      if (transaction != null) {
        await _repo.activateSubscription(
            subscriptionId, transaction.id, tier.intervalDays);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscribed to ${tier.name}!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not subscribe: $e')),
      );
    } finally {
      if (mounted) setState(() => _subscribingTierId = null);
    }
  }

  void _showCreateTierSheet() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New membership tier',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Tier name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Perks (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Monthly price', prefixText: 'KES '),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final price = double.tryParse(priceCtrl.text.trim());
                  if (nameCtrl.text.trim().isEmpty || price == null || price <= 0) {
                    return;
                  }
                  await _repo.createTier(
                    communityId: widget.communityId,
                    name: nameCtrl.text.trim(),
                    price: price,
                    description:
                        descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  );
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  _load();
                },
                child: const Text('Create tier'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.isSubscribing,
    required this.onSubscribe,
  });

  final MembershipTierModel tier;
  final bool isSubscribing;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.darkSurface2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tier.name,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            if (tier.description != null) ...[
              const SizedBox(height: 4),
              Text(tier.description!, style: const TextStyle(color: Colors.white70)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${tier.currency} ${tier.price.toStringAsFixed(0)} / ${tier.intervalDays} days',
                  style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: isSubscribing ? null : onSubscribe,
                  child: isSubscribing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Subscribe'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
