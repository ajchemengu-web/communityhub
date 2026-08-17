import 'dart:typed_data';

import '../../../core/services/block_service.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/models/call_model.dart';
import '../domain/models/conversation_model.dart';
import '../domain/models/message_model.dart';

class ChatRepository {
  ChatRepository._();
  static final instance = ChatRepository._();

  // ── Conversations ──────────────────────────────────────────

  Future<List<ConversationModel>> fetchConversations({
    int limit = 30,
    DateTime? cursor,
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];

    var query = SupabaseService.client
        .from('conversation_members')
        .select('''
          last_read_at,
          conversations!inner(
            id, type, name, cover_url, last_message,
            last_message_at, last_message_sender_id, created_at,
            conversation_members(
              user_id,
              users!user_id(full_name, username, avatar_url)
            )
          )
        ''')
        .eq('user_id', uid);

    if (cursor != null) {
      query = query.lt('conversations(last_message_at)', cursor.toIso8601String());
    }

    final rows = await query
        .order('conversations(last_message_at)', ascending: false)
        .limit(limit) as List<dynamic>;

    final excludedIds = await BlockService.instance.fetchExcludedUserIds();

    final conversations = rows.map((row) {
      final convoMap =
          Map<String, dynamic>.from(row['conversations'] as Map);
      convoMap['last_read_at'] = row['last_read_at'];

      // Build participant list (everyone except current user)
      final memberRows =
          (convoMap['conversation_members'] as List? ?? []);
      final participants = memberRows
          .where((m) => m['user_id'] != uid)
          .map((m) {
            final p = Map<String, dynamic>.from(m as Map);
            final profile = p['users'] as Map<String, dynamic>? ?? {};
            return ParticipantModel(
              userId: p['user_id'] as String,
              fullName: profile['full_name'] as String?,
              username: profile['username'] as String?,
              avatarUrl: profile['avatar_url'] as String?,
            );
          })
          .toList();

      // (actual unread count would come from a server function; approximate here)
      convoMap['unread_count'] = 0;

      return ConversationModel.fromMap(convoMap,
          participants: participants);
    }).toList();

    if (excludedIds.isEmpty) return conversations;
    return conversations
        .where((c) => !c.participants.any((p) => excludedIds.contains(p.userId)))
        .toList();
  }

  // ── Get or create a direct conversation ───────────────────

  Future<ConversationModel> getOrCreateDirectConversation(
      String otherUserId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    if (await BlockService.instance.isBlockedEitherWay(otherUserId)) {
      throw Exception('You can\'t message this user.');
    }

    // Check if a direct conversation already exists between these two users
    final existing = await SupabaseService.client.rpc(
      'get_direct_conversation',
      params: {'user_a': uid, 'user_b': otherUserId},
    ) as List<dynamic>;

    if (existing.isNotEmpty) {
      final row = existing.first as Map<String, dynamic>;
      return _fetchSingleConversation(row['id'] as String);
    }

    // Create new direct conversation
    final convo = await SupabaseService.client
        .from('conversations')
        .insert({'type': 'direct', 'created_by': uid})
        .select()
        .single();

    final convoId = convo['id'] as String;

    // Add both participants
    await SupabaseService.client.from('conversation_members').insert([
      {'conversation_id': convoId, 'user_id': uid},
      {'conversation_id': convoId, 'user_id': otherUserId},
    ]);

    return _fetchSingleConversation(convoId);
  }

