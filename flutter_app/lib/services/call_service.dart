import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallService {
  final SupabaseClient sb;
  RTCPeerConnection? peer;
  MediaStream? localStream;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  RealtimeChannel? channel;
  StreamSubscription? _subscription;

  CallService(this.sb);

  Future<void> initialize() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> start({required String conversationId, required bool video}) async {
    await initialize();
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    peer = await createPeerConnection(config);
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video,
    });
    localRenderer.srcObject = localStream;
    for (final track in localStream!.getTracks()) {
      await peer!.addTrack(track, localStream!);
    }
    peer!.onTrack = (event) {
      if (event.streams.isNotEmpty) remoteRenderer.srcObject = event.streams.first;
    };
    channel = sb.channel('call:$conversationId');
    channel!.onBroadcast(event: 'signal', callback: (payload) async {
      final data = Map<String, dynamic>.from(payload);
      if (data['type'] == 'offer') {
        await peer!.setRemoteDescription(RTCSessionDescription(data['sdp'], 'offer'));
        final answer = await peer!.createAnswer();
        await peer!.setLocalDescription(answer);
        await channel!.send(type: 'broadcast', event: 'signal', payload: {'type': 'answer', 'sdp': answer.sdp});
      } else if (data['type'] == 'answer') {
        await peer!.setRemoteDescription(RTCSessionDescription(data['sdp'], 'answer'));
      } else if (data['type'] == 'candidate') {
        await peer!.addCandidate(RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
      }
    }).subscribe();
    peer!.onIceCandidate = (candidate) async {
      if (candidate.candidate != null) {
        await channel!.send(type: 'broadcast', event: 'signal', payload: {
          'type': 'candidate', 'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };
    final offer = await peer!.createOffer();
    await peer!.setLocalDescription(offer);
    await channel!.send(type: 'broadcast', event: 'signal', payload: {'type': 'offer', 'sdp': offer.sdp});
  }

  Future<void> toggleMute(bool muted) async {
    for (final track in localStream?.getAudioTracks() ?? []) track.enabled = !muted;
  }

  Future<void> toggleCamera(bool enabled) async {
    for (final track in localStream?.getVideoTracks() ?? []) track.enabled = enabled;
  }

  Future<void> hangUp() async {
    await localStream?.dispose();
    await peer?.close();
    if (channel != null) await sb.removeChannel(channel!);
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
  }

  Future<void> dispose() async {
    await hangUp();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
    await _subscription?.cancel();
  }
}
