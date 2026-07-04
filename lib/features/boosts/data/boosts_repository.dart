import '../../../core/services/supabase_service.dart';
import '../domain/models/boost_model.dart';

class BoostsRepository {
  BoostsRepository._();
  static final instance = BoostsRepository._();

  final _client = SupabaseService.client;

  /// Creates the boost row before any money moves. Returns the new
  /// boost id, used as `referenceId` when initiating the charge.
  Future<String> createBoost({
    required BoostTargetType targetType,
    required String targetId,
    required BoostPackage package,
  }) async {
    final uid = SupabaseService.currentUserId!;
    final startsAt = DateTime.now();
    final row = await _client
        .from('boosts')
        .insert({
          'target_type': targetType == BoostTargetType.event ? 'event' : 'post',
          'target_id': targetId,
          'buyer_id': uid,
          'starts_at': startsAt.toIso8601String(),
          'ends_at': startsAt.add(package.duration).toIso8601String(),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> attachTransaction(String boostId, String transactionId) async {
    await _client
        .from('boosts')
        .update({'payment_transaction_id': transactionId}).eq('id', boostId);
  }

  /// Ids of currently-active boosted posts, most-boosted first.
  Future<List<String>> fetchActiveBoostedPostIds({int limit = 10}) async {
    final rows = await _client
        .from('boosts')
        .select('target_id')
        .eq('target_type', 'post')
        .gt('ends_at', DateTime.now().toIso8601String())
        .order('rank_weight', ascending: false)
        .limit(limit) as List;
    return rows.map((r) => r['target_id'] as String).toList();
  }

  /// Ids of currently-active boosted events, most-boosted first.
  Future<List<String>> fetchActiveBoostedEventIds({int limit = 10}) async {
    final rows = await _client
        .from('boosts')
        .select('target_id')
        .eq('target_type', 'event')
        .gt('ends_at', DateTime.now().toIso8601String())
        .order('rank_weight', ascending: false)
        .limit(limit) as List;
    return rows.map((r) => r['target_id'] as String).toList();
  }
}
