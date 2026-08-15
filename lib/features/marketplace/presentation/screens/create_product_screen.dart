import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/marketplace_repository.dart';
import '../../domain/models/product_model.dart';
import '../providers/marketplace_provider.dart';

/// Add-or-edit form for one listing. Passing [product] switches this into
/// edit mode: fields prefill from it, the copy changes from "New Listing"
/// / "Publish listing" to "Edit Listing" / "Save changes", and submitting
/// calls [MarketplaceRepository.updateProduct] instead of `createProduct`.
/// Reached either from the marketplace's "+" FAB (create) or from the shop
/// admin dashboard's Listings tab (either mode).
class CreateProductScreen extends ConsumerStatefulWidget {
  const CreateProductScreen({super.key, this.product});

  /// Null = creating a new listing. Non-null = editing this one.
  final ProductModel? product;

  @override
  ConsumerState<CreateProductScreen> createState() =>
      _CreateProductScreenState();
}

class _CreateProductScreenState extends ConsumerState<CreateProductScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _picker = ImagePicker();

  ProductType _type = ProductType.merch;
  File? _imageFile;
  String? _existingImageUrl;
  bool _isSubmitting = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _type = p.type;
      _titleCtrl.text = p.title;
      _descCtrl.text = p.description ?? '';
      _priceCtrl.text = p.price % 1 == 0
          ? p.price.toStringAsFixed(0)
          : p.price.toString();
      _stockCtrl.text = p.stock?.toString() ?? '';
      _existingImageUrl = p.coverImage;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (xfile != null) setState(() => _imageFile = File(xfile.path));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: Text(_isEditing ? 'Edit Listing' : 'New Listing'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.darkSurface2,
                borderRadius: BorderRadius.circular(12),
                image: _imageFile != null
                    ? DecorationImage(
                        image: FileImage(_imageFile!), fit: BoxFit.cover)
                    : _existingImageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_existingImageUrl!),
                            fit: BoxFit.cover)
                        : null,
              ),
              child: _imageFile == null && _existingImageUrl == null
                  ? const Center(
                      child: Icon(Icons.add_photo_alternate_outlined,
                          color: Colors.white38, size: 32),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ProductType>(
            initialValue: _type,
            dropdownColor: AppColors.darkSurface2,
            decoration: const InputDecoration(labelText: 'Type'),
            items: ProductType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(ProductModel.typeString(t)),
                    ))
                .toList(),
            // Type is set once at creation and reflects checkout-relevant
            // behavior elsewhere in the app -- editing it after listings
            // and orders already exist against it is out of scope here,
            // same as most marketplaces (Kilimall's category field is
            // similarly locked once a product has stock/orders against it).
            onChanged: _isEditing
                ? null
                : (t) => setState(() => _type = t ?? ProductType.merch),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Description (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Price', prefixText: 'KES '),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stockCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Stock (leave blank for unlimited)',
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _onSubmit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save changes' : 'Publish listing'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSubmit() async {
    final title = _titleCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    if (title.isEmpty || price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title and a valid price')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = MarketplaceRepository.instance;
      final uid = SupabaseService.currentUserId!;
      final description =
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
      final stock = int.tryParse(_stockCtrl.text.trim());

      List<String>? images;
      if (_imageFile != null) {
        images = [await repo.uploadProductImage(_imageFile!, uid)];
      } else if (!_isEditing) {
        images = const [];
      } // else: editing with no new image picked -- leave images untouched

      if (_isEditing) {
        await repo.updateProduct(
          widget.product!.id,
          title: title,
          description: description,
          price: price,
          images: images,
          stock: stock,
        );
      } else {
        await repo.createProduct(
          type: _type,
          title: title,
          price: price,
          description: description,
          images: images ?? const [],
          stock: stock,
        );
      }

      if (!mounted) return;
      ref.read(marketplaceProvider.notifier).refresh();
      ref.invalidate(myListingsProvider);
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('CreateProductScreen submit failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEditing
              ? "Couldn't save changes — please try again."
              : "Couldn't publish this listing — please try again.")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
