import 'package:flutter/material.dart';

import '../core/utils/money_utils.dart';

class AmountText extends StatelessWidget {
  final String amount;
  final String currency;
  final TextStyle? style;
  final TextAlign? textAlign;

  const AmountText({
    super.key,
    required this.amount,
    required this.currency,
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      MoneyUtils.formatAmount(amount, currency: currency),
      textAlign: textAlign,
      style: style ??
          theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}
