enum PaymentPurpose { donation, order, membership, boost }

enum PaymentProviderType { stripe, paystack, mpesa }

enum PaymentStatus { pending, processing, succeeded, failed, cancelled }

class PaymentTransactionModel {
  const PaymentTransactionModel({
    required this.id,
    required this.userId,
    required this.purpose,
    required this.provider,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.referenceId,
    this.providerRef,
  });

  final String id;
  final String userId;
  final PaymentPurpose purpose;
  final String? referenceId;
  final PaymentProviderType provider;
  final String? providerRef;
  final double amount;
  final String currency;
  final PaymentStatus status;
  final DateTime createdAt;

  bool get isResolved =>
      status == PaymentStatus.succeeded ||
      status == PaymentStatus.failed ||
      status == PaymentStatus.cancelled;

  factory PaymentTransactionModel.fromMap(Map<String, dynamic> map) {
    return PaymentTransactionModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      purpose: _parsePurpose(map['purpose'] as String),
      referenceId: map['reference_id'] as String?,
      provider: _parseProvider(map['provider'] as String),
      providerRef: map['provider_ref'] as String?,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'KES',
      status: _parseStatus(map['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static PaymentPurpose _parsePurpose(String s) {
    switch (s) {
      case 'order':
        return PaymentPurpose.order;
      case 'membership':
        return PaymentPurpose.membership;
      case 'boost':
        return PaymentPurpose.boost;
      default:
        return PaymentPurpose.donation;
    }
  }

  static PaymentProviderType _parseProvider(String s) {
    switch (s) {
      case 'paystack':
        return PaymentProviderType.paystack;
      case 'mpesa':
        return PaymentProviderType.mpesa;
      default:
        return PaymentProviderType.stripe;
    }
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
