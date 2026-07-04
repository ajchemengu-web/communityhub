enum BoostTargetType { post, event }

class BoostModel {
  const BoostModel({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.buyerId,
    required this.startsAt,
    required this.endsAt,
    required this.rankWeight,
    this.paymentTransactionId,
  });

  final String id;
  final BoostTargetType targetType;
  final String targetId;
  final String buyerId;
  final DateTime startsAt;
  final DateTime endsAt;
  final double rankWeight;
  final String? paymentTransactionId;

  bool get isActive => DateTime.now().isBefore(endsAt);

  factory BoostModel.fromMap(Map<String, dynamic> map) {
    return BoostModel(
      id: map['id'] as String,
      targetType: (map['target_type'] as String) == 'event'
          ? BoostTargetType.event
          : BoostTargetType.post,
      targetId: map['target_id'] as String,
      buyerId: map['buyer_id'] as String,
      startsAt: DateTime.parse(map['starts_at'] as String),
      endsAt: DateTime.parse(map['ends_at'] as String),
      rankWeight: (map['rank_weight'] as num?)?.toDouble() ?? 1.0,
      paymentTransactionId: map['payment_transaction_id'] as String?,
    );
  }
}

/// Fixed promotion packages — duration mapped to price (KES).
class BoostPackage {
  const BoostPackage(this.duration, this.priceKes, this.label);
  final Duration duration;
  final double priceKes;
  final String label;

  static const List<BoostPackage> all = [
    BoostPackage(Duration(hours: 24), 150, '24 hours'),
    BoostPackage(Duration(days: 3), 350, '3 days'),
    BoostPackage(Duration(days: 7), 700, '7 days'),
  ];
}
