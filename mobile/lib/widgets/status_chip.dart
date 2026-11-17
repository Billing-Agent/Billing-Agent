import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  final String status;

  const StatusChip({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final rawStatus = status.trim().toUpperCase();
    final normalizedStatus = rawStatus.isEmpty ? 'UNKNOWN' : rawStatus;
    final palette = _paletteFor(context, normalizedStatus);

    return Semantics(
      label: '$normalizedStatus status',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMedium,
          vertical: AppConstants.spacingXSmall,
        ),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              palette.icon,
              size: AppConstants.iconSmall,
              color: palette.foreground,
            ),
            const SizedBox(width: AppConstants.spacingXSmall),
            Text(
              normalizedStatus,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.foreground,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  _StatusPalette _paletteFor(BuildContext context, String normalizedStatus) {
    final semantic = AppSemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    switch (normalizedStatus) {
      case 'PAID':
      case 'SUCCESS':
      case 'CONFIRMED':
        return _StatusPalette(
          background: semantic.successContainer,
          foreground: semantic.onSuccessContainer,
          border: semantic.success,
          icon: Icons.check_circle_outline_rounded,
        );
      case 'UNPAID':
      case 'PENDING':
      case 'PROCESSING':
      case 'CONFIRMING':
        return _StatusPalette(
          background: semantic.pendingContainer,
          foreground: semantic.onPendingContainer,
          border: semantic.pending,
          icon: Icons.schedule_rounded,
        );
      case 'FAILED':
      case 'ERROR':
        return _StatusPalette(
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
          border: scheme.error,
          icon: Icons.error_outline_rounded,
        );
      case 'CANCELLED':
      case 'CANCELED':
        return _StatusPalette(
          background: semantic.neutralContainer,
          foreground: semantic.onNeutralContainer,
          border: semantic.neutral,
          icon: Icons.cancel_outlined,
        );
      default:
        return _StatusPalette(
          background: semantic.neutralContainer,
          foreground: semantic.onNeutralContainer,
          border: semantic.neutral,
          icon: Icons.help_outline_rounded,
        );
    }
  }
}

class _StatusPalette {
  final Color background;
  final Color foreground;
  final Color border;
  final IconData icon;

  const _StatusPalette({
    required this.background,
    required this.foreground,
    required this.border,
    required this.icon,
  });
}
