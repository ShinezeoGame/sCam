import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../data/net/protocol.dart';
import '../data/system_bridge.dart';
import '../models/camera.dart';
import '../ui/theme.dart';
import 'media.dart';

/// Configuration commune : aucun serveur STUN ou TURN. Seules les adresses du réseau local
/// sont échangées, la transmission ne peut donc pas passer par Internet.
const _rtcConfig = <String, dynamic>{'iceServers': <Map<String, dynamic>>[], 'sdpSemantics': 'unified-plan'};

bool _audioConfigured = false;

/// Sur Android, le son passe par le haut-parleur, comme un média (et non comme un appel,
/// qui le dirigerait vers l'écouteur).
Future<void> _configureAudio() async {
  if (_audioConfigured || !Platform.isAndroid) return;
  _audioConfigured = true;
  try {
    await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.media);
  } on Object {
    // Configuration par défaut.
  }
}

Map<String, dynamic> _candidateMessage(RTCIceCandidate c) => {
  'type': 'candidat',
  'candidat': c.candidate,
  'mid': c.sdpMid,
  'index': c.sdpMLineIndex,
};

Future<void> _addCandidate(RTCPeerConnection pc, Map<String, dynamic> message) async {
  final candidate = message['candidat'];
  if (candidate is! String || !isLocalCandidate(candidate)) return;
  final mid = message['mid'], index = message['index'];
  await pc.addCandidate(RTCIceCandidate(candidate, mid is String ? mid : null, index is int ? index : null));
}

/// Caméra réelle (Android), par WebRTC.
class WebRtcCameraMedia implements CameraMedia {
  WebRtcCameraMedia(this.bridge);

  final SystemBridge bridge;
  MediaStream? _stream;
  final _sessions = <_CameraSession>{};
  final _preview = RTCVideoRenderer();
  bool _previewReady = false;
  bool _hasTorch = false;

  // Liaison interne (la caméra vers elle-même) qui garde le micro ouvert : sans elle,
  // WebRTC ne l'ouvre que lorsqu'un écran regarde, et le bruit ne serait pas surveillé.
  RTCPeerConnection? _loopSend;
  RTCPeerConnection? _loopReceive;

  @override
  bool get running => _stream != null;

  @override
  bool get hasTorch => _hasTorch;

  Map<String, dynamic> _constraints(CameraSettings s) => {
    // Le traitement « appel » (annulation d'écho, réduction de bruit, gain automatique)
    // atténuerait justement les pleurs : il est coupé.
    'audio': {
      'echoCancellation': false,
      'noiseSuppression': false,
      'autoGainControl': false,
      'optional': [
        {'googEchoCancellation': false},
        {'googNoiseSuppression': false},
        {'googAutoGainControl': false},
        {'googHighpassFilter': false},
      ],
    },
    'video': {
      'facingMode': s.lens == Lens.front ? 'user' : 'environment',
      'width': s.quality.width,
      'height': s.quality.height,
      'frameRate': 20,
    },
  };

  @override
  Future<void> start(CameraSettings settings) async {
    if (_stream != null) return;
    await _configureAudio();
    final stream = await navigator.mediaDevices.getUserMedia(_constraints(settings));
    _stream = stream;
    if (!_previewReady) {
      await _preview.initialize();
      _previewReady = true;
    }
    _preview.srcObject = stream;
    await _afterCapture(settings);
    await _openLoop(stream);
  }

  Future<void> _afterCapture(CameraSettings settings) async {
    final stream = _stream;
    if (stream == null) return;
    final video = stream.getVideoTracks().firstOrNull;
    final audio = stream.getAudioTracks().firstOrNull;
    try {
      _hasTorch = video != null && await video.hasTorch();
      if (_hasTorch && settings.torch) await video!.setTorch(true);
    } on Object {
      _hasTorch = false;
    }
    await bridge.startAnalysis(videoTrackId: video?.id, audioTrackId: audio?.id);
  }

  Future<void> _openLoop(MediaStream stream) async {
    final audio = stream.getAudioTracks().firstOrNull;
    if (audio == null) return;
    try {
      final send = await createPeerConnection(_rtcConfig);
      final receive = await createPeerConnection(_rtcConfig);
      _loopSend = send;
      _loopReceive = receive;
      send.onIceCandidate = (c) => receive.addCandidate(c);
      receive.onIceCandidate = (c) => send.addCandidate(c);
      // Le son reçu par la liaison interne ne doit pas sortir du haut-parleur.
      receive.onTrack = (event) => event.track.enabled = false;
      await send.addTrack(audio, stream);
      final offer = await send.createOffer();
      await send.setLocalDescription(offer);
      await receive.setRemoteDescription(offer);
      final answer = await receive.createAnswer();
      await receive.setLocalDescription(answer);
      await send.setRemoteDescription(answer);
    } on Object {
      // Sans liaison interne, le bruit n'est mesuré que lorsqu'un écran regarde.
    }
  }

  @override
  Future<void> stop() async {
    for (final session in _sessions.toList()) {
      await session.close();
    }
    await bridge.stopAnalysis();
    await _loopSend?.close();
    await _loopReceive?.close();
    _loopSend = _loopReceive = null;
    final stream = _stream;
    _stream = null;
    if (_previewReady) _preview.srcObject = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
    _hasTorch = false;
  }

