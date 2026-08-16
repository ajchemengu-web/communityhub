import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/payment_transaction_model.dart';
import '../../domain/payment_gateway.dart';
import '../providers/payment_provider.dart';

/// Shared bottom sheet used by giving, marketplace checkout, memberships
/// and boosts to pick a payment method and drive the charge to
/// resolution. Returns the resolved [PaymentTransactionModel] once the
/// ledger row settles, or null if the user dismissed the sheet.
Future<PaymentTransactionModel?> showPaymentMethodSheet(
  BuildContext context, {
  required double amount,
  required PaymentPurpose purpose,
  String? referenceId,
  String currency = 'KES',
  String recipientType = 'platform',
  String? recipientId,
}) {
  return showModalBottomSheet<PaymentTransactionModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.darkSurface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _PaymentMethodSheet(
      amount: amount,
      purpose: purpose,
      referenceId: referenceId,
      currency: currency,
      recipientType: recipientType,
      recipientId: recipientId,
    ),
  );
}

class _PaymentMethodSheet extends ConsumerStatefulWidget {
  const _PaymentMethodSheet({
    required this.amount,
    required this.purpose,
    required this.currency,
    required this.recipientType,
    this.referenceId,
    this.recipientId,
  });

  final double amount;
  final PaymentPurpose purpose;
  final String? referenceId;
  final String currency;
  final String recipientType;
  final String? recipientId;

  @override
  ConsumerState<_PaymentMethodSheet> createState() =>
      _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<_PaymentMethodSheet> {
  final _phoneController = TextEditingController();
  PaymentProviderType? _selected;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentProvider);

    ref.listen(paymentProvider, (previous, next) {
      if (next.flowStatus == PaymentFlowStatus.succeeded &&
          next.transaction != null) {
        Navigator.of(context).pop(next.transaction);
      }
    });

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Complete payment',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${widget.currency} ${widget.amount.toStringAsFixed(2)}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: AppColors.secondary)),
            const SizedBox(height: 20),
            _ProviderTile(
              label: 'M-Pesa',
              subtitle: 'Pay with mobile money',
              selected: _selected == PaymentProviderType.mpesa,
              onTap: () =>
                  setState(() => _selected = PaymentProviderType.mpesa),
            ),
            _ProviderTile(
              label: 'Card (Stripe)',
              subtitle: 'Visa, Mastercard, Apple Pay, Google Pay',
              selected: _selected == PaymentProviderType.stripe,
              onTap: () =>
                  setState(() => _selected = PaymentProviderType.stripe),
            ),
            _ProviderTile(
              label: 'Paystack',
              subtitle: 'Card or bank transfer',
              selected: _selected == PaymentProviderType.paystack,
              onTap: () =>
                  setState(() => _selected = PaymentProviderType.paystack),
            ),
            if (_selected == PaymentProviderType.mpesa) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'M-Pesa phone number (2547XXXXXXXX)',
                ),
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(state.errorMessage!,
                  style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected == null ||
                        state.flowStatus == PaymentFlowStatus.initiating ||
                        state.flowStatus == PaymentFlowStatus.awaitingConfirmation
                    ? null
                    : _onPay,
                child: state.flowStatus == PaymentFlowStatus.initiating ||
                        state.flowStatus == PaymentFlowStatus.awaitingConfirmation
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pay now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPay() async {
    final notifier = ref.read(paymentProvider.notifier);
    final request = ChargeRequest(
      provider: _selected!,
      amount: widget.amount,
      purpose: widget.purpose,
      referenceId: widget.referenceId,
      currency: widget.currency,
      recipientType: widget.recipientType,
      recipientId: widget.recipientId,
      phoneNumber: _phoneController.text.trim(),
      email: SupabaseService.currentUser?.email,
    );

    final handle = await notifier.initiateCharge(request);
    if (handle == null || !mounted) return;

    if (_selected == PaymentProviderType.paystack &&
        handle.paystackAuthorizationUrl != null) {
      await _openPaystackCheckout(handle.paystackAuthorizationUrl!);
    }
    // Stripe PaymentSheet confirmation and M-Pesa STK-push prompts are
    // handled outside this sheet (Stripe SDK / phone push respectively) —
    // this sheet just stays open showing a spinner until the realtime
    // listener above resolves the transaction.
  }

  Future<void> _openPaystackCheckout(String url) async {
    if (!mounted) return;
    // webview_flutter has no web platform implementation registered in
    // this project — on web, open Paystack's hosted checkout in a new
    // tab instead of embedding it. The realtime listener above (not the
    // webview itself) is what resolves the transaction either way, so
    // this doesn't lose any completion-detection behavior.
    if (kIsWeb) {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PaystackCheckoutScreen(url: url),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? AppColors.primaryLight : AppColors.darkSurface2,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(label),
        subtitle: Text(subtitle),
        trailing: selected
            ? const Icon(Icons.check_circle, color: AppColors.secondary)
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// Minimal in-app webview for Paystack's hosted checkout page.
class _PaystackCheckoutScreen extends StatefulWidget {
  const _PaystackCheckoutScreen({required this.url});
  final String url;

  @override
  State<_PaystackCheckoutScreen> createState() =>
      _PaystackCheckoutScreenState();
}

class _PaystackCheckoutScreenState extends State<_PaystackCheckoutScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paystack Checkout')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
