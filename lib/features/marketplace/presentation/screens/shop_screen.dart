import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../chat/data/chat_repository.dart';
import '../../domain/models/product_model.dart';
import '../providers/marketplace_provider.dart';

/// Public storefront — reached by tapping a product's seller header on
/// ProductDetailScreen, or from a profile page's shop tile. Anyone can
/// view a published shop; only the owner can reach ManageShopScreen to
/// edit it (RLS on the `shops` table enforces this server-side too, this
/// screen just doesn't show an edit affordance to non-owners).
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key, required this.ownerId});
  final String ownerId;

  /// Loading/errored/no-shop-here all render as a plain screen with a
  /// bare AppBar -- unlike the "shop loaded" branch, which builds its own
  /// SliverAppBar behind the banner image. These three used to render
  /// with no AppBar at all, which meant no back button and no way off
  /// the screen besides the system back gesture -- a real dead end.
  Widget _plainScaffold(Widget body) => Scaffold(
        backgroundColor: AppColors.darkBackground,
        appBar: AppBar(
          backgroundColor: AppColors.darkSurface,
          foregroundColor: Colors.white,
        ),
        body: body,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = SupabaseService.currentUserId == ownerId;
    final shopAsync = ref.watch(shopProvider(ownerId));

    return shopAsync.when(
      loading: () =>
          _plainScaffold(const Center(child: CircularProgressIndicator())),
      error: (e, _) => _plainScaffold(_ErrorState(
        message: '$e',
        onRetry: () => ref.invalidate(shopProvider(ownerId)),
      )),
      data: (shop) {
        if (shop == null) {
          return _plainScaffold(_EmptyShopState(isOwner: isOwner));
        }
        final productsAsync = ref.watch(shopProductsProvider(ownerId));
        return Scaffold(
          backgroundColor: AppColors.darkBackground,
          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(shopProvider(ownerId));
              ref.invalidate(shopProductsProvider(ownerId));
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: AppColors.darkSurface,
                  foregroundColor: Colors.white,
                  expandedHeight: 200,
                  pinned: true,
                  actions: [
                    if (isOwner)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit shop',
                        onPressed: () => context.push(AppRoutes.manageShop),
                      ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: shop.bannerUrl != null
                        ? CachedNetworkImage(
                            imageUrl: shop.bannerUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: AppColors.darkSurface2,
                            child: const Icon(Icons.storefront_rounded,
                                color: Colors.white24, size: 56),
                          ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: AppColors.darkSurface2,
                              backgroundImage: shop.logoUrl != null
                                  ? CachedNetworkImageProvider(shop.logoUrl!)
                                  : null,
                              child: shop.logoUrl == null
                                  ? const Icon(Icons.storefront_rounded,
                                      color: Colors.white38)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(shop.name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold)),
                                  if (shop.category != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(shop.category!,
                                          style: const TextStyle(
                                              color: AppColors.secondary,
                                              fontSize: 13)),
                                    ),
                                  if (shop.ownerName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          if (shop.ownerAvatarUrl != null)
                                            CircleAvatar(
                                              radius: 8,
                                              backgroundImage:
                                                  CachedNetworkImageProvider(
                                                      shop.ownerAvatarUrl!),
                                            ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'Run by ${shop.ownerName}',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (shop.bio != null) ...[
                          const SizedBox(height: 12),
                          Text(shop.bio!,
                              style: const TextStyle(color: Colors.white70)),
                        ],
                        if (!isOwner) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _messageSeller(context),
                              icon: const Icon(Icons.chat_bubble_outline_rounded,
                                  size: 18),
                              label: const Text('Message seller'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: AppColors.darkBorder),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const Text('Inventory',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                productsAsync.when(
                  loading: () => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: _ErrorState(message: '$e'),
                  ),
                  data: (products) => products.isEmpty
                      ? const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text('No listings yet',
                                  style: TextStyle(color: Colors.white54)),
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.72,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) =>
                                  _ShopProductCard(product: products[i]),
                              childCount: products.length,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _messageSeller(BuildContext context) async {
    try {
      final convo =
          await ChatRepository.instance.getOrCreateDirectConversation(ownerId);
      if (context.mounted) context.push('/chat/${convo.id}');
    } catch (e) {
      debugPrint('ShopScreen _messageSeller failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open chat — please try again.')));
      }
    }
  }
}

class _ShopProductCard extends StatelessWidget {
  const _ShopProductCard({required this.product});
  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/marketplace/${product.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurface2,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.coverImage != null
                      ? CachedNetworkImage(
                          imageUrl: product.coverImage!, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.darkBorder,
                          child: const Icon(Icons.image_outlined,
                              color: Colors.white38, size: 32),
                        ),
                  if (product.isSoldOut)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('SOLD OUT',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${product.currency} ${product.price.toStringAsFixed(0)}',
                      style: const TextStyle(color: AppColors.secondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyShopState extends StatelessWidget {
  const _EmptyShopState({required this.isOwner});
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined,
                color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            Text(
              isOwner
                  ? "You haven't set up a shop yet"
                  : "This user doesn't have a shop yet",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            if (isOwner) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.push(AppRoutes.manageShop),
                child: const Text('Start selling'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Keep the raw exception in the debug log, not on screen -- a
    // person shouldn't have to parse a stack trace to know their
    // internet dropped.
    debugPrint('ShopScreen error: $message');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white38, size: 40),
            const SizedBox(height: 12),
            const Text("Couldn't load this shop",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Check your connection and try again.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
