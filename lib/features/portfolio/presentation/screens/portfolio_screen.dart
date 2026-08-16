import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
      // The raw exception (Supabase function/network errors, etc.) goes to
      // the debug log only -- _ErrorState below maps it to something a
      // person can actually act on instead of showing them a stack trace.
      debugPrint('PortfolioScreen load failed: $e');
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
                  // webview_flutter has no web platform implementation
                  // registered in this project (no webview_flutter_web
                  // dependency) — embedding would just throw at runtime.
                  // The web build is already inside a browser, so opening
                  // the portfolio in a new tab is a perfectly natural
                  // substitute rather than a degraded one.
                  : kIsWeb
                      ? _PortfolioWebOpener(url: _url!)
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

  /// True once the WebView has painted anything at all. Only the very
  /// first load blocks the screen behind a full overlay (there's nothing
  /// to see behind it yet); once real content has shown up, a later
  /// in-page navigation (tapping a link inside Profolio) just shows a
  /// thin progress bar over the still-visible previous page, the way a
  /// normal in-app browser would, instead of blanking the whole screen.
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _pageLoading = true),
        onPageFinished: (_) => setState(() {
          _pageLoading = false;
          _hasLoadedOnce = true;
        }),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_pageLoading && !_hasLoadedOnce)
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.darkBackground,
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_pageLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: AppColors.secondary,
            ),
          ),
      ],
    );
  }
}

/// Web substitute for [_PortfolioWebView] — opens the portfolio URL in a
/// new browser tab instead of embedding it, since there's no
/// webview_flutter_web implementation registered. Auto-opens once on
/// first build, with a button to reopen if the tab was blocked/closed.
class _PortfolioWebOpener extends StatefulWidget {
  const _PortfolioWebOpener({required this.url});
  final String url;

  @override
  State<_PortfolioWebOpener> createState() => _PortfolioWebOpenerState();
}

class _PortfolioWebOpenerState extends State<_PortfolioWebOpener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  void _open() {
    launchUrl(Uri.parse(widget.url), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new_rounded, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Your portfolio opened in a new tab.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open again'),
            ),
          ],
        ),
      ),
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

  /// [message] is a raw exception's toString() -- useful in the debug
  /// log (see _PortfolioScreenState._load's catch block), meaningless to
  /// a person looking at their phone. Map the couple of cases worth
  /// distinguishing to plain language and fall back to a generic retry
  /// prompt for everything else, rather than ever showing the raw text.
  String get _friendlyMessage {
    final m = message.toLowerCase();
    if (m.contains('not_found') || m.contains('404')) {
      return "We couldn't reach your portfolio right now. This usually "
          "clears up on its own -- try again in a moment.";
    }
    if (m.contains('socketexception') ||
        m.contains('network') ||
        m.contains('timeout') ||
        m.contains('connection')) {
      return "You're offline, or the connection dropped. Check your "
          'internet and try again.';
    }
    return "Something went wrong opening your portfolio. Please try again.";
  }

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
            Text(_friendlyMessage,
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
