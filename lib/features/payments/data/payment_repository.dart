import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/models/payment_transaction_model.dart';
import '../domain/payment_gateway.dart';

class PaymentRepository implements PaymentGateway {
  PaymentRepository._();
  static final instance = PaymentRepository._();

  final _client = SupabaseService.client;

  @override
  Future<ChargeHandle> charge(ChargeRequest request) async {
    switch (request.provider) {
      case PaymentProviderType.stripe:
        return _chargeWithStripe(request);
      case PaymentProviderType.paystack:
        return _chargeWithPaystack(request);
      case PaymentProviderType.mpesa:
        return _chargeWithMpesa(request);
    }
  }

  Future<ChargeHandle> _chargeWithStripe(ChargeRequest request) async {
    final res = await _client.functions.invoke('stripe-create-intent', body: {
      'amount': request.amount,
      'currency': request.currency,
      'purpose': _purposeString(request.purpose),
      'referenceId': request.referenceId,
      'recipientType': request.recipientType,
      'recipientId': request.recipientId,
    });
    final data = res.data as Map<String, dynamic>;
    return ChargeHandle(
      transactionId: data['transactionId'] as String,
      stripeClientSecret: data['clientSecret'] as String?,
    );
  }

  Future<ChargeHandle> _chargeWithPaystack(ChargeRequest request) async {
    if (request.email == null) {
      throw ArgumentError('email is required for Paystack charges');
    }
    final res = await _client.functions.invoke('paystack-init', body: {
      'amount': request.amount,
      'currency': request.currency,
      'purpose': _purposeString(request.purpose),
      'referenceId': request.referenceId,
      'recipientType': request.recipientType,
      'recipientId': request.recipientId,
      'email': request.email,
    });
    final data = res.data as Map<String, dynamic>;
    return ChargeHandle(
      transactionId: data['transactionId'] as String,
      paystackAuthorizationUrl: data['authorizationUrl'] as String?,
    );
  }

  Future<ChargeHandle> _chargeWithMpesa(ChargeRequest request) async {
    if (request.phoneNumber == null) {
      throw ArgumentError('phoneNumber is required for M-Pesa charges');
    }
    final res = await _client.functions.invoke('mpesa-stk-push', body: {
      'amount': request.amount,
      'phoneNumber': request.phoneNumber,
      'purpose': _purposeString(request.purpose),
      'referenceId': request.referenceId,
      'recipientType': request.recipientType,
      'recipientId': request.recipientId,
    });
    final data = res.data as Map<String, dynamic>;
    return ChargeHandle(transactionId: data['transactionId'] as String);
  }

  @override
  Stream<PaymentTransactionModel> watchTransaction(String transactionId) {
    return _client
        .from(AppConstants.tablePaymentTransactions)
        .stream(primaryKey: ['id'])
        .eq('id', transactionId)
        .map((rows) => PaymentTransactionModel.fromMap(
              Map<String, dynamic>.from(rows.first),
            ));
  }

  Future<List<PaymentTransactionModel>> fetchMyTransactions() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _client
        .from(AppConstants.tablePaymentTransactions)
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false) as List;
    return rows
        .map((r) =>
            PaymentTransactionModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  static String _purposeString(PaymentPurpose p) {
    switch (p) {
      case PaymentPurpose.donation:
        return 'donation';
      case PaymentPurpose.order:
        return 'order';
      case PaymentPurpose.membership:
        return 'membership';
      case PaymentPurpose.boost:
        return 'boost';
    }
  }
}
