import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallRecord {
  final String id, callerId, calleeId, type, status, createdAt;
  final String? endedAt;
  CallRecord.fromMap(Map<String, dynamic> m)
      : id = m['id'].toString(), callerId = m['caller_id'].toString(),
        calleeId = m['callee_id'].toString(), type = m['type'].toString(),
        status = m['status'].toString(), createdAt = m['created_at'].toString(),
        endedAt = m['ended_at']?.toString();
}

class CallsRepository {
  final SupabaseClient sb;
  CallsRepository(this.sb);

  Future<CallRecord> createCall(String calleeId, String type) async {
    final user = sb.auth.currentUser;
    if (user == null) throw Exception('You must be signed in');
    final row = await sb.from('calls').insert({
      'caller_id': user.id, 'callee_id': calleeId, 'type': type, 'status': 'ringing'
    }).select().single();
    final call = CallRecord.fromMap(row);
    try { await sb.functions.invoke('send-call-push', body: {'callId': call.id}); } catch (_) {}
    return call;
  }

  Future<CallRecord> getCall(String id) async =>
      CallRecord.fromMap(await sb.from('calls').select().eq('id', id).single());

  Future<void> setStatus(String id, String status) async {
    final patch = <String, dynamic>{'status': status};
    if (status == 'ended' || status == 'rejected') patch['ended_at'] = DateTime.now().toUtc().toIso8601String();
    await sb.from('calls').update(patch).eq('id', id);
  }

  Future<void> sendSignal(String callId, String kind, Map<String, dynamic> payload) async {
    final user = sb.auth.currentUser;
    if (user == null) throw Exception('You must be signed in');
    await sb.from('call_signals').insert({'call_id': callId, 'sender_id': user.id, 'kind': kind, 'payload': payload});
  }

  Future<List<Map<String, dynamic>>> loadSignals(String callId) async =>
      List<Map<String, dynamic>>.from(await sb.from('call_signals').select().eq('call_id', callId).order('created_at'));

  RealtimeChannel subscribeToCall(String callId, void Function(CallRecord) onCall, void Function(Map<String,dynamic>) onSignal) =>
      sb.channel('call:$callId')
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'calls', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: callId), callback: (p) => onCall(CallRecord.fromMap(p.newRecord)))
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'call_signals', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'call_id', value: callId), callback: (p) => onSignal(p.newRecord))
        ..subscribe();

  RealtimeChannel subscribeToIncoming(String userId, void Function(CallRecord) onCall) =>
      sb.channel('incoming-calls:$userId')
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'calls', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'callee_id', value: userId), callback: (p) => onCall(CallRecord.fromMap(p.newRecord)))
        ..subscribe();
}
