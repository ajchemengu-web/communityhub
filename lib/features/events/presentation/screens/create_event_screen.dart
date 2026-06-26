import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/events_repository.dart';
import '../../domain/models/event_model.dart';
import '../providers/events_provider.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() =>
      _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _meetingUrlCtrl = TextEditingController();

  File? _coverFile;
  EventType _type = EventType.service;
  bool _isOnline = false;
  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  DateTime _endTime = DateTime.now().add(const Duration(hours: 3));
  bool _isSubmitting = false;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _meetingUrlCtrl.dispose();
    super.dispose();
  }

  // ── Cover picker ───────────────────────────────────────────────

  Future<void> _pickCover() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (xfile != null) {
      setState(() => _coverFile = File(xfile.path));
    }
  }

  // ── Date/time pickers ──────────────────────────────────────────

  Future<void> _pickStartTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: _darkPickerTheme,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
      builder: _darkPickerTheme,
    );
    if (time == null) return;

    setState(() {
      _startTime = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
      if (_endTime.isBefore(_startTime)) {
        _endTime = _startTime.add(const Duration(hours: 2));
      }
    });
  }

  Future<void> _pickEndTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endTime,
      firstDate: _startTime,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: _darkPickerTheme,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime),
      builder: _darkPickerTheme,
    );
    if (time == null) return;

    setState(() {
      _endTime = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Widget _darkPickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          surface: AppColors.darkSurface,
          onSurface: AppColors.textPrimary,
        ),
      ),
      child: child!,
    );
  }

  // ── Submit ─────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endTime.isBefore(_startTime)) {
      _showError('End time must be after start time');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Create event first
      final event = await EventsRepository.instance.createEvent(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        communityId: null, // TODO: community selector
        type: _type,
        isOnline: _isOnline,
        location: _isOnline ? null : _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        meetingUrl: _isOnline ? _meetingUrlCtrl.text.trim().isEmpty
            ? null
            : _meetingUrlCtrl.text.trim()
            : null,
        startTime: _startTime,
        endTime: _endTime,
      );

      // Upload cover if selected
      if (_coverFile != null) {
        try {
          final url = await EventsRepository.instance
              .uploadEventCover(_coverFile!, event.id);
          await SupabaseService.client
              .from('events')
              .update({'cover_url': url}).eq('id', event.id);
        } catch (_) {
          // Non-fatal; event created without cover
        }
      }

      ref.read(eventsProvider.notifier).onEventCreated(event);

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        title: Text('Create Event', style: AppTextStyles.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  )
                : Text('Create',
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.primary)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Cover picker
            _CoverPicker(file: _coverFile, onTap: _pickCover),
            const SizedBox(height: 24),

            // Title
            _StyledField(
              controller: _titleCtrl,
              label: 'Event Title',
              hint: 'e.g. Sunday Service, Youth Bible Study',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),

            // Description
            _StyledField(
              controller: _descCtrl,
              label: 'Description (optional)',
              hint: 'Tell people what to expect…',
              maxLines: 4,
            ),
            const SizedBox(height: 24),

            // Event type
            _SectionLabel('Event Type'),
            const SizedBox(height: 12),
            _TypeSelector(
              selected: _type,
              onChanged: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: 24),

            // Date & time
            _SectionLabel('Date & Time'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateTimeTile(
                    label: 'Starts',
                    dateTime: _startTime,
                    onTap: _pickStartTime,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateTimeTile(
                    label: 'Ends',
                    dateTime: _endTime,
                    onTap: _pickEndTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Online toggle
            _SectionLabel('Location'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    _isOnline
                        ? Icons.videocam_outlined
                        : Icons.location_on_outlined,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Online Event',
                            style: AppTextStyles.bodyMedium
                                .copyWith(fontWeight: FontWeight.w600)),
                        Text(
                            _isOnline
                                ? 'Share a meeting link'
                                : 'Specify a physical location',
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isOnline,
                    onChanged: (v) => setState(() => _isOnline = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _isOnline
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: _StyledField(
                controller: _locationCtrl,
                label: 'Location',
                hint: 'e.g. 123 Main St, City Hall, etc.',
                prefixIcon: Icons.location_on_outlined,
              ),
              secondChild: _StyledField(
                controller: _meetingUrlCtrl,
                label: 'Meeting Link',
                hint: 'https://zoom.us/j/...',
                prefixIcon: Icons.link_outlined,
                keyboardType: TextInputType.url,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Cover picker ───────────────────────────────────────────────────

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({required this.file, required this.onTap});
  final File? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.darkBorder, style: BorderStyle.solid),
          image: file != null
              ? DecorationImage(
                  image: FileImage(file!), fit: BoxFit.cover)
              : null,
        ),
        child: file == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined,
                      size: 36, color: AppColors.textSecondary),
                  const SizedBox(height: 8),
                  Text('Add Cover Photo',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                  Text('Recommended: 1280×720',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary)),
                ],
              )
            : Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.darkBackground.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit_outlined,
                        size: 18, color: Colors.white),
                  ),
                ),
              ),
      ),
    );
  }
}

// ── Event type selector ────────────────────────────────────────────

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selected, required this.onChanged});
  final EventType selected;
  final ValueChanged<EventType> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      (EventType.service, Icons.church_outlined, 'Service'),
      (EventType.study, Icons.menu_book_outlined, 'Study'),
      (EventType.outreach, Icons.volunteer_activism_outlined, 'Outreach'),
      (EventType.social, Icons.celebration_outlined, 'Social'),
      (EventType.other, Icons.event_outlined, 'Other'),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((opt) {
        final (type, icon, label) = opt;
        final isSelected = selected == type;
        return GestureDetector(
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.2)
                  : AppColors.darkSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    isSelected ? AppColors.primary : AppColors.darkBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 18,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Date-time tile ─────────────────────────────────────────────────

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    required this.label,
    required this.dateTime,
    required this.onTap,
  });

  final String label;
  final DateTime dateTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM d, yyyy').format(dateTime),
              style: AppTextStyles.bodyMedium
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              DateFormat('h:mm a').format(dateTime),
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Styled field ───────────────────────────────────────────────────

class _StyledField extends StatelessWidget {
  const _StyledField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.validator,
    this.prefixIcon,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final FormFieldValidator<String>? validator;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          keyboardType: keyboardType,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: AppColors.textSecondary, size: 20)
                : null,
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
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: AppTextStyles.labelMedium
            .copyWith(color: AppColors.textSecondary));
  }
}
