import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'calls_repository.dart';

class CallService {
  final SupabaseClient sb;
  RTCPeerConnection? peer;
  MediaStream? localStream;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  RealtimeChannel? channel;
  StreamSubscription? _subscription;
  late CallsRepository repo;
  String? callId;
  bool caller = false;

  CallService(this.sb) { repo = CallsRepository(sb); }

  Future<void> initialize() async { await localRenderer.initialize(); await remoteRenderer.initialize(); }

  Future<void> start({required String callId, required bool video, required bool caller}) async {
    this.callId = callId; this.caller = caller; await initialize();
    peer = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]});
    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': video});
    localRenderer.srcObject = localStream;
    for (final track in localStream!.getTracks()) { await peer!.addTrack(track, localStream!); }
    peer!.onTrack = (event) { if (event.streams.isNotEmpty) remoteRenderer.srcObject = event.streams.first; };
    peer!.onIceCandidate = (candidate) async {
      if (candidate.candidate != null) await repo.sendSignal(callId, 'candidate', {'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex});
    };
    channel = repo.subscribeToCall(callId, (call) {}, (signal) async { await _handleSignal(signal); });
    if (caller) {
      final offer = await peer!.createOffer(); await peer!.setLocalDescription(offer);
      await repo.sendSignal(callId, 'offer', {'sdp': offer.sdp});
    } else {
      for (final signal in await repo.loadSignals(callId)) await _handleSignal(signal);
    }
  }

  Future<void> _handleSignal(Map<String, dynamic> signal) async {
    if (signal['sender_id'] == sb.auth.currentUser?.id) return;
    final kind = signal['kind']?.toString(); final payload = Map<String, dynamic>.from(signal['payload'] ?? {});
    if (kind == 'offer') {
      await peer!.setRemoteDescription(RTCSessionDescription(payload['sdp'], 'offer'));
      final answer = await peer!.createAnswer(); await peer!.setLocalDescription(answer);
      await repo.sendSignal(callId!, 'answer', {'sdp': answer.sdp});
    } else if (kind == 'answer') {
      await peer!.setRemoteDescription(RTCSessionDescription(payload['sdp'], 'answer'));
    } else if (kind == 'candidate') {
      await peer!.addCandidate(RTCIceCandidate(payload['candidate'], payload['sdpMid'], payload['sdpMLineIndex']));
    }
  }

  Future<void> toggleMute(bool muted) async { for (final track in localStream?.getAudioTracks() ?? []) track.enabled = !muted; }
  Future<void> toggleCamera(bool enabled) async { for (final track in localStream?.getVideoTracks() ?? []) track.enabled = enabled; }

  Future<void> hangUp() async {
    await localStream?.dispose(); await peer?.close(); if (channel != null) await sb.removeChannel(channel!);
    localRenderer.srcObject = null; remoteRenderer.srcObject = null;
  }
  Future<void> dispose() async { await hangUp(); await localRenderer.dispose(); await remoteRenderer.dispose(); await _subscription?.cancel(); }
}
