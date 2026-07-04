enum FulfillmentStatus { pending, paid, shipped, completed, cancelled }

class OrderModel {
  const OrderModel({
    required this.id,
    required this.buyerId,
    required this.productId,
    required this.sellerId,
    required this.quantity,
    required this.amount,
    required this.currency,
    required this.fulfillmentStatus,
    required this.createdAt,
    this.productTitle,
    this.buyerName,
    this.paymentTransactionId,
  });

  final String id;
  final String buyerId;
  final String? buyerName;
  final String productId;
  final String? productTitle;
  final String sellerId;
  final int quantity;
  final double amount;
  final String currency;
  final FulfillmentStatus fulfillmentStatus;
  final String? paymentTransactionId;
  final DateTime createdAt;

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    final product = map['products'] as Map?;
    final buyer = map['buyer'] as Map?;
    return OrderModel(
      id: map['id'] as String,
      buyerId: map['buyer_id'] as String,
      buyerName: buyer?['full_name'] as String?,
      productId: map['product_id'] as String,
      productTitle: product?['title'] as String?,
      sellerId: map['seller_id'] as String,
      quantity: (map['quantity'] as int?) ?? 1,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'KES',
      fulfillmentStatus: _parseStatus(map['fulfillment_status'] as String? ?? 'pending'),
      paymentTransactionId: map['payment_transaction_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static FulfillmentStatus _parseStatus(String s) {
    switch (s) {
      case 'paid':
        return FulfillmentStatus.paid;
      case 'shipped':
        return FulfillmentStatus.shipped;
      case 'completed':
        return FulfillmentStatus.completed;
      case 'cancelled':
        return FulfillmentStatus.cancelled;
      default:
        return FulfillmentStatus.pending;
    }
  }

  static String statusString(FulfillmentStatus s) {
    switch (s) {
      case FulfillmentStatus.paid:
        return 'paid';
      case FulfillmentStatus.shipped:
        return 'shipped';
      case FulfillmentStatus.completed:
        return 'completed';
      case FulfillmentStatus.cancelled:
        return 'cancelled';
      case FulfillmentStatus.pending:
        return 'pending';
    }
  }
}
