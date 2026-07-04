import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/create_community_provider.dart';

class CreateCommunityScreen extends ConsumerStatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  ConsumerState<CreateCommunityScreen> createState() =>
      _CreateCommunityScreenState();
}

class _CreateCommunityScreenState
    extends ConsumerState<CreateCommunityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  final _descFocus = FocusNode();
  final _denomFocus = FocusNode();
  final _locationFocus = FocusNode();
  final _websiteFocus = FocusNode();

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _denomCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();

  @override
  void dispose() {
    _nameFocus.dispose();
    _descFocus.dispose();
    _denomFocus.dispose();
    _locationFocus.dispose();
    _websiteFocus.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _denomCtrl.dispose();
    _locationCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 640,
      imageQuality: 85,
    );
    if (picked != null) {
      ref
          .read(createCommunityProvider.notifier)
          .setCoverFile(File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState!.save();

    await ref.read(createCommunityProvider.notifier).submit();

    final state = ref.read(createCommunityProvider);
    if (!mounted) return;

    if (state.status == CreateCommunityStatus.success &&
        state.created != null) {
      final community = state.created!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${community.name} created!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop(community);
    } else if (state.status == CreateCommunityStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.errorMessage ?? 'Something went wrong'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createCommunityProvider);
    final notifier = ref.read(createCommunityProvider.notifier);
    final isFaith = state.hubType == 'faith' ||
        state.hubType == 'christianity' ||
        state.hubType == 'islam';
    final isIslam = state.hubType == 'islam';
    final isUploading = state.status == CreateCommunityStatus.uploading;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: Text(
          'Create Hub',
          style: AppTextStyles.heading3
              .copyWith(color: AppColors.textDarkPrimary),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textDarkPrimary),
          onPressed: isUploading ? null : () => context.pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _SubmitButton(
              canSubmit: state.canSubmit,
              isUploading: isUploading,
              onTap: _submit,
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Cover image picker ─────────────────────────────
            _CoverPicker(
              file: state.coverFile,
              onTap: isUploading ? null : _pickCover,
              onRemove: isUploading
                  ? null
                  : () => notifier.setCoverFile(null),
            ),

            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hub type ───────────────────────────────────
                  _SectionLabel('Hub Type'),
                  const SizedBox(height: 8),
                  _HubTypeSelector(
                    value: state.hubType,
                    onChange: isUploading ? null : notifier.setHubType,
                  ),

                  const SizedBox(height: 24),

                  // ── Name ───────────────────────────────────────
                  _SectionLabel('Community Name *'),
                  const SizedBox(height: 8),
                  _StyledField(
                    controller: _nameCtrl,
                    focusNode: _nameFocus,
                    hint: isIslam
                        ? 'e.g. Masjid Al-Noor, Quran Circle…'
                        : isFaith
                            ? 'e.g. Grace Community Church'
                            : 'e.g. Flutter Developers Africa',
                    maxLength: 60,
                    enabled: !isUploading,
                    validator: (v) {
                      if (v == null || v.trim().length < 3) {
                        return 'Name must be at least 3 characters';
                      }
                      return null;
                    },
                    onChanged: notifier.setName,
                    onSaved: (v) => notifier.setName(v ?? ''),
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_descFocus),
                  ),

                  const SizedBox(height: 20),

                  // ── Description ────────────────────────────────
                  _SectionLabel('Description'),
                  const SizedBox(height: 8),
                  _StyledField(
                    controller: _descCtrl,
                    focusNode: _descFocus,
                    hint: isIslam
                        ? 'Share your masjid\'s mission and what members can expect…'
                        : isFaith
                            ? 'Share your church\'s mission and what members can expect…'
                            : 'Tell people what this community is about…',
                    maxLines: 4,
                    maxLength: 300,
                    enabled: !isUploading,
                    onChanged: notifier.setDescription,
                    onSaved: (v) => notifier.setDescription(v ?? ''),
                    textInputAction: TextInputAction.newline,
                  ),

                  const SizedBox(height: 20),

                  // ── Privacy ────────────────────────────────────
                  _PrivacyToggle(
                    isPrivate: state.isPrivate,
                    onChange: isUploading ? null : notifier.setPrivate,
                  ),

                  const SizedBox(height: 24),

                  // ── Faith-only fields ──────────────────────────
                  if (isFaith) ...[
                    _SectionLabel(isIslam ? 'School / Madhab' : 'Denomination'),
                    const SizedBox(height: 8),
                    _StyledField(
                      controller: _denomCtrl,
                      focusNode: _denomFocus,
                      hint: isIslam
                          ? 'e.g. Sunni, Shia, Sufi, Salafi…'
                          : 'e.g. Baptist, Catholic, Pentecostal…',
                      enabled: !isUploading,
                      onChanged: notifier.setDenomination,
                      onSaved: (v) => notifier.setDenomination(v ?? ''),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(_locationFocus),
                    ),

                    const SizedBox(height: 20),

                    _SectionLabel('Location'),
                    const SizedBox(height: 8),
                    _StyledField(
                      controller: _locationCtrl,
                      focusNode: _locationFocus,
                      hint: 'City, Country',
                      prefixIcon: Icons.location_on_outlined,
                      enabled: !isUploading,
                      onChanged: notifier.setLocation,
                      onSaved: (v) => notifier.setLocation(v ?? ''),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(_websiteFocus),
                    ),

                    const SizedBox(height: 20),
                  ],

                  // ── Website ────────────────────────────────────
                  _SectionLabel('Website'),
                  const SizedBox(height: 8),
                  _StyledField(
                    controller: _websiteCtrl,
                    focusNode: _websiteFocus,
                    hint: 'https://',
                    prefixIcon: Icons.link_outlined,
                    enabled: !isUploading,
                    keyboardType: TextInputType.url,
                    onChanged: notifier.setWebsite,
                    onSaved: (v) => notifier.setWebsite(v ?? ''),
                    textInputAction: TextInputAction.done,
                  ),

                  const SizedBox(height: 32),

                  // ── Submit button (bottom) ─────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: state.canSubmit ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor:
                            AppColors.primary.withOpacity(0.4),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isUploading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Create Community',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cover picker ───────────────────────────────────────────────────

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.file,
    required this.onTap,
    required this.onRemove,
  });

  final File? file;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180,
        color: AppColors.surfaceDark,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (file != null)
              Image.file(file!, fit: BoxFit.cover)
            else
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Add Cover Image',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textDarkSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recommended: 1920 × 640',
                    style: AppTextStyles.captionText
                        .copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),

            // Dark gradient at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.5),
                    ],
                  ),
                ),
              ),
            ),

            // Remove button
            if (file != null)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),

            // Edit overlay when image exists
            if (file != null)
              Positioned(
                bottom: 8,
                right: 12,
                child: Row(
                  children: [
                    const Icon(Icons.edit, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Change cover',
                      style: AppTextStyles.captionText
                          .copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Hub type selector ──────────────────────────────────────────────

class _HubTypeSelector extends StatelessWidget {
  const _HubTypeSelector({required this.value, required this.onChange});

  final String value;
  final void Function(String)? onChange;

  static const _hubs = [
    (
      id: 'christianity',
      label: 'Christianity',
      icon: Icons.church_outlined,
      description: 'Church, ministry or Christian fellowship'
    ),
    (
      id: 'islam',
      label: 'Islam',
      icon: Icons.mosque_outlined,
      description: 'Masjid, Quran circle or Islamic community'
    ),
    (
      id: 'faith',
      label: 'Faith (General)',
      icon: Icons.auto_awesome_outlined,
      description: 'Interfaith or multi-religion spiritual group'
    ),
    (
      id: 'career',
      label: 'Career',
      icon: Icons.work_outline,
      description: 'Tech, business or professional community'
    ),
    (
      id: 'general',
      label: 'General',
      icon: Icons.people_outline,
      description: 'Any other interest or topic'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _hubs
          .map(
            (h) => GestureDetector(
              onTap: onChange == null ? null : () => onChange!(h.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: value == h.id
                      ? AppColors.primary.withOpacity(0.12)
                      : AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: value == h.id
                        ? AppColors.primary
                        : AppColors.divider,
                    width: value == h.id ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: value == h.id
                            ? AppColors.primary.withOpacity(0.2)
                            : AppColors.backgroundDark,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        h.icon,
                        color: value == h.id
                            ? AppColors.primary
                            : AppColors.textDarkSecondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h.label,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: value == h.id
                                  ? AppColors.primary
                                  : AppColors.textDarkPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            h.description,
                            style: AppTextStyles.captionText.copyWith(
                                color: AppColors.textDarkSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (value == h.id)
                      const Icon(Icons.check_circle,
                          color: AppColors.primary, size: 20)
                    else
                      const Icon(Icons.radio_button_unchecked,
                          color: AppColors.divider, size: 20),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── Privacy toggle ─────────────────────────────────────────────────

class _PrivacyToggle extends StatelessWidget {
  const _PrivacyToggle({required this.isPrivate, required this.onChange});

  final bool isPrivate;
  final void Function(bool)? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _PrivacyOption(
            icon: Icons.lock_outline,
            label: 'Private',
            description:
                'Members must be approved before joining. Posts are hidden from non-members.',
            selected: isPrivate,
            onTap: onChange == null ? null : () => onChange!(true),
          ),
          const Divider(color: AppColors.divider, height: 20),
          _PrivacyOption(
            icon: Icons.public,
            label: 'Public',
            description:
                'Anyone can join and see the community posts.',
            selected: !isPrivate,
            onTap: onChange == null ? null : () => onChange!(false),
          ),
        ],
      ),
    );
  }
}

class _PrivacyOption extends StatelessWidget {
  const _PrivacyOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: selected
                ? AppColors.primary
                : AppColors.textDarkSecondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textDarkPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: AppTextStyles.captionText
                      .copyWith(color: AppColors.textDarkSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color:
                selected ? AppColors.primary : AppColors.divider,
            size: 20,
          ),
        ],
      ),
    );
  }
}

// ── Submit button (AppBar action) ──────────────────────────────────

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.canSubmit,
    required this.isUploading,
    required this.onTap,
  });

  final bool canSubmit;
  final bool isUploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (isUploading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor:
              AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      );
    }

    return GestureDetector(
      onTap: canSubmit ? onTap : null,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: canSubmit
              ? AppColors.primary
              : AppColors.primary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Create',
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Styled text field ──────────────────────────────────────────────

class _StyledField extends StatelessWidget {
  const _StyledField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.prefixIcon,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSaved,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final bool enabled;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String?)? onSaved;
  final void Function(String)? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      maxLength: maxLength,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: AppTextStyles.bodyMedium
          .copyWith(color: AppColors.textDarkPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.bodyMedium
            .copyWith(color: AppColors.textMuted),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppColors.textDarkSecondary, size: 20)
            : null,
        filled: true,
        fillColor: AppColors.surfaceDark,
        counterStyle:
            AppTextStyles.captionText.copyWith(color: AppColors.textMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AppColors.divider.withOpacity(0.5)),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: maxLines > 1 ? 14 : 0,
        ),
      ),
      validator: validator,
      onChanged: onChanged,
      onSaved: onSaved,
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}

// ── Section label ──────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textDarkSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}
