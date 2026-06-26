import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/call_model.dart';
import '../providers/call_provider.dart';

// ── Call Screen ────────────────────────────────────────────────────

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.callId});

  final String callId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callProvider);
    final call = state.activeCall;

    // No active call → pop back
    if (call == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
      return const SizedBox.shrink();
    }

    final isVideo = call.isVideo;
    final isRinging = call.isRinging;
    final displayName = call.receiverName ?? 'Unknown';
    final avatarUrl = call.receiverAvatar;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: video feed or avatar ────────────────
          isVideo && !isRinging
              ? _VideoBackground(isLocalPreview: false)
              : _AvatarBackground(name: displayName, avatarUrl: avatarUrl),

          // ── Dark overlay ─────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xCC000000),
                  Colors.transparent,
                  Color(0xDD000000),
                ],
                stops: [0, 0.4, 1],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // ── Top: caller info ─────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 24,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  isRinging ? 'Calling…' : _formatDuration(state.callDuration),
                  style: AppTextStyles.captionText
                      .copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  style: AppTextStyles.headlineMedium.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  isRinging
                      ? (isVideo ? 'Video call' : 'Voice call')
                      : (isVideo ? '📹 Video' : '📞 Voice'),
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),

          // ── Ringing pulse animation ──────────────────────────
          if (isRinging)
            Center(
              child: _PulseRing(
                  controller: _pulseCtrl, avatarUrl: avatarUrl, name: displayName),
            ),

          // ── Local preview (video call) ───────────────────────
          if (isVideo && !isRinging && !state.isCameraOff)
            Positioned(
              top: MediaQuery.of(context).padding.top + 120,
              right: 16,
              child: _LocalVideoPreview(
                isFrontCamera: state.isFrontCamera,
                onFlip: ref.read(callProvider.notifier).flipCamera,
              ),
            ),

          // ── Camera off placeholder (video call) ──────────────
          if (isVideo && !isRinging && state.isCameraOff)
            Positioned(
              top: MediaQuery.of(context).padding.top + 120,
              right: 16,
              child: Container(
                width: 100,
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off,
                        color: Colors.white54, size: 28),
                    const SizedBox(height: 6),
                    Text('Camera off',
                        style: AppTextStyles.overline
                            .copyWith(color: Colors.white54)),
                  ],
                ),
              ),
            ),

          // ── Bottom controls ──────────────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 32,
            left: 0,
            right: 0,
            child: isRinging
                ? _RingingControls(
                    onCancel: () async {
                      await ref.read(callProvider.notifier).endCall();
                      if (context.mounted) context.pop();
                    },
                  )
                : _ActiveCallControls(
                    state: state,
                    notifier: ref.read(callProvider.notifier),
                    isVideo: isVideo,
                    onEnd: () async {
                      await ref.read(callProvider.notifier).endCall();
                      if (context.mounted) context.pop();
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ── Video background (Agora hook) ─────────────────────────────────

class _VideoBackground extends StatelessWidget {
  const _VideoBackground({required this.isLocalPreview});

  final bool isLocalPreview;

  @override
  Widget build(BuildContext context) {
    // TODO: Replace with AgoraVideoView when agora_rtc_engine is added:
    //   AgoraVideoView(controller: VideoViewController(
    //     rtcEngine: _engine,
    //     canvas: VideoCanvas(uid: isLocalPreview ? 0 : remoteUid),
    //   ))
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isLocalPreview ? Icons.personal_video : Icons.videocam,
              size: 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            Text(
              isLocalPreview
                  ? 'Local camera preview'
                  : 'Connecting video…',
              style: AppTextStyles.captionText
                  .copyWith(color: Colors.white38),
            ),
            Text(
              'Add agora_rtc_engine to pubspec for live video',
              style: AppTextStyles.overline
                  .copyWith(color: Colors.white24),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar background ──────────────────────────────────────────────

class _AvatarBackground extends StatelessWidget {
  const _AvatarBackground({required this.name, required this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D0D5C), Color(0xFF1A237E), Color(0xFF283593)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

// ── Pulse ring (ringing animation) ────────────────────────────────

class _PulseRing extends StatelessWidget {
  const _PulseRing({
    required this.controller,
    required this.name,
    required this.avatarUrl,
  });

  final AnimationController controller;
  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final scale = 1.0 + controller.value * 0.4;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse ring
            Transform.scale(
              scale: scale,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white
                        .withOpacity(0.2 * (1 - controller.value)),
                    width: 2,
                  ),
                ),
              ),
            ),
            // Middle ring
            Transform.scale(
              scale: 1.0 + controller.value * 0.2,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white
                      .withOpacity(0.05 * (1 - controller.value)),
                ),
              ),
            ),
            // Avatar
            ClipOval(
              child: avatarUrl != null
                  ? CachedNetworkImage(
                      imageUrl: avatarUrl!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover)
                  : Container(
                      width: 100,
                      height: 100,
                      color: AppColors.primaryLight,
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ── Local video preview (PIP) ─────────────────────────────────────

class _LocalVideoPreview extends StatelessWidget {
  const _LocalVideoPreview({
    required this.isFrontCamera,
    required this.onFlip,
  });

  final bool isFrontCamera;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onFlip,
      child: Container(
        width: 100,
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        clipBehavior: Clip.hardEdge,
        child: const _VideoBackground(isLocalPreview: true),
      ),
    );
  }
}

// ── Ringing controls ───────────────────────────────────────────────

class _RingingControls extends StatelessWidget {
  const _RingingControls({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Ringing…',
          style: AppTextStyles.captionText
              .copyWith(color: Colors.white60),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallButton(
              icon: Icons.call_end,
              color: AppColors.error,
              label: 'Cancel',
              size: 68,
              onTap: onCancel,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Active call controls ───────────────────────────────────────────

class _ActiveCallControls extends StatelessWidget {
  const _ActiveCallControls({
    required this.state,
    required this.notifier,
    required this.isVideo,
    required this.onEnd,
  });

  final CallState state;
  final CallNotifier notifier;
  final bool isVideo;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top row: secondary controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CallButton(
                icon: state.isMuted ? Icons.mic_off : Icons.mic,
                color: state.isMuted
                    ? Colors.white
                    : Colors.white.withOpacity(0.2),
                iconColor: state.isMuted ? Colors.black : Colors.white,
                label: state.isMuted ? 'Unmute' : 'Mute',
                onTap: notifier.toggleMute,
              ),
              _CallButton(
                icon: state.isSpeakerOn
                    ? Icons.volume_up
                    : Icons.volume_off,
                color: state.isSpeakerOn
                    ? Colors.white
                    : Colors.white.withOpacity(0.2),
                iconColor:
                    state.isSpeakerOn ? Colors.black : Colors.white,
                label: 'Speaker',
                onTap: notifier.toggleSpeaker,
              ),
              if (isVideo)
                _CallButton(
                  icon: state.isCameraOff
                      ? Icons.videocam_off
                      : Icons.videocam,
                  color: state.isCameraOff
                      ? Colors.white
                      : Colors.white.withOpacity(0.2),
                  iconColor:
                      state.isCameraOff ? Colors.black : Colors.white,
                  label: state.isCameraOff ? 'Camera' : 'Camera',
                  onTap: notifier.toggleCamera,
                ),
              if (isVideo)
                _CallButton(
                  icon: Icons.flip_camera_ios,
                  color: Colors.white.withOpacity(0.2),
                  iconColor: Colors.white,
                  label: 'Flip',
                  onTap: notifier.flipCamera,
                ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // End call button (center)
        _CallButton(
          icon: Icons.call_end,
          color: AppColors.error,
          label: 'End call',
          size: 72,
          onTap: onEnd,
        ),
      ],
    );
  }
}

// ── Call button ────────────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
    this.size = 56,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final String label;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: size * 0.42),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.overline
                .copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// ── Incoming Call Overlay ──────────────────────────────────────────

/// Displayed as a modal route over the current screen.
/// Triggered from the main app shell when [callProvider.incomingCall] is set.
class IncomingCallOverlay extends ConsumerStatefulWidget {
  const IncomingCallOverlay({super.key});

  @override
  ConsumerState<IncomingCallOverlay> createState() =>
      _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay>
    with TickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callProvider);
    final call = state.incomingCall;
    if (call == null) return const SizedBox.shrink();

    final notifier = ref.read(callProvider.notifier);
    final isVideo = call.isVideo;
    final callerName = call.callerName ?? 'Unknown';
    final callerAvatar = call.callerAvatar;

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
          parent: _slideCtrl, curve: Curves.easeOut)),
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Pulsing avatar
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, child) => Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: 1.0 + _pulseCtrl.value * 0.25,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.success.withOpacity(
                                  0.4 * (1 - _pulseCtrl.value)),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      child!,
                    ],
                  ),
                  child: ClipOval(
                    child: callerAvatar != null
                        ? CachedNetworkImage(
                            imageUrl: callerAvatar,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover)
                        : Container(
                            width: 52,
                            height: 52,
                            color: AppColors.primaryLight,
                            child: Center(
                              child: Text(
                                callerName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),

                const SizedBox(width: 14),

                // Caller info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        callerName,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.textDarkPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Incoming ${isVideo ? 'video' : 'voice'} call…',
                        style: AppTextStyles.captionText
                            .copyWith(color: AppColors.textDarkSecondary),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Decline
                GestureDetector(
                  onTap: () => notifier.declineCall(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_end,
                        color: Colors.white, size: 22),
                  ),
                ),

                const SizedBox(width: 10),

                // Accept
                GestureDetector(
                  onTap: () async {
                    await notifier.acceptCall();
                    final accepted = ref.read(callProvider).activeCall;
                    if (accepted != null && context.mounted) {
                      context.push('/call/${accepted.id}');
                    }
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo ? Icons.videocam : Icons.call,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
