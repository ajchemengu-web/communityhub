import 'models/payment_transaction_model.dart';

/// Provider-agnostic charge request. Callers (giving, marketplace,
/// memberships, boosts) build one of these and never see Stripe/Paystack/
/// M-Pesa specifics directly.
class ChargeRequest {
  const ChargeRequest({
    required this.provider,
    required this.amount,
    required this.purpose,
    this.referenceId,
    this.currency = 'KES',
    this.recipientType = 'platform',
    this.recipientId,
    this.phoneNumber,
    this.email,
  });

  final PaymentProviderType provider;
  final double amount;
  final PaymentPurpose purpose;
  final String? referenceId;
  final String currency;
  final String recipientType; // 'platform' | 'community'
  final String? recipientId;

  /// Required when [provider] is [PaymentProviderType.mpesa].
  final String? phoneNumber;

  /// Required when [provider] is [PaymentProviderType.paystack].
  final String? email;
}

/// Result of kicking off a charge. For Stripe this carries a client secret
/// to confirm in the Stripe SDK; for Paystack an authorization URL to open
/// in a webview; for M-Pesa nothing further — the caller just watches
/// [transactionId] resolve over realtime.
class ChargeHandle {
  const ChargeHandle({
    required this.transactionId,
    this.stripeClientSecret,
    this.paystackAuthorizationUrl,
  });

  final String transactionId;
  final String? stripeClientSecret;
  final String? paystackAuthorizationUrl;
}

abstract class PaymentGateway {
  Future<ChargeHandle> charge(ChargeRequest request);

  /// Streams the ledger row for [transactionId] until it resolves.
  Stream<PaymentTransactionModel> watchTransaction(String transactionId);
}
