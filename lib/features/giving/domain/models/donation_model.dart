import '../../../payments/domain/models/payment_transaction_model.dart';

class DonationModel {
  const DonationModel({
    required this.id,
    required this.giverId,
    required this.amount,
    required this.currency,
    required this.isAnonymous,
    required this.createdAt,
    this.communityId,
    this.communityName,
    this.message,
    this.paymentTransactionId,
    this.transactionStatus,
  });

  final String id;
  final String giverId;
  final String? communityId;
  final String? communityName;
  final double amount;
  final String currency;
  final String? message;
  final bool isAnonymous;
  final String? paymentTransactionId;
  final PaymentStatus? transactionStatus;
  final DateTime createdAt;

  bool get isSucceeded => transactionStatus == PaymentStatus.succeeded;

  factory DonationModel.fromMap(Map<String, dynamic> map) {
    final community = map['communities'] as Map?;
    final transaction = map['payment_transactions'] as Map?;
    return DonationModel(
      id: map['id'] as String,
      giverId: map['giver_id'] as String,
      communityId: map['community_id'] as String?,
      communityName: community?['name'] as String?,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'KES',
      message: map['message'] as String?,
      isAnonymous: (map['is_anonymous'] as bool?) ?? false,
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
