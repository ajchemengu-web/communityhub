import '../../../core/services/supabase_service.dart';
import '../domain/models/membership_subscription_model.dart';
import '../domain/models/membership_tier_model.dart';

class MembershipsRepository {
  MembershipsRepository._();
  static final instance = MembershipsRepository._();

  final _client = SupabaseService.client;

  static const _subscriptionSelect = '''
    id, subscriber_id, tier_id, community_id, current_period_end,
    payment_transaction_id, created_at,
    membership_tiers(id, community_id, name, description, price, currency, interval_days, is_active),
    payment_transactions(status)
  ''';

  // ── Tiers ─────────────────────────────────────────────────────

  Future<List<MembershipTierModel>> fetchTiersForCommunity(String communityId) async {
    final rows = await _client
        .from('membership_tiers')
        .select('*, communities(name)')
        .eq('community_id', communityId)
        .eq('is_active', true)
        .order('price') as List;
    return rows
        .map((r) => MembershipTierModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<MembershipTierModel> createTier({
    required String communityId,
    required String name,
    required double price,
    String currency = 'KES',
    String? description,
    int intervalDays = 30,
  }) async {
    final row = await _client
        .from('membership_tiers')
        .insert({
          'community_id': communityId,
          'name': name,
          'description': description,
          'price': price,
          'currency': currency,
          'interval_days': intervalDays,
        })
        .select('*, communities(name)')
        .single();
    return MembershipTierModel.fromMap(row);
  }

  // ── Subscriptions ─────────────────────────────────────────────

  /// Creates the subscription row before any money moves. Returns the
  /// new subscription id, used as `referenceId` when initiating the
  /// charge.
  Future<String> createSubscription(MembershipTierModel tier) async {
    final uid = SupabaseService.currentUserId!;
    final row = await _client
        .from('membership_subscriptions')
        .insert({
          'subscriber_id': uid,
          'tier_id': tier.id,
          'community_id': tier.communityId,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Attaches the transaction and starts the billing period. The
  /// subscription is only genuinely "active" once the linked
  /// payment_transactions row reaches 'succeeded' — see
  /// [MembershipSubscriptionModel.isActive].
  Future<void> activateSubscription(
    String subscriptionId,
    String transactionId,
    int intervalDays,
  ) async {
    await _client.from('membership_subscriptions').update({
      'payment_transaction_id': transactionId,
      'current_period_end':
          DateTime.now().add(Duration(days: intervalDays)).toIso8601String(),
    }).eq('id', subscriptionId);
  }

  Future<List<MembershipSubscriptionModel>> fetchMySubscriptions() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _client
        .from('membership_subscriptions')
        .select(_subscriptionSelect)
        .eq('subscriber_id', uid)
        .order('created_at', ascending: false) as List;
    return rows
        .map((r) =>
            MembershipSubscriptionModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Whether the current user has an active subscription to any tier in
  /// [communityId] — used to gate subscriber-only announcements.
  Future<bool> hasActiveSubscription(String communityId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return false;
    final rows = await _client
        .from('membership_subscriptions')
        .select(_subscriptionSelect)
        .eq('subscriber_id', uid)
        .eq('community_id', communityId) as List;
    return rows
        .map((r) =>
            MembershipSubscriptionModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .any((s) => s.isActive);
  }
}
