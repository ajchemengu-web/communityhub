import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../auth/data/profile_repository.dart';
import '../../data/profile_detail_repository.dart';
import '../providers/profile_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _churchCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();

  bool _loaded = false;
  bool _saving = false;
  late final String _uid;

  String? _existingAvatarUrl;
  Uint8List? _newAvatarBytes;

  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _uid = SupabaseService.currentUserId ?? '';
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (_uid.isEmpty) return;
    try {
      final data = await ProfileDetailRepository.instance.fetchProfile(_uid);
      if (!mounted) return;
      _fullNameCtrl.text = (data['full_name'] as String?) ?? '';
      _usernameCtrl.text = (data['username'] as String?) ?? '';
      _bioCtrl.text = (data['bio'] as String?) ?? '';
      _churchCtrl.text = (data['church_name'] as String?) ?? '';
      _websiteCtrl.text = (data['website'] as String?) ?? '';
      _existingAvatarUrl = data['avatar_url'] as String?;
      setState(() => _loaded = true);
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _churchCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final xFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      setState(() => _newAvatarBytes = bytes);
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
              _SheetOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take a photo',
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatar(ImageSource.camera);
                },
              ),
              _SheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from gallery',
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatar(ImageSource.gallery);
                },
              ),
              if (_newAvatarBytes != null || _existingAvatarUrl != null)
                _SheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove photo',
                  color: AppColors.error,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _newAvatarBytes = null;
                      _existingAvatarUrl = null;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      // Upload new avatar if selected
      String? avatarUrl = _existingAvatarUrl;
      if (_newAvatarBytes != null) {
        avatarUrl = await ProfileRepository.instance.uploadAvatar(_newAvatarBytes!);
      } else if (_existingAvatarUrl == null) {
        avatarUrl = '';
      }

      await ProfileDetailRepository.instance.updateProfile(
        userId: _uid,
        fullName: _fullNameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        churchName: _churchCtrl.text.trim().isEmpty ? null : _churchCtrl.text.trim(),
        website: _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
        avatarUrl: avatarUrl,
      );

      if (mounted) {
        ref.invalidate(profileProvider(_uid));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Edit Profile'),
        centerTitle: true,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(
                'Save',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Avatar picker ──────────────────────────
                    Center(
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: _showAvatarOptions,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: _newAvatarBytes != null
                                    ? Image.memory(_newAvatarBytes!,
                                        fit: BoxFit.cover)
                                    : (_existingAvatarUrl != null &&
                                            _existingAvatarUrl!.isNotEmpty)
                                        ? CachedNetworkImage(
                                            imageUrl: _existingAvatarUrl!,
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) => Container(
                                                color: AppColors.darkSurface),
                                            errorWidget: (_, __, ___) =>
                                                _AvatarPlaceholder(
                                                    name: _fullNameCtrl.text),
                                          )
                                        : _AvatarPlaceholder(
                                            name: _fullNameCtrl.text),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _showAvatarOptions,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.darkBackground,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(Icons.camera_alt_rounded,
                                    size: 15, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: _showAvatarOptions,
                        child: Text(
                          'Change photo',
                          style: AppTextStyles.labelMedium
                              .copyWith(color: AppColors.primary),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    _SectionLabel('Basic Info'),
                    const SizedBox(height: 12),

                    _Field(
                      controller: _fullNameCtrl,
                      label: 'Full name',
                      icon: Icons.person_outline,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Full name is required';
                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    _Field(
                      controller: _usernameCtrl,
                      label: 'Username',
                      icon: Icons.alternate_email_rounded,
                      prefix: '@',
                      autocorrect: false,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Username is required';
                        if (v.trim().length < 3) return 'At least 3 characters';
                        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v.trim())) {
                          return 'Letters, numbers and underscores only';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),
                    _SectionLabel('About You'),
                    const SizedBox(height: 12),

                    _Field(
                      controller: _bioCtrl,
                      label: 'Bio',
                      icon: Icons.notes_rounded,
                      maxLines: 4,
                      maxLength: 160,
                    ),

                    const SizedBox(height: 24),
                    _SectionLabel('Community'),
                    const SizedBox(height: 12),

                    _Field(
                      controller: _churchCtrl,
                      label: 'Church / congregation',
                      icon: Icons.church_rounded,
                    ),

                    const SizedBox(height: 14),

                    _Field(
                      controller: _websiteCtrl,
                      label: 'Website',
                      icon: Icons.link_rounded,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        if (!v.trim().startsWith('http')) {
                          return 'Start with http:// or https://';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save Changes'),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.3),
      child: Center(
        child: name.isNotEmpty
            ? Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w700),
              )
            : const Icon(Icons.person, color: Colors.white70, size: 40),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
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
    final c = color ?? Colors.white;
    return ListTile(
      leading: Icon(icon, color: c),
      title: Text(label, style: TextStyle(color: c)),
      onTap: onTap,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.textMuted,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.prefix,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.autocorrect = true,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? prefix;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      autocorrect: autocorrect,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        prefixText: prefix,
        prefixStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: AppColors.darkSurface,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        errorStyle: const TextStyle(color: AppColors.error),
        counterStyle: const TextStyle(color: Colors.white38),
      ),
    );
  }
}
