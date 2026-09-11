import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/call_service.dart';
import 'services/calls_repository.dart';

class CallPage extends StatefulWidget {
  final String callId; final bool video; final bool caller;
  const CallPage({super.key, required this.callId, required this.video, required this.caller});
  @override State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final CallService service; late final CallsRepository repo;
  bool muted = false, camera = true; bool loading = true;

  @override void initState() { super.initState(); service = CallService(Supabase.instance.client); repo = CallsRepository(Supabase.instance.client); _start(); }

  Future<void> _start() async {
    try { await service.start(callId: widget.callId, video: widget.video, caller: widget.caller); await repo.setStatus(widget.callId, 'active'); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _hangUp() async { await repo.setStatus(widget.callId, 'ended'); await service.hangUp(); if (mounted) Navigator.pop(context); }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(child: Stack(children: [
      if (widget.video) Positioned.fill(child: RTCVideoView(service.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
      if (widget.video) Positioned(right: 16, top: 16, width: 120, height: 170, child: RTCVideoView(service.localRenderer, mirror: true)),
      if (!widget.video) const Center(child: Icon(Icons.call, color: Colors.white, size: 90)),
      if (loading) const Center(child: CircularProgressIndicator()),
      Positioned(bottom: 30, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(iconSize: 30, color: Colors.white, onPressed: () async { muted = !muted; await service.toggleMute(muted); setState(() {}); }, icon: Icon(muted ? Icons.mic_off : Icons.mic)),
        if (widget.video) IconButton(iconSize: 30, color: Colors.white, onPressed: () async { camera = !camera; await service.toggleCamera(camera); setState(() {}); }, icon: Icon(camera ? Icons.videocam : Icons.videocam_off)),
        const SizedBox(width: 25),
        FloatingActionButton(backgroundColor: Colors.red, onPressed: _hangUp, child: const Icon(Icons.call_end)),
      ])),
    ])),
  );
  @override void dispose() { service.dispose(); super.dispose(); }
}
