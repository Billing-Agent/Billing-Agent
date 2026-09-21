import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../models/bill.dart';
import '../../models/payment_method.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/money_utils.dart';
import '../../core/errors/app_errors.dart';
import '../../repositories/providers.dart';
import '../../repositories/payment_repository.dart';
import '../../widgets/primary_button.dart';

class PaymentConfirmationScreen extends ConsumerStatefulWidget {
  final Bill? bill;

  const PaymentConfirmationScreen({super.key, this.bill});

  @override
  ConsumerState<PaymentConfirmationScreen> createState() => _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState extends ConsumerState<PaymentConfirmationScreen> {
  late String _idempotencyKey;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Generate a single idempotency key for this payment intent
    _idempotencyKey = const Uuid().v4();
  }

  Future<void> _confirmPayment(PaymentMethod paymentMethod) async {
    if (widget.bill == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final repository = ref.read(paymentRepositoryProvider);
      final transaction = await repository.preparePayment(
        widget.bill!.id, 
        paymentMethod.id, 
        _idempotencyKey,
      );
      
      if (!mounted) return;
      _showSuccessDialog(transaction.id);
    } catch (e) {
      if (!mounted) return;
      String msg = 'An unexpected error occurred.';
      if (e is AppError) {
        msg = e.message;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessDialog(String transactionId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment Prepared'),
        content: Text('Transaction ID: $transactionId\n\nPhase 5: The backend has prepared the transaction in PENDING state. Actual payment processing is not implemented yet.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // Close dialog
              context.go('/bills'); // Return to bills
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppConstants.paddingMedium),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingLarge),
                child: Column(
                  children: [
                    _buildDetailRow(context, 'Biller', widget.bill!.biller),
                    const Divider(height: AppConstants.paddingMedium),
                    _buildDetailRow(context, 'Account Number', widget.bill!.accountNumber),
                    const Divider(height: AppConstants.paddingMedium),
                    _buildDetailRow(
                      context, 
                      'Total Amount', 
                      MoneyUtils.formatAmount(widget.bill!.amountDue, currency: widget.bill!.currency),
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
                    subtitle: Text('${method.cardBrand ?? method.provider} ending in ${method.lastFour ?? "****"}'),
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
                      label: 'Confirm Payment',
                      isLoading: _isLoading,
                      onPressed: _isLoading ? null : () => _confirmPayment(methods.first),
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

  Widget _buildDetailRow(BuildContext context, String label, String value, {bool isTotal = false}) {
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
