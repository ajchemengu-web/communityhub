import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/portfolio_repository.dart';

/// Entry point for "Make/View Portfolio" -- either the current user's
/// own portfolio (create/edit, via a single-sign-on handoff into
/// Profolio) or someone else's *published* portfolio (read-only, no
/// login involved at all). Which mode this is in is entirely determined
/// by [userId]: null or equal to the signed-in user's id means "mine".
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key, this.userId});

  /// Whose portfolio to open. Null (the nav-bar entry point) always
  /// means "my own". A non-null value that happens to be the current
  /// user's own id (reached from your own profile's shop-bar equivalent)
  /// also means "mine" -- only a *different* user's id puts this in
  /// read-only view mode.
  final String? userId;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  bool get _isOwnPortfolio =>
      widget.userId == null || widget.userId == SupabaseService.currentUserId;

  bool _isLoading = true;
  String? _error;
  String? _url;
  bool _noPublishedPortfolio = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _noPublishedPortfolio = false;
    });
    try {
      final repo = PortfolioRepository.instance;
      final url = _isOwnPortfolio
          ? await repo.fetchOwnPortfolioUrl()
          : await repo.fetchPublishedPortfolioUrl(widget.userId!);
      if (!mounted) return;
      if (url == null) {
        setState(() {
          _noPublishedPortfolio = true;
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _url = url;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: Text(_isOwnPortfolio ? 'My Portfolio' : 'Portfolio'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _noPublishedPortfolio
                  ? const _EmptyPortfolioState()
                  : _PortfolioWebView(url: _url!),
    );
  }
}

class _PortfolioWebView extends StatefulWidget {
  const _PortfolioWebView({required this.url});
  final String url;

  @override
  State<_PortfolioWebView> createState() => _PortfolioWebViewState();
}

class _PortfolioWebViewState extends State<_PortfolioWebView> {
  late final WebViewController _controller;
  bool _pageLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _pageLoading = true),
        onPageFinished: (_) => setState(() => _pageLoading = false),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_pageLoading)
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.darkBackground,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _EmptyPortfolioState extends StatelessWidget {
  const _EmptyPortfolioState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, color: Colors.white24, size: 56),
            SizedBox(height: 16),
            Text(
              "This person hasn't published a portfolio yet",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text('Could not open your portfolio: $message',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