  Future<ConversationModel> _fetchSingleConversation(
      String convoId) async {
    final uid = SupabaseService.currentUserId!;

    final row = await SupabaseService.client
        .from('conversations')
        .select('''
          id, type, name, cover_url, last_message,
          last_message_at, last_message_sender_id, created_at,
          conversation_members(
            user_id,
            users!user_id(full_name, username, avatar_url)
          )
        ''')
        .eq('id', convoId)
        .single();

    final memberRows = (row['conversation_members'] as List? ?? []);
    final participants = memberRows
        .where((m) => m['user_id'] != uid)
        .map((m) {
          final p = Map<String, dynamic>.from(m as Map);
          // The query above joins this as `users!user_id(...)`, not
          // `profiles` -- this was reading the wrong key and silently
          // getting an empty map every time, which is why a freshly
          // created direct conversation's other participant always
          // showed up with no name/photo.
          final profile = p['users'] as Map<String, dynamic>? ?? {};
          return ParticipantModel(
            userId: p['user_id'] as String,
            fullName: profile['full_name'] as String?,
            username: profile['username'] as String?,
            avatarUrl: profile['avatar_url'] as String?,
          );
        })
        .toList();

    return ConversationModel.fromMap(row, participants: participants);
  }

  // ── Messages ───────────────────────────────────────────────

  Future<List<MessageModel>> fetchMessages(
    String conversationId, {
    int limit = 30,
    DateTime? cursor,
  }) async {
    final uid = SupabaseService.currentUserId!;

    var baseQuery = SupabaseService.client
        .from('messages')
        .select('''
          id, conversation_id, sender_id, content, type, media_url,
          media_thumbnail_url, reply_to_id, is_deleted, reactions,
          call_type, call_duration, call_status, created_at,
          users!sender_id(full_name, username, avatar_url)
        ''')
        .eq('conversation_id', conversationId);

    if (cursor != null) {
      baseQuery = baseQuery.lt('created_at', cursor.toIso8601String());
    }

    final rows = await baseQuery
        .order('created_at', ascending: false)
        .limit(limit + 1) as List<dynamic>;
    final hasMore = rows.length > limit;
    final slice = hasMore ? rows.sublist(0, limit) : rows;

    return slice.reversed
        .map((r) => MessageModel.fromMap(
              Map<String, dynamic>.from(r as Map),
              currentUserId: uid,
            ))
        .toList();
  }

  // ── Send message ───────────────────────────────────────────

