import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/marketplace_repository.dart';
import '../../domain/models/shop_model.dart';
import '../providers/marketplace_provider.dart';

/// Create-or-edit screen for the caller's own shop. Reached from the
/// profile page's shop tile and from ShopScreen's edit button (owner
/// only — RLS on `shops` also enforces `id = auth.uid()` on both
/// INSERT/UPDATE, so this screen can never be used to edit someone
/// else's shop even if it were somehow reached with a different id).
class ManageShopScreen extends ConsumerStatefulWidget {
  const ManageShopScreen({super.key});

  @override
  ConsumerState<ManageShopScreen> createState() => _ManageShopScreenState();
}

class _ManageShopScreenState extends ConsumerState<ManageShopScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _picker = ImagePicker();

  File? _bannerFile;
  File? _logoFile;
  String? _existingBannerUrl;
  String? _existingLogoUrl;
  bool _isPublished = false;
  bool _loaded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _prefill(ShopModel? shop) {
    if (_loaded || shop == null) return;
    _loaded = true;
    _nameCtrl.text = shop.name;
    _bioCtrl.text = shop.bio ?? '';
    _categoryCtrl.text = shop.category ?? '';
    _existingBannerUrl = shop.bannerUrl;
    _existingLogoUrl = shop.logoUrl;
    _isPublished = shop.isPublished;
  }

  Future<void> _pickBanner() async {
    final xfile = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
    if (xfile != null) setState(() => _bannerFile = File(xfile.path));
  }

  Future<void> _pickLogo() async {
    final xfile = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (xfile != null) setState(() => _logoFile = File(xfile.path));
  }

  @override
  Widget build(BuildContext context) {
    final myShopAsync = ref.watch(myShopProvider);
    myShopAsync.whenData(_prefill);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('My Shop'),
        centerTitle: true,
      ),
      body: myShopAsync.isLoading && !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                GestureDetector(
                  onTap: _pickBanner,
                  child: Container(
                    height: 130,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.darkSurface2,
                      borderRadius: BorderRadius.circular(12),
                      image: _bannerFile != null
                          ? DecorationImage(
                              image: FileImage(_bannerFile!), fit: BoxFit.cover)
                          : _existingBannerUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(_existingBannerUrl!),
                                  fit: BoxFit.cover)
                              : null,
                    ),
                    child: _bannerFile == null && _existingBannerUrl == null
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    color: Colors.white38, size: 28),
                                SizedBox(height: 6),
                                Text('Shop banner',
                                    style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _pickLogo,
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.darkSurface2,
                        backgroundImage: _logoFile != null
                            ? FileImage(_logoFile!)
                            : _existingLogoUrl != null
                                ? NetworkImage(_existingLogoUrl!) as ImageProvider
                                : null,
                        child: _logoFile == null && _existingLogoUrl == null
                            ? const Icon(Icons.storefront_rounded,
                                color: Colors.white38)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Tap the banner or logo to change them',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Shop name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _categoryCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      labelText: 'Category (e.g. Bakery, Clothing, Photography)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bioCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      labelText: 'About your shop (optional)'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.secondary,
                  title: const Text('Published',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _isPublished
                        ? 'Visible to everyone in the marketplace and on your profile'
                        : 'Draft — only you can see this shop',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: _isPublished,
                  onChanged: (v) => setState(() => _isPublished = v),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _onSave,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save shop'),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _onSave() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Give your shop a name')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = MarketplaceRepository.instance;
      final uid = SupabaseService.currentUserId!;

      var bannerUrl = _existingBannerUrl;
      if (_bannerFile != null) {
        bannerUrl = await repo.uploadShopImage(_bannerFile!, suffix: 'banner');
      }
      var logoUrl = _existingLogoUrl;
      if (_logoFile != null) {
        logoUrl = await repo.uploadShopImage(_logoFile!, suffix: 'logo');
      }

      await repo.upsertShop(
        name: name,
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        bannerUrl: bannerUrl,
        logoUrl: logoUrl,
        category: _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim(),
        isPublished: _isPublished,
      );

      if (!mounted) return;
      ref.invalidate(myShopProvider);
      ref.invalidate(shopProvider(uid));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Shop saved')));
      context.pop();
    } catch (e) {
      debugPrint('ManageShopScreen save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't save your shop — check your connection "
              'and try again.')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
