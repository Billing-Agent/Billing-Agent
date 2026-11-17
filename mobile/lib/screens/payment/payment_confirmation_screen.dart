import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../models/bill.dart';
import '../../models/payment_method.dart';
import '../../models/transaction.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/errors/app_errors.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/providers.dart';
import '../../repositories/payment_repository.dart';
import '../../services/payhere_checkout_service.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/payment_result_dialog.dart';
import '../../widgets/primary_button.dart';

enum _PaymentProgressStage { idle, openingPayHere, confirmingStatus }

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
  _PaymentProgressStage _progressStage = _PaymentProgressStage.idle;
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
      _progressStage = _PaymentProgressStage.idle;
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
      setState(() {
        _progressStage = _PaymentProgressStage.openingPayHere;
      });
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
        _progressStage = _PaymentProgressStage.idle;
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
      _progressStage = _PaymentProgressStage.confirmingStatus;
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
        _progressStage = _PaymentProgressStage.idle;
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
        _progressStage = _PaymentProgressStage.idle;
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
        return PaymentResultDialog(
          status: status,
          title: title,
          transactionId: transactionId,
          amount: amount,
          currency: currency,
          message: message,
          onRetry: canRetry
              ? () {
                  Navigator.of(ctx).pop();
                  // Reset state for a fresh attempt.
                  setState(() {
                    _transactionId = null;
                    _idempotencyKey = const Uuid().v4();
                  });
                }
              : null,
          onPrimary: () {
            Navigator.of(ctx).pop();
            if (status == 'SUCCESS') {
              context.go('/bills');
            }
          },
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
          _progressStage = _PaymentProgressStage.idle;
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
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Payment')),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spacingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review before continuing',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spacingXSmall),
              Text(
                'Check the amount and destination. PayHere opens only after you confirm.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spacingLarge),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spacingXLarge),
                  child: Column(
                    children: [
                      Container(
                        key: const Key('payhere_sandbox_badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacingMedium,
                          vertical: AppConstants.spacingSmall,
                        ),
                        decoration: BoxDecoration(
                          color: semantic.informationContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.science_outlined,
                              size: AppConstants.iconSmall,
                              color: semantic.onInformationContainer,
                            ),
                            const SizedBox(width: AppConstants.spacingXSmall),
                            Text(
                              'PAYHERE SANDBOX',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: semantic.onInformationContainer,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingLarge),
                      Text(
                        'Amount to pay',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingXSmall),
                      AmountText(
                        amount: widget.bill!.amountDue,
                        currency: widget.bill!.currency,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingXLarge),
                      const Divider(height: 1),
                      const SizedBox(height: AppConstants.spacingLarge),
                      _buildDetailRow(
                        context,
                        'Biller',
                        widget.bill!.biller,
                      ),
                      const SizedBox(height: AppConstants.spacingMedium),
                      _buildDetailRow(
                        context,
                        'Account',
                        _maskedAccount(widget.bill!.accountNumber),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingLarge),
              Text(
                'Payment method',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spacingSmall),
              paymentMethodsAsync.when(
                data: (methods) {
                  if (methods.isEmpty) {
                    return Card(
                      child: Padding(
                        padding:
                            const EdgeInsets.all(AppConstants.spacingLarge),
                        child: Row(
                          children: [
                            Icon(
                              Icons.credit_card_off_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppConstants.spacingMedium),
                            const Expanded(
                              child: Text(
                                'No payment methods found. Please add one before continuing.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final method = methods.first;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppConstants.spacingLarge),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMedium,
                              ),
                            ),
                            child: Icon(
                              Icons.credit_card_rounded,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: AppConstants.spacingMedium),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  method.cardBrand ?? method.provider,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(
                                  height: AppConstants.spacingXSmall,
                                ),
                                Text(
                                  'Ending in ${method.lastFour ?? "••••"}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 20,
                            color: theme.colorScheme.secondary,
                          ),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingLarge),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppConstants.spacingMedium),
                        Text(
                          'Loading payment method…',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                error: (err, stack) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingLarge),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: AppConstants.spacingMedium),
                        const Expanded(
                          child: Text('Failed to load payment methods.'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingLarge),
              Container(
                key: const Key('payment_trust_copy'),
                padding: const EdgeInsets.all(AppConstants.spacingMedium),
                decoration: BoxDecoration(
                  color: semantic.surfaceSubtle,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMedium),
                  border: Border.all(color: semantic.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: AppConstants.spacingSmall),
                    Expanded(
                      child: Text(
                        'PayHere Sandbox collects the payment. Final status is confirmed only from PayHere provider data by the Billing Agent backend.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spacingXLarge),
            ],
          ),
        ),
      ),
      bottomNavigationBar: paymentMethodsAsync.maybeWhen(
        data: (methods) => methods.isNotEmpty
            ? Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: semantic.border)),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.all(AppConstants.spacingLarge),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_progressStage != _PaymentProgressStage.idle) ...[
                        _buildProgressCard(context),
                        const SizedBox(height: AppConstants.spacingMedium),
                      ],
                      PrimaryButton(
                        key: const Key('confirm_payment_button'),
                        label: 'Confirm and open PayHere',
                        isLoading: _isLoading,
                        onPressed: _isLoading
                            ? null
                            : () => _confirmPayment(methods.first),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isOpening = _progressStage == _PaymentProgressStage.openingPayHere;
    final message = isOpening
        ? 'Opening PayHere Sandbox…'
        : 'Confirming payment status with the backend…';

    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingLarge),
        decoration: BoxDecoration(
          color: semantic.informationContainer,
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          border: Border.all(color: semantic.information.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: semantic.onInformationContainer,
              ),
            ),
            const SizedBox(width: AppConstants.spacingMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    key: const Key('payment_progress_message'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: semantic.onInformationContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingXSmall),
                  Text(
                    isOpening
                        ? 'Complete or close the sandbox checkout to continue.'
                        : 'The app will not report success until the backend confirms it.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: semantic.onInformationContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(width: AppConstants.spacingMedium),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  String _maskedAccount(String accountNumber) {
    final trimmed = accountNumber.trim();
    if (trimmed.isEmpty) return 'Not available';
    if (trimmed.length <= 4) return '••••';
    final visibleDigits = trimmed.substring(trimmed.length - 4);
    return '•••• $visibleDigits';
  }
}