  Future<MessageModel> sendMessage({
    required String conversationId,
    required String content,
    MessageType type = MessageType.text,
    String? replyToId,
    String? mediaUrl,
    String? mediaThumbnailUrl,
    // Call log extras
    String? callType,
    int? callDuration,
    String? callStatus,
  }) async {
    final uid = SupabaseService.currentUserId!;

    final row = await SupabaseService.client
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': uid,
          'content': content.isEmpty ? null : content,
          'type': _typeToString(type),
          'reply_to_id': replyToId,
          'media_url': mediaUrl,
          'media_thumbnail_url': mediaThumbnailUrl,
          'call_type': callType,
          'call_duration': callDuration,
          'call_status': callStatus,
        })
        .select(
            'id, conversation_id, sender_id, content, type, media_url, media_thumbnail_url, reply_to_id, is_deleted, reactions, call_type, call_duration, call_status, created_at, users!sender_id(full_name, username, avatar_url)')
        .single();

    // Update conversation last_message
    await SupabaseService.client.from('conversations').update({
      'last_message': content.isNotEmpty ? content : _typeToPreview(type),
      'last_message_at': DateTime.now().toIso8601String(),
      'last_message_sender_id': uid,
    }).eq('id', conversationId);

    return MessageModel.fromMap(
      Map<String, dynamic>.from(row),
      currentUserId: uid,
    );
  }

  // ── Upload media for chat ──────────────────────────────────

  Future<String> uploadChatMedia(
    Uint8List bytes,
    String extension,
    String conversationId,
  ) async {
    final uid = SupabaseService.currentUserId!;
    final path = 'chat/$conversationId/$uid/${DateTime.now().millisecondsSinceEpoch}.$extension';

    await SupabaseService.client.storage
        .from('chat_media')
        .uploadBinary(path, bytes);

    return SupabaseService.client.storage
        .from('chat_media')
        .getPublicUrl(path);
  }

  // ── Delete message (soft) ──────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    await SupabaseService.client
        .from('messages')
        .update({'is_deleted': true})
        .eq('id', messageId);
  }

  // ── Toggle reaction ────────────────────────────────────────

  Future<Map<String, List<String>>> toggleReaction(
    String messageId,
    Map<String, List<String>> currentReactions,
    String emoji,
  ) async {
    final uid = SupabaseService.currentUserId!;
    final updated =
        Map<String, List<String>>.from(currentReactions);

    final users = List<String>.from(updated[emoji] ?? []);
    if (users.contains(uid)) {
      users.remove(uid);
    } else {
      users.add(uid);
    }

    if (users.isEmpty) {
      updated.remove(emoji);
    } else {
      updated[emoji] = users;
    }

    // Serialise: Map<String, List<String>> → Map<String, dynamic>
    final serialised = updated.map((k, v) => MapEntry(k, v));

    await SupabaseService.client
        .from('messages')
        .update({'reactions': serialised})
        .eq('id', messageId);

    return updated;
  }

  // ── Mark conversation as read ──────────────────────────────

  Future<void> markAsRead(String conversationId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    await SupabaseService.client
        .from('conversation_members')
        .update({'last_read_at': DateTime.now().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('user_id', uid);
  }

  // ── Calls ──────────────────────────────────────────────────

  Future<CallModel> initiateCall({
    required String conversationId,
    required String receiverId,
    required CallType type,
  }) async {
    final uid = SupabaseService.currentUserId!;
    final channelName =
        'call_${conversationId}_${DateTime.now().millisecondsSinceEpoch}';

    final row = await SupabaseService.client
        .from('calls')
        .insert({
          'conversation_id': conversationId,
          'caller_id': uid,
          'receiver_id': receiverId,
          'type': type == CallType.video ? 'video' : 'audio',
          'status': 'ringing',
          'channel_name': channelName,
        })
        .select(
            'id, conversation_id, caller_id, receiver_id, type, status, channel_name, created_at, started_at, ended_at')
        .single();

    return CallModel.fromMap(row);
  }

  Future<CallModel> updateCallStatus(
      String callId, CallStatus status) async {
    final updates = <String, dynamic>{
      'status': _callStatusToString(status),
    };
    if (status == CallStatus.active) {
      updates['started_at'] = DateTime.now().toIso8601String();
    } else if (status == CallStatus.ended ||
        status == CallStatus.missed ||
        status == CallStatus.declined) {
      updates['ended_at'] = DateTime.now().toIso8601String();
    }

    final row = await SupabaseService.client
        .from('calls')
        .update(updates)
        .eq('id', callId)
        .select()
        .single();

    return CallModel.fromMap(row);
  }

  /// Fetches a LiveKit access token scoped to this specific call. Minted
  /// server-side by the `livekit-call-token` Edge Function, which looks
  /// up [callId] with a service-role client and rejects the request
  /// unless the caller is actually the call's caller_id or receiver_id —
  /// unlike the live-streaming feature's `livekit-generate-token`
  /// (any authenticated user, any room name — correct for a public
  /// stream audience, wrong for a private 1:1 call), this can't be used
  /// to join someone else's call.
  Future<String> fetchLiveKitCallToken(String callId) async {
    final res = await SupabaseService.client.functions
        .invoke('livekit-call-token', body: {'callId': callId});
    final data = res.data as Map<String, dynamic>;
    return data['token'] as String;
  }

  // ── Helpers ───────────────────────────────────────────────

  static String _typeToString(MessageType t) {
    switch (t) {
      case MessageType.image:
        return 'image';
      case MessageType.video:
        return 'video';
      case MessageType.audio:
        return 'audio';
      case MessageType.callLog:
        return 'call_log';
      default:
        return 'text';
    }
  }

  static String _typeToPreview(MessageType t) {
    switch (t) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.audio:
        return '🎙 Voice message';
      default:
        return '';
    }
  }

  static String _callStatusToString(CallStatus s) {
    switch (s) {
      case CallStatus.active:
        return 'active';
      case CallStatus.ended:
        return 'ended';
      case CallStatus.missed:
        return 'missed';
      case CallStatus.declined:
        return 'declined';
      default:
        return 'ringing';
    }
  }
}
