import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/payment_repository.dart';
import '../../domain/models/payment_transaction_model.dart';
import '../../domain/payment_gateway.dart';

enum PaymentFlowStatus {
  idle,
  initiating,
  awaitingConfirmation, // Stripe sheet open / Paystack webview open / M-Pesa STK push sent
  succeeded,
  failed,
}

class PaymentState {
  const PaymentState({
    this.flowStatus = PaymentFlowStatus.idle,
    this.chargeHandle,
    this.transaction,
    this.errorMessage,
  });

  final PaymentFlowStatus flowStatus;
  final ChargeHandle? chargeHandle;
  final PaymentTransactionModel? transaction;
  final String? errorMessage;

  PaymentState copyWith({
    PaymentFlowStatus? flowStatus,
    ChargeHandle? chargeHandle,
    PaymentTransactionModel? transaction,
    String? errorMessage,
  }) =>
      PaymentState(
        flowStatus: flowStatus ?? this.flowStatus,
        chargeHandle: chargeHandle ?? this.chargeHandle,
        transaction: transaction ?? this.transaction,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

class PaymentNotifier extends StateNotifier<PaymentState> {
  PaymentNotifier() : super(const PaymentState());

  final _repo = PaymentRepository.instance;
  StreamSubscription<PaymentTransactionModel>? _sub;

  /// Kicks off a charge. Callers should inspect the returned [ChargeHandle]
  /// to decide next steps (present Stripe sheet / open Paystack webview /
  /// just wait for M-Pesa STK push) — this notifier tracks resolution
  /// either way via realtime.
  Future<ChargeHandle?> initiateCharge(ChargeRequest request) async {
    state = state.copyWith(
        flowStatus: PaymentFlowStatus.initiating, errorMessage: null);
    try {
      final handle = await _repo.charge(request);
      state = state.copyWith(
        flowStatus: PaymentFlowStatus.awaitingConfirmation,
        chargeHandle: handle,
      );
      _watch(handle.transactionId);
      return handle;
    } catch (e) {
      state = state.copyWith(
        flowStatus: PaymentFlowStatus.failed,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  void _watch(String transactionId) {
    _sub?.cancel();
    _sub = _repo.watchTransaction(transactionId).listen((tx) {
      state = state.copyWith(
        transaction: tx,
        flowStatus: tx.status == PaymentStatus.succeeded
            ? PaymentFlowStatus.succeeded
            : tx.status == PaymentStatus.failed ||
                    tx.status == PaymentStatus.cancelled
                ? PaymentFlowStatus.failed
                : PaymentFlowStatus.awaitingConfirmation,
      );
      if (tx.isResolved) {
        _sub?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final paymentProvider =
    StateNotifierProvider.autoDispose<PaymentNotifier, PaymentState>(
  (_) => PaymentNotifier(),
);
