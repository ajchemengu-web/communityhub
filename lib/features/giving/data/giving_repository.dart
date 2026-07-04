import '../../../core/services/supabase_service.dart';
import '../domain/models/donation_model.dart';

class GivingRepository {
  GivingRepository._();
  static final instance = GivingRepository._();

  final _client = SupabaseService.client;

  static const _donationSelect = '''
    id, giver_id, community_id, amount, currency, message, is_anonymous,
    payment_transaction_id, created_at,
    communities(name),
    payment_transactions(status)
  ''';

  /// Creates the donation row before any money moves. Returns the new
  /// donation id, used as `referenceId` when initiating the charge.
  Future<String> createDonation({
    required double amount,
    required String currency,
    String? communityId,
    String? message,
    bool isAnonymous = false,
  }) async {
    final uid = SupabaseService.currentUserId!;
    final row = await _client
        .from('donations')
        .insert({
          'giver_id': uid,
          'community_id': communityId,
          'amount': amount,
          'currency': currency,
          'message': message,
          'is_anonymous': isAnonymous,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Attaches the resulting payment transaction to the donation row.
  Future<void> attachTransaction(String donationId, String transactionId) async {
    await _client
        .from('donations')
        .update({'payment_transaction_id': transactionId}).eq('id', donationId);
  }

  Future<List<DonationModel>> fetchMyDonations() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _client
        .from('donations')
        .select(_donationSelect)
        .eq('giver_id', uid)
        .order('created_at', ascending: false) as List;
    return rows
        .map((r) => DonationModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
