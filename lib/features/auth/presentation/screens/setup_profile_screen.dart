import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/profile_setup_provider.dart';

class SetupProfileScreen extends ConsumerStatefulWidget {
  const SetupProfileScreen({super.key});

  @override
  ConsumerState<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends ConsumerState<SetupProfileScreen>
    with SingleTickerProviderStateMixin {
  // ── Controllers ───────────────────────────────────────────
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _churchCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();

  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();

  late final AnimationController _pageAnim;
  late final Animation<Offset> _slideIn;

  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _pageAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _slideIn = Tween<Offset>(
      begin: const Offset(0.06, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _pageAnim, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _churchCtrl.dispose();
    _websiteCtrl.dispose();
    _pageAnim.dispose();
    super.dispose();
  }

  // ── Avatar picker ─────────────────────────────────────────

  Future<void> _pickAvatar(ImageSource source) async {
    final notifier = ref.read(profileSetupProvider.notifier);
    try {
      final xFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      notifier.setAvatarBytes(bytes);
    } catch (_) {}
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.darkBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _BottomSheetOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take a photo',
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatar(ImageSource.camera);
                },
              ),
              _BottomSheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from gallery',
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatar(ImageSource.gallery);
                },
              ),
              if (ref.read(profileSetupProvider).avatarBytes != null)
                _BottomSheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove photo',
                  color: AppColors.error,
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(profileSetupProvider.notifier).clearAvatar();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step navigation ───────────────────────────────────────

  void _goNext() {
    if (!(_step1Key.currentState?.validate() ?? false)) return;
    final state = ref.read(profileSetupProvider);
    if (!state.isStep1Valid) return;
    _pageAnim.forward(from: 0);
    ref.read(profileSetupProvider.notifier).nextStep();
  }

  void _goBack() {
    _pageAnim.forward(from: 0);
    ref.read(profileSetupProvider.notifier).prevStep();
  }

  Future<void> _submit() async {
    final notifier = ref.read(profileSetupProvider.notifier);
    await notifier.submit();
    if (!mounted) return;
    final state = ref.read(profileSetupProvider);
    if (state.submitStatus == SetupSubmitStatus.success) {
      context.go(AppRoutes.home);
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileSetupProvider);

    // Listen for success / error toasts
    ref.listen<ProfileSetupState>(profileSetupProvider, (prev, next) {
      if (next.submitStatus == SetupSubmitStatus.error &&
          next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: SafeArea(
          child: Column(
            children: [
              // ── Header + step indicator ──────────────────
              _Header(currentStep: state.currentStep),

              // ── Page content ─────────────────────────────
              Expanded(
                child: SlideTransition(
                  position: _slideIn,
                  child: state.currentStep == 0
                      ? _Step1(
                          formKey: _step1Key,
                          fullNameCtrl: _fullNameCtrl,
                          usernameCtrl: _usernameCtrl,
                          onAvatarTap: _showAvatarOptions,
                        )
                      : _Step2(
                          formKey: _step2Key,
                          bioCtrl: _bioCtrl,
                          churchCtrl: _churchCtrl,
                          websiteCtrl: _websiteCtrl,
                        ),
                ),
              ),

              // ── Bottom actions ────────────────────────────
              _BottomActions(
                currentStep: state.currentStep,
                isStep1Valid: state.isStep1Valid,
                isStep2Valid: state.isStep2Valid,
                isLoading: state.isLoading,
                submitStatus: state.submitStatus,
                onNext: _goNext,
                onBack: _goBack,
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header with step indicator
// ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step pills
          Row(
            children: List.generate(2, (i) {
              final active = i == currentStep;
              final done = i < currentStep;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: EdgeInsets.only(right: i == 0 ? 6 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: done || active
                        ? AppColors.secondary
                        : AppColors.darkBorder,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 28),

          // Title
          Text(
            currentStep == 0
                ? 'Create your profile'
                : 'Choose your faith',
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textDarkPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            currentStep == 0
                ? 'Step 1 of 2 — Add a photo and choose your handle'
                : 'Step 2 of 2 — Select your faith to personalise your experience',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textDarkSecondary,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Step 1 — Avatar, Full Name, Username
// ─────────────────────────────────────────────────────────────

class _Step1 extends ConsumerWidget {
  const _Step1({
    required this.formKey,
    required this.fullNameCtrl,
    required this.usernameCtrl,
    required this.onAvatarTap,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController fullNameCtrl;
  final TextEditingController usernameCtrl;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileSetupProvider);
    final notifier = ref.read(profileSetupProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar picker ────────────────────────────
            Center(
              child: GestureDetector(
                onTap: onAvatarTap,
                child: Stack(
                  children: [
                    Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: state.avatarBytes == null
                            ? AppColors.brandGradient
                            : null,
                        border: Border.all(
                          color: AppColors.secondary,
                          width: 2.5,
                        ),
                      ),
                      child: ClipOval(
                        child: state.avatarBytes != null
                            ? Image.memory(
                                state.avatarBytes!,
                                fit: BoxFit.cover,
                                width: 108,
                                height: 108,
                              )
                            : const Icon(
                                Icons.person_rounded,
                                size: 52,
                                color: Colors.white54,
                              ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.darkBackground,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Full name ────────────────────────────────
            _FieldLabel('Full Name'),
            const SizedBox(height: 8),
            TextFormField(
              controller: fullNameCtrl,
              onChanged: notifier.setFullName,
              style: AppTextStyles.bodyLarge
                  .copyWith(color: AppColors.textDarkPrimary),
              textCapitalization: TextCapitalization.words,
              decoration: _inputDecoration(
                hint: 'Your real name',
                prefixIcon: Icons.badge_outlined,
              ),
              validator: (v) {
                if (v == null || v.trim().length < 2) {
                  return 'Please enter at least 2 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // ── Username ─────────────────────────────────
            _FieldLabel('Username'),
            const SizedBox(height: 8),
            TextFormField(
              controller: usernameCtrl,
              onChanged: notifier.setUsername,
              style: AppTextStyles.bodyLarge
                  .copyWith(color: AppColors.textDarkPrimary),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_.]')),
                LengthLimitingTextInputFormatter(30),
              ],
              decoration: _inputDecoration(
                hint: 'e.g. john_doe',
                prefixIcon: Icons.alternate_email_rounded,
                suffix: _UsernameStatusWidget(status: state.usernameStatus),
              ),
              validator: (v) {
                if (v == null || v.trim().length < 3) {
                  return 'Username must be at least 3 characters';
                }
                if (state.usernameStatus == UsernameStatus.taken) {
                  return 'That username is already taken';
                }
                if (state.usernameStatus == UsernameStatus.invalid) {
                  return 'Only letters, numbers, _ and . are allowed';
                }
                return null;
              },
            ),
            const SizedBox(height: 6),
            _UsernameHintRow(status: state.usernameStatus),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Step 2 — Bio, Hub, Church, Website
// ─────────────────────────────────────────────────────────────

class _Step2 extends ConsumerWidget {
  const _Step2({
    required this.formKey,
    required this.bioCtrl,
    required this.churchCtrl,
    required this.websiteCtrl,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController bioCtrl;
  final TextEditingController churchCtrl;
  final TextEditingController websiteCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileSetupProvider);
    final notifier = ref.read(profileSetupProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Bio ──────────────────────────────────────
            _FieldLabel('Bio'),
            const SizedBox(height: 8),
            TextFormField(
              controller: bioCtrl,
              onChanged: notifier.setBio,
              maxLines: 3,
              maxLength: 150,
              style: AppTextStyles.bodyLarge
                  .copyWith(color: AppColors.textDarkPrimary),
              textCapitalization: TextCapitalization.sentences,
              decoration: _inputDecoration(
                hint: 'A short intro about yourself…',
                prefixIcon: Icons.edit_note_rounded,
              ).copyWith(
                counterStyle: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textDarkSecondary),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),

            // ── Religion (required) ──────────────────────
            _FieldLabel('Your Faith *'),
            const SizedBox(height: 4),
            Text(
              'This personalises your feed and default scripture community',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textDarkSecondary),
            ),
            const SizedBox(height: 14),
            _ReligionPicker(
              selected: state.religion,
              onSelect: notifier.setReligion,
            ),
            if (state.religion.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Please select your faith to continue',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 24),

            // ── Church / Mosque (adaptive) ───────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: state.religion.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel(state.religion == 'muslim'
                            ? 'Masjid / Islamic Centre'
                            : 'Church / Ministry'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: churchCtrl,
                          onChanged: notifier.setChurchName,
                          style: AppTextStyles.bodyLarge
                              .copyWith(color: AppColors.textDarkPrimary),
                          textCapitalization: TextCapitalization.words,
                          decoration: _inputDecoration(
                            hint: state.religion == 'muslim'
                                ? 'Optional — e.g. Masjid Al-Noor'
                                : 'Optional — e.g. Grace Chapel',
                            prefixIcon: state.religion == 'muslim'
                                ? Icons.mosque_outlined
                                : Icons.church_outlined,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Website ──────────────────────────────────
            _FieldLabel('Website'),
            const SizedBox(height: 8),
            TextFormField(
              controller: websiteCtrl,
              onChanged: notifier.setWebsite,
              style: AppTextStyles.bodyLarge
                  .copyWith(color: AppColors.textDarkPrimary),
              keyboardType: TextInputType.url,
              decoration: _inputDecoration(
                hint: 'Optional — https://yoursite.com',
                prefixIcon: Icons.link_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom action buttons
// ─────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.currentStep,
    required this.isStep1Valid,
    required this.isStep2Valid,
    required this.isLoading,
    required this.submitStatus,
    required this.onNext,
    required this.onBack,
    required this.onSubmit,
  });

  final int currentStep;
  final bool isStep1Valid;
  final bool isStep2Valid;
  final bool isLoading;
  final SetupSubmitStatus submitStatus;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.darkBackground,
        border: Border(
          top: BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button (only on step 2)
          if (currentStep == 1) ...[
            _OutlineButton(
              label: 'Back',
              onTap: onBack,
              icon: Icons.arrow_back_rounded,
            ),
            const SizedBox(width: 12),
          ],

          // Next / Finish button
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: currentStep == 0
                  ? _PrimaryButton(
                      key: const ValueKey('next'),
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      enabled: isStep1Valid,
                      onTap: onNext,
                    )
                  : _PrimaryButton(
                      key: const ValueKey('finish'),
                      label: isLoading ? _loadingLabel(submitStatus) : 'Finish',
                      icon: isLoading ? null : Icons.check_rounded,
                      enabled: !isLoading && isStep2Valid,
                      isLoading: isLoading,
                      onTap: onSubmit,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _loadingLabel(SetupSubmitStatus status) {
    return switch (status) {
      SetupSubmitStatus.uploading => 'Uploading photo…',
      SetupSubmitStatus.saving => 'Saving…',
      _ => 'Please wait…',
    };
  }
}

// ─────────────────────────────────────────────────────────────
// Small re-usable widgets
// ─────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: AppTextStyles.labelLarge.copyWith(
          color: AppColors.textDarkSecondary,
          letterSpacing: 0.4,
        ),
      );
}

class _UsernameStatusWidget extends StatelessWidget {
  const _UsernameStatusWidget({required this.status});
  final UsernameStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      UsernameStatus.checking => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
        ),
      UsernameStatus.available => const Icon(
          Icons.check_circle_rounded,
          color: AppColors.success,
          size: 20,
        ),
      UsernameStatus.taken => const Icon(
          Icons.cancel_rounded,
          color: AppColors.error,
          size: 20,
        ),
      UsernameStatus.invalid => const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.warning,
          size: 20,
        ),
      UsernameStatus.idle => const SizedBox.shrink(),
    };
  }
}

class _UsernameHintRow extends StatelessWidget {
  const _UsernameHintRow({required this.status});
  final UsernameStatus status;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      UsernameStatus.available => ('Username is available!', AppColors.success),
      UsernameStatus.taken => ('Username is already taken', AppColors.error),
      UsernameStatus.invalid =>
        ('Only letters, numbers, _ and . allowed', AppColors.warning),
      UsernameStatus.checking => ('Checking availability…', AppColors.accent),
      UsernameStatus.idle => ('Letters, numbers, _ and . only', AppColors.textDarkTertiary),
    };

    return Text(
      text,
      style:
          AppTextStyles.bodySmall.copyWith(color: color),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Religion Picker — two large cards: Christianity / Islam
// ─────────────────────────────────────────────────────────────

class _ReligionPicker extends StatelessWidget {
  const _ReligionPicker({
    required this.selected,
    required this.onSelect,
  });
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ReligionCard(
          value: 'christian',
          label: 'Christianity',
          emoji: '✝️',
          subtitle: 'Bible · Gospel · Church',
          color: const Color(0xFF1A7A6B),
          selected: selected == 'christian',
          onTap: () => onSelect('christian'),
        ),
        const SizedBox(width: 12),
        _ReligionCard(
          value: 'muslim',
          label: 'Islam',
          emoji: '☪️',
          subtitle: 'Quran · Hadith · Masjid',
          color: const Color(0xFF1A6B4A),
          selected: selected == 'muslim',
          onTap: () => onSelect('muslim'),
        ),
      ],
    );
  }
}

class _ReligionCard extends StatelessWidget {
  const _ReligionCard({
    required this.value,
    required this.label,
    required this.emoji,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String value, label, emoji, subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : AppColors.darkBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : AppColors.textDarkPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                    color: AppColors.textDarkSecondary, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              if (selected) ...[
                const SizedBox(height: 8),
                Icon(Icons.check_circle, color: color, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HubChip extends StatelessWidget {
  const _HubChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.secondary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withOpacity(0.15)
                : AppColors.darkSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? activeColor : AppColors.darkBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? activeColor : AppColors.textDarkSecondary,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? activeColor : AppColors.textDarkSecondary,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool enabled;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          gradient: enabled
              ? AppColors.goldGradient
              : null,
          color: enabled ? null : AppColors.darkSurface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: AppTextStyles.labelLarge.copyWith(
                color: enabled ? Colors.black : AppColors.textDarkTertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            if (icon != null && !isLoading) ...[
              const SizedBox(width: 6),
              Icon(
                icon,
                size: 18,
                color: enabled ? Colors.black : AppColors.textDarkTertiary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.darkBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.textDarkSecondary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.textDarkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomSheetOption extends StatelessWidget {
  const _BottomSheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textDarkPrimary;
    return ListTile(
      leading: Icon(icon, color: c),
      title: Text(label, style: AppTextStyles.bodyLarge.copyWith(color: c)),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Input decoration helper
// ─────────────────────────────────────────────────────────────

InputDecoration _inputDecoration({
  required String hint,
  required IconData prefixIcon,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle:
        AppTextStyles.bodyLarge.copyWith(color: AppColors.textDarkTertiary),
    filled: true,
    fillColor: AppColors.darkSurface,
    prefixIcon: Icon(prefixIcon, color: AppColors.textDarkSecondary, size: 20),
    suffixIcon: suffix != null
        ? Padding(
            padding: const EdgeInsets.only(right: 14),
            child: suffix,
          )
        : null,
    suffixIconConstraints: const BoxConstraints(maxWidth: 44, maxHeight: 44),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.darkBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.darkBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.secondary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.error, width: 1.5),
    ),
    errorStyle:
        AppTextStyles.bodySmall.copyWith(color: AppColors.error),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
