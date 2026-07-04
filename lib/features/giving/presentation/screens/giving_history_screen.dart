import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/models/donation_model.dart';
import '../providers/giving_provider.dart';

class GivingHistoryScreen extends ConsumerWidget {
  const GivingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(givingHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('My Giving'),
        centerTitle: true,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(givingHistoryProvider.notifier).refresh(),
              child: state.donations.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text('No gifts yet',
                              style: TextStyle(color: Colors.white54)),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          color: AppColors.darkSurface2,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total given',
                                    style: TextStyle(color: Colors.white70)),
                                Text(
                                  'KES ${state.totalGiven.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: AppColors.secondary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...state.donations.map((d) => _DonationTile(donation: d)),
                      ],
                    ),
            ),
    );
  }
}

class _DonationTile extends StatelessWidget {
  const _DonationTile({required this.donation});
  final DonationModel donation;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.darkSurface2,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          donation.communityName ?? 'CommunityHub',
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          DateFormat.yMMMd().add_jm().format(donation.createdAt),
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${donation.currency} ${donation.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: AppColors.secondary, fontWeight: FontWeight.bold),
            ),
            Text(
              _statusLabel(donation),
              style: TextStyle(
                fontSize: 12,
                color: donation.isSucceeded
                    ? AppColors.success
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(DonationModel d) {
    switch (d.transactionStatus) {
      case null:
        return 'Pending';
      default:
        return d.isSucceeded ? 'Completed' : d.transactionStatus!.name;
    }
  }
}