  @override
  Future<void> apply(CameraSettings previous, CameraSettings next) async {
    final stream = _stream;
    if (stream == null) return;
    if (previous.quality != next.quality) {
      // Nouvelle résolution : la capture est rouverte et les écrans reçoivent la nouvelle image.
      final sessions = _sessions.toList();
      await bridge.stopAnalysis();
      await _loopSend?.close();
      await _loopReceive?.close();
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      final fresh = await navigator.mediaDevices.getUserMedia(_constraints(next));
      _stream = fresh;
      _preview.srcObject = fresh;
      await stream.dispose();
      for (final session in sessions) {
        await session.replaceTracks(fresh);
      }
      await _afterCapture(next);
      await _openLoop(fresh);
      return;
    }
    final video = stream.getVideoTracks().firstOrNull;
    if (video == null) return;
    if (previous.lens != next.lens) {
      if (previous.torch) await _setTorch(video, false);
      await Helper.switchCamera(video);
      try {
        _hasTorch = await video.hasTorch();
      } on Object {
        _hasTorch = false;
      }
      if (next.torch) await _setTorch(video, true);
    } else if (previous.torch != next.torch) {
      await _setTorch(video, next.torch);
    }
  }

  Future<void> _setTorch(MediaStreamTrack video, bool on) async {
    try {
      if (_hasTorch) await video.setTorch(on);
    } on Object {
      // Lampe occupée ou absente.
    }
  }

  @override
  Future<MediaSession> openSession(SignalSink signal) async {
    final stream = _stream;
    if (stream == null) throw StateError('La caméra ne filme pas');
    final pc = await createPeerConnection(_rtcConfig);
    final session = _CameraSession(pc, signal, onClosed: (s) => _sessions.remove(s));
    _sessions.add(session);
    pc.onIceCandidate = (c) => signal(_candidateMessage(c));
    for (final track in stream.getTracks()) {
      session.senders.add(await pc.addTrack(track, stream));
    }
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    signal({'type': 'offre', 'sdp': offer.sdp});
    return session;
  }

  @override
  Future<Measures> measure() async {
    final raw = await bridge.measure();
    if (raw == null) return const Measures();
    return Measures(sound: soundLevelFromDb(raw.soundDb), motion: raw.motion);
  }

  @override
  Future<Uint8List?> snapshot() => bridge.latestJpeg();

  @override
  Widget preview() => _previewReady
      ? RTCVideoView(_preview, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
      : const SizedBox.shrink();
}

class _CameraSession implements MediaSession {
  _CameraSession(this.pc, this.signal, {required this.onClosed});

  final RTCPeerConnection pc;
  final SignalSink signal;
  final void Function(_CameraSession) onClosed;
  final senders = <RTCRtpSender>[];
  bool _closed = false;

  Future<void> replaceTracks(MediaStream stream) async {
    for (final sender in senders) {
      final kind = sender.track?.kind;
      final track = kind == 'audio' ? stream.getAudioTracks().firstOrNull : stream.getVideoTracks().firstOrNull;
      if (track != null) await sender.replaceTrack(track);
    }
  }

  @override
  Future<void> onSignal(Map<String, dynamic> message) async {
    if (_closed) return;
    switch (message['type']) {
      case 'reponse':
        final sdp = message['sdp'];
        if (sdp is String) await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      case 'candidat':
        await _addCandidate(pc, message);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    onClosed(this);
    await pc.close();
  }
}

/// Réception réelle (Android et Windows), par WebRTC.
class WebRtcScreenMedia implements ScreenMedia {
  @override
  Future<ViewerSession> openSession(SignalSink signal) async {
    await _configureAudio();
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final pc = await createPeerConnection(_rtcConfig);
    final session = _ViewerSession(pc, renderer, signal);
    pc.onIceCandidate = (c) => signal(_candidateMessage(c));
    pc.onTrack = session._onTrack;
    pc.onConnectionState = (state) =>
        session.connected.value = state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    if (Platform.isAndroid) {
      try {
        await Helper.setSpeakerphoneOn(true);
      } on Object {
        // Sortie par défaut.
      }
    }
    return session;
  }
}

class _ViewerSession implements ViewerSession {
  _ViewerSession(this.pc, this.renderer, this.signal);

  final RTCPeerConnection pc;
  final RTCVideoRenderer renderer;
  final SignalSink signal;
  bool _muted = false;
  bool _closed = false;
  MediaStream? _stream;

  @override
  final connected = ValueNotifier(false);

  void _onTrack(RTCTrackEvent event) {
    if (event.track.kind == 'audio') event.track.enabled = !_muted;
    final stream = event.streams.firstOrNull;
    if (stream != null && stream != _stream) {
      _stream = stream;
      renderer.srcObject = stream;
    }
  }

  @override
  void setMuted(bool muted) {
    _muted = muted;
    for (final track in _stream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> onSignal(Map<String, dynamic> message) async {
    if (_closed) return;
    switch (message['type']) {
      case 'offre':
        final sdp = message['sdp'];
        if (sdp is! String) return;
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        signal({'type': 'reponse', 'sdp': answer.sdp});
      case 'candidat':
        await _addCandidate(pc, message);
    }
  }

  @override
  Widget view({bool brighten = false, bool cover = false}) {
    final video = RTCVideoView(
      renderer,
      objectFit: cover
          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
          : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
    );
    return brighten ? ColorFiltered(colorFilter: nightFilter, child: video) : video;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    connected.value = false;
    renderer.srcObject = null;
    await pc.close();
    await renderer.dispose();
  }
}
