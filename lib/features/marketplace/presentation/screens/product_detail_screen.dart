import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../payments/domain/models/payment_transaction_model.dart';
import '../../../payments/presentation/widgets/payment_method_sheet.dart';
import '../../data/marketplace_repository.dart';
import '../../domain/models/product_model.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  ProductModel? _product;
  bool _isLoading = true;
  int _quantity = 1;
  bool _isBuying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final product =
        await MarketplaceRepository.instance.fetchProductById(widget.productId);
    if (!mounted) return;
    setState(() {
      _product = product;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Listing'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _product == null
              ? const Center(
                  child: Text('Listing not found', style: TextStyle(color: Colors.white54)),
                )
              : _buildBody(_product!),
    );
  }

  Widget _buildBody(ProductModel product) {
    return ListView(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: product.coverImage != null
              ? CachedNetworkImage(imageUrl: product.coverImage!, fit: BoxFit.cover)
              : Container(
                  color: AppColors.darkSurface2,
                  child: const Icon(Icons.image_outlined, color: Colors.white38, size: 48),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${product.currency} ${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: AppColors.secondary, fontSize: 18, fontWeight: FontWeight.w600)),
              if (product.sellerName != null) ...[
                const SizedBox(height: 10),
                // Trust signal + the "on clicked, redirect to the shop"
                // path for browsing: the marketplace grid and this page
                // both lead with the product first (research: fewer taps
                // to a Buy button converts better), and the seller/shop
                // is one tap away from here rather than the default
                // landing spot.
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.push('/shop/${product.sellerId}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.darkSurface2,
                          backgroundImage: product.sellerAvatarUrl != null
                              ? CachedNetworkImageProvider(product.sellerAvatarUrl!)
                              : null,
                          child: product.sellerAvatarUrl == null
                              ? const Icon(Icons.storefront_rounded,
                                  size: 14, color: Colors.white38)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Sold by ${product.sellerName}',
                              style: const TextStyle(color: Colors.white70)),
                        ),
                        const Text('Visit shop',
                            style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.secondary, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
              if (product.description != null) ...[
                const SizedBox(height: 16),
                Text(product.description!, style: const TextStyle(color: Colors.white70)),
              ],
              if (product.isSoldOut) ...[
                const SizedBox(height: 16),
                const Text('Sold out', style: TextStyle(color: AppColors.error)),
              ] else ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('Quantity', style: TextStyle(color: Colors.white70)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                      onPressed: _quantity > 1
                          ? () => setState(() => _quantity--)
                          : null,
                    ),
                    Text('$_quantity', style: const TextStyle(color: Colors.white)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                      onPressed: () => setState(() => _quantity++),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isBuying ? null : () => _onBuy(product),
                    child: _isBuying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Buy now · ${product.currency} ${(product.price * _quantity).toStringAsFixed(2)}',
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onBuy(ProductModel product) async {
    setState(() => _isBuying = true);
    try {
      final repo = MarketplaceRepository.instance;
      final orderId = await repo.createOrder(product: product, quantity: _quantity);

      if (!mounted) return;
      final PaymentTransactionModel? transaction = await showPaymentMethodSheet(
        context,
        amount: product.price * _quantity,
        purpose: PaymentPurpose.order,
        referenceId: orderId,
        currency: product.currency,
        recipientType: product.communityId != null ? 'community' : 'platform',
        recipientId: product.communityId,
      );

      if (transaction != null) {
        await repo.attachTransaction(orderId, transaction.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order placed!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBuying = false);
    }
  }
}
