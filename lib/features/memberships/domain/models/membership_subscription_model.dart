import '../../../payments/domain/models/payment_transaction_model.dart';
import 'membership_tier_model.dart';

class MembershipSubscriptionModel {
  const MembershipSubscriptionModel({
    required this.id,
    required this.subscriberId,
    required this.tierId,
    required this.communityId,
    required this.createdAt,
    this.tier,
    this.currentPeriodEnd,
    this.paymentTransactionId,
    this.transactionStatus,
  });

  final String id;
  final String subscriberId;
  final String tierId;
  final MembershipTierModel? tier;
  final String communityId;
  final DateTime? currentPeriodEnd;
  final String? paymentTransactionId;
  final PaymentStatus? transactionStatus;
  final DateTime createdAt;

  /// Trusts the linked `payment_transactions` row (only ever updated by
  /// a Supabase Edge Function) rather than a client-settable status
  /// column, so this can't be spoofed by editing the subscription row.
  bool get isActive =>
      transactionStatus == PaymentStatus.succeeded &&
      currentPeriodEnd != null &&
      currentPeriodEnd!.isAfter(DateTime.now());

  factory MembershipSubscriptionModel.fromMap(Map<String, dynamic> map) {
    final tierMap = map['membership_tiers'] as Map?;
    final transaction = map['payment_transactions'] as Map?;
    return MembershipSubscriptionModel(
      id: map['id'] as String,
      subscriberId: map['subscriber_id'] as String,
      tierId: map['tier_id'] as String,
      tier: tierMap != null
          ? MembershipTierModel.fromMap(Map<String, dynamic>.from(tierMap))
          : null,
      communityId: map['community_id'] as String,
      currentPeriodEnd: map['current_period_end'] != null
          ? DateTime.parse(map['current_period_end'] as String)
          : null,
      paymentTransactionId: map['payment_transaction_id'] as String?,
      transactionStatus: transaction != null
          ? _parseStatus(transaction['status'] as String? ?? 'pending')
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static PaymentStatus _parseStatus(String s) {
    switch (s) {
      case 'processing':
        return PaymentStatus.processing;
      case 'succeeded':
        return PaymentStatus.succeeded;
      case 'failed':
        return PaymentStatus.failed;
      case 'cancelled':
        return PaymentStatus.cancelled;
      default:
        return PaymentStatus.pending;
    }
  }
}
