import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});
  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _ctrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  int _resendSeconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds == 0) {
        t.cancel();
      } else {
        if (mounted) setState(() => _resendSeconds--);
      }
    });
  }

  String get _otp => _ctrls.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _nodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _nodes[index - 1].requestFocus();
    }
    // Auto-verify when all 6 digits entered
    if (_otp.length == 6) _verify();
  }

  Future<void> _verify() async {
    if (_otp.length < 6 || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .verifyPhoneOtp(widget.phone, _otp);
      // Auth state change listener will navigate automatically
    } catch (e) {
      _showError('Invalid code. Please try again.');
      for (final c in _ctrls) {
        c.clear();
      }
      if (mounted) _nodes[0].requestFocus();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    if (_resendSeconds > 0) return;
    setState(() => _isLoading = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signInWithPhone(widget.phone);
      _startTimer();
      _showSuccess('New code sent!');
    } catch (e) {
      _showError('Could not resend code. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(height: 32),

                // Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.sms_outlined,
                      color: AppColors.secondary, size: 32),
                ).animate().fadeIn(duration: 400.ms),

                const SizedBox(height: 24),

                Text(
                  'Enter verification\ncode',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.3, end: 0),

                const SizedBox(height: 10),

                Text(
                  'We sent a 6-digit code to\n${widget.phone}',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: Colors.white60, height: 1.5),
                ).animate(delay: 150.ms).fadeIn(),

                const SizedBox(height: 40),

                // OTP boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (i) => _OtpBox(
                    controller: _ctrls[i],
                    focusNode: _nodes[i],
                    onChanged: (v) => _onDigitChanged(i, v),
                  )),
                ).animate(delay: 200.ms).fadeIn(),

                const SizedBox(height: 40),

                // Verify button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.secondary.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text('Verify',
                            style: AppTextStyles.buttonText
                                .copyWith(color: Colors.white)),
                  ),
                ).animate(delay: 250.ms).fadeIn(),

                const SizedBox(height: 24),

                // Resend
                Center(
                  child: GestureDetector(
                    onTap: _resendSeconds == 0 ? _resend : null,
                    child: RichText(
                      text: TextSpan(
                        text: "Didn't receive a code? ",
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.white54),
                        children: [
                          TextSpan(
                            text: _resendSeconds > 0
                                ? 'Resend in ${_resendSeconds}s'
                                : 'Resend',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: _resendSeconds > 0
                                  ? Colors.white30
                                  : AppColors.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ).animate(delay: 300.ms).fadeIn(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 56,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.secondary, width: 2),
          ),
        ),
      ),
    );
  }
}
