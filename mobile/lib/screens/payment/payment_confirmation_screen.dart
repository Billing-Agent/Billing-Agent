import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../models/bill.dart';
import '../../models/payment_method.dart';
import '../../models/transaction.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/money_utils.dart';
import '../../core/errors/app_errors.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/providers.dart';
import '../../repositories/payment_repository.dart';
import '../../services/payhere_checkout_service.dart';
import '../../widgets/primary_button.dart';

class PaymentConfirmationScreen extends ConsumerStatefulWidget {
  final Bill? bill;

  const PaymentConfirmationScreen({super.key, this.bill});

  @override
  ConsumerState<PaymentConfirmationScreen> createState() =>
      _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState
    extends ConsumerState<PaymentConfirmationScreen> {
  late String _idempotencyKey;
  late final AuthenticatedSession? _originSession;
  String? _transactionId;
  bool _isLoading = false;
  Route<dynamic>? _resultDialogRoute;

  bool get _isCurrentSession => _originSession?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    _originSession = ref.read(authenticatedSessionProvider);
    // Generate a single idempotency key for this payment intent
    _idempotencyKey = const Uuid().v4();
  }

  Future<void> _confirmPayment(PaymentMethod paymentMethod) async {
    if (!_isCurrentSession || widget.bill == null || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    final repository = ref.read(paymentRepositoryProvider);
    final checkoutService = ref.read(payHereCheckoutServiceProvider);

    try {
      // 1. Prepare payment transaction idempotently (or reuse if already prepared)
      if (_transactionId == null) {
        final transaction = await repository.preparePayment(
          widget.bill!.id,
          paymentMethod.id,
          _idempotencyKey,
        );
        if (!_isCurrentSession) return;
        _transactionId = transaction.id;
      }

      final activeTxId = _transactionId!;

      // 2. Initiate PayHere checkout parameters (signed server-side)
      final initiateResponse = await repository.initiatePayment(activeTxId);
      if (!_isCurrentSession) return;

      // 3. Launch PayHere mobile sandbox checkout
      checkoutService.startPayment(
        initiateResponse: initiateResponse,
        onCompleted: (paymentId) {
          if (!_isCurrentSession) return;
          // PayHere client callback must NOT mark payment successful locally.
          // The backend webhook is authoritative.
          _verifyBackendTransactionStatus(activeTxId, wasDismissed: false);
        },
        onError: (error) {
          if (!_isCurrentSession) return;
          _handleCheckoutError(activeTxId, error);
        },
        onDismissed: () {
          if (!_isCurrentSession) return;
          // User closed checkout sheet; verify backend status
          _verifyBackendTransactionStatus(activeTxId, wasDismissed: true);
        },
      );
    } catch (e) {
      if (!mounted || !_isCurrentSession) return;
      setState(() {
        _isLoading = false;
      });
      String msg = 'An unexpected error occurred.';
      if (e is AppError) {
        msg = e.message;
      } else {
        msg = e.toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _handleCheckoutError(String transactionId, String error) {
    if (!mounted || !_isCurrentSession) return;
    // Check if the backend already recorded a financial state
    _verifyBackendTransactionStatus(
      transactionId,
      wasDismissed: false,
      fallbackErrorMessage:
          error.isNotEmpty ? error : 'Payment checkout was interrupted.',
    );
  }

  Future<void> _verifyBackendTransactionStatus(
    String transactionId, {
    required bool wasDismissed,
    String? fallbackErrorMessage,
  }) async {
    if (!mounted || !_isCurrentSession) return;
    setState(() {
      _isLoading = true;
    });

    final repository = ref.read(paymentRepositoryProvider);

    try {
      // PayHere webhook might have slight network latency, so allow up to 2 brief
      // checks if user completed checkout and status is still PENDING.
      Transaction? transaction;
      int attempts = 0;
      const maxAttempts = 3;

      while (attempts < maxAttempts) {
        transaction = await repository.getPaymentStatus(transactionId);
        if (!mounted || !_isCurrentSession) return;
        if (transaction != null && transaction.status != 'PENDING') {
          break;
        }
        attempts++;
        if (attempts < maxAttempts && !wasDismissed) {
          await Future.delayed(const Duration(milliseconds: 1200));
          if (!mounted || !_isCurrentSession) return;
        } else {
          break;
        }
      }

      if (!mounted || !_isCurrentSession) return;
      setState(() {
        _isLoading = false;
      });

      if (transaction == null) {
        if (fallbackErrorMessage != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(fallbackErrorMessage)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Unable to retrieve payment status. Please check your transaction history.')),
          );
        }
        return;
      }

      final status = transaction.status.toUpperCase();

      if (status == 'SUCCESS') {
        // Refresh application state so bill is not shown unpaid & history reflects success
        ref.invalidate(userBillsProvider);
        ref.invalidate(userTransactionsProvider);
        if (widget.bill != null) {
          ref.invalidate(billDetailsProvider(widget.bill!.id));
        }

        _showPaymentResultDialog(
          status: 'SUCCESS',
          title: 'Payment Successful',
          transactionId: transaction.id,
          amount: transaction.amount,
          currency: transaction.currency,
        );
      } else if (status == 'FAILED') {
        _showPaymentResultDialog(
          status: 'FAILED',
          title: 'Payment Failed',
          transactionId: transaction.id,
          amount: transaction.amount,
          currency: transaction.currency,
          canRetry: true,
        );
      } else if (status == 'CANCELLED') {
        _showPaymentResultDialog(
          status: 'CANCELLED',
          title: 'Payment Cancelled',
          transactionId: transaction.id,
          amount: transaction.amount,
          currency: transaction.currency,
        );
      } else {
        // Status remains PENDING on backend
        if (wasDismissed) {
          _showPaymentResultDialog(
            status: 'CANCELLED',
            title: 'Payment Cancelled',
            transactionId: transaction.id,
            amount: transaction.amount,
            currency: transaction.currency,
          );
        } else {
          _showPaymentResultDialog(
            status: 'PENDING',
            title: 'Payment Processing',
            message: 'Your payment is still being confirmed.',
            transactionId: transaction.id,
            amount: transaction.amount,
            currency: transaction.currency,
          );
        }
      }
    } catch (e) {
      if (!mounted || !_isCurrentSession) return;
      setState(() {
        _isLoading = false;
      });
      // Do not convert network errors into FAILED financial status
      String msg = 'Unable to verify payment status with server.';
      if (e is AppError) {
        msg = e.message;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _showPaymentResultDialog({
    required String status,
    required String title,
    required String transactionId,
    required String amount,
    required String currency,
    String? message,
    bool canRetry = false,
  }) {
    if (!_isCurrentSession) return;
    Route<dynamic>? openedRoute;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        openedRoute = ModalRoute.of(ctx);
        _resultDialogRoute = openedRoute;
        IconData icon;
        Color color;
        switch (status) {
          case 'SUCCESS':
            icon = Icons.check_circle;
            color = Colors.green;
            break;
          case 'FAILED':
            icon = Icons.error;
            color = Colors.red;
            break;
          case 'CANCELLED':
            icon = Icons.cancel;
            color = Colors.orange;
            break;
          case 'PENDING':
          default:
            icon = Icons.hourglass_top;
            color = Colors.blue;
            break;
        }

        return AlertDialog(
          key: const Key('payment_result_dialog'),
          title: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  key: const Key('payment_result_title'),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[
                Text(message, key: const Key('payment_result_message')),
                const SizedBox(height: 12),
              ],
              Text('Amount: $currency $amount',
                  key: const Key('payment_result_amount')),
              const SizedBox(height: 6),
              Text('Transaction ID: $transactionId',
                  key: const Key('payment_result_tx_id')),
            ],
          ),
          actions: [
            if (canRetry)
              TextButton(
                key: const Key('payment_result_retry_button'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  // Reset state for a fresh attempt
                  setState(() {
                    _transactionId = null;
                    _idempotencyKey = const Uuid().v4();
                  });
                },
                child: const Text('Retry'),
              ),
            TextButton(
              key: const Key('payment_result_primary_button'),
              onPressed: () {
                Navigator.of(ctx).pop();
                if (status == 'SUCCESS') {
                  context.go('/bills');
                }
              },
              child: Text(status == 'SUCCESS' ? 'View Bills' : 'OK'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      if (identical(_resultDialogRoute, openedRoute)) {
        _resultDialogRoute = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authenticatedSessionProvider);
    ref.listen<AuthenticatedSession?>(
      authenticatedSessionProvider,
      (previous, next) {
        if (identical(previous, next) || !mounted) return;
        final dialogRoute = _resultDialogRoute;
        if (dialogRoute != null) {
          Navigator.of(context, rootNavigator: true).removeRoute(dialogRoute);
          _resultDialogRoute = null;
        }
        setState(() {
          _transactionId = null;
          _idempotencyKey = const Uuid().v4();
          _isLoading = false;
        });
      },
    );

    if (!_isCurrentSession) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm Payment')),
        body: const Center(
          child: Text(
            'This payment session has ended. Please select the bill again.',
            key: Key('payment_session_ended_message'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (widget.bill == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm Payment')),
        body: const Center(child: Text('Bill not found.')),
      );
    }

    final paymentMethodsAsync = ref.watch(userPaymentMethodsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Payment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review your payment',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppConstants.paddingMedium),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingLarge),
                child: Column(
                  children: [
                    _buildDetailRow(context, 'Biller', widget.bill!.biller),
                    const Divider(height: AppConstants.paddingMedium),
                    _buildDetailRow(
                        context, 'Account Number', widget.bill!.accountNumber),
                    const Divider(height: AppConstants.paddingMedium),
                    _buildDetailRow(
                      context,
                      'Total Amount',
                      MoneyUtils.formatAmount(widget.bill!.amountDue,
                          currency: widget.bill!.currency),
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppConstants.paddingMedium),

            // Payment Methods Section
            paymentMethodsAsync.when(
              data: (methods) {
                if (methods.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppConstants.paddingLarge),
                      child: Text('No payment methods found. Please add one.'),
                    ),
                  );
                }
                final method = methods.first; // Use the first method for now
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.credit_card),
                    title: const Text('Payment Method'),
                    subtitle: Text(
                        '${method.cardBrand ?? method.provider} ending in ${method.lastFour ?? "****"}'),
                    trailing: TextButton(
                      onPressed: () {},
                      child: const Text('Change'),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppConstants.paddingLarge),
                  child: Text('Failed to load payment methods.'),
                ),
              ),
            ),

            const SizedBox(height: AppConstants.paddingLarge * 2),

            paymentMethodsAsync.maybeWhen(
              data: (methods) => methods.isNotEmpty
                  ? PrimaryButton(
                      key: const Key('confirm_payment_button'),
                      label: 'Confirm Payment',
                      isLoading: _isLoading,
                      onPressed: _isLoading
                          ? null
                          : () => _confirmPayment(methods.first),
                    )
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),

            const SizedBox(height: AppConstants.paddingMedium),
            const Center(
              child: Text(
                'By confirming, you agree to the Terms of Service.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value,
      {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
                fontSize: isTotal ? 20 : null,
                color: isTotal ? Theme.of(context).colorScheme.primary : null,
              ),
        ),
      ],
    );
  }
}
