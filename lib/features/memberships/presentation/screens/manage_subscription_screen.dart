import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/models/membership_subscription_model.dart';
import '../providers/memberships_provider.dart';

class ManageSubscriptionScreen extends ConsumerWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mySubscriptionsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('My Memberships'),
        centerTitle: true,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(mySubscriptionsProvider.notifier).refresh(),
              child: state.subscriptions.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text('No memberships yet',
                              style: TextStyle(color: Colors.white54)),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.subscriptions.length,
                      itemBuilder: (context, i) =>
                          _SubscriptionTile(subscription: state.subscriptions[i]),
                    ),
            ),
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({required this.subscription});
  final MembershipSubscriptionModel subscription;

  @override
  Widget build(BuildContext context) {
    final tier = subscription.tier;
    return Card(
      color: AppColors.darkSurface2,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(tier?.name ?? 'Membership', style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          subscription.currentPeriodEnd != null
              ? 'Renews / expires ${DateFormat.yMMMd().format(subscription.currentPeriodEnd!)}'
              : 'Pending payment',
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: Text(
          subscription.isActive ? 'Active' : 'Inactive',
          style: TextStyle(
            color: subscription.isActive ? AppColors.success : AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
