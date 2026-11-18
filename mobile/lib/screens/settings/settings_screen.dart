import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spacingLarge),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingLarge),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusLarge),
                    ),
                    child: Icon(
                      Icons.person_outline_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingMedium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'Not signed in',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (user != null) ...[
                          const SizedBox(height: AppConstants.spacingXSmall),
                          Text(
                            user.email,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppConstants.spacingSmall),
                        Text(
                          'Sandbox MVP account',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXLarge),
          _buildSectionHeader(context, 'Account'),
          const SizedBox(height: AppConstants.spacingSmall),
          Card(
            child: Column(
              children: [
                _buildComingSoonItem(
                  context,
                  key: const Key('settings_profile_item'),
                  icon: Icons.badge_outlined,
                  title: 'Profile',
                  subtitle: 'Profile editing is not available yet',
                ),
                Divider(color: semantic.border, height: 1),
                _buildComingSoonItem(
                  context,
                  key: const Key('settings_payment_methods_item'),
                  icon: Icons.payment_outlined,
                  title: 'Payment Methods',
                  subtitle: 'Saved-card management is not available yet',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingXLarge),
          _buildSectionHeader(context, 'Preferences'),
          const SizedBox(height: AppConstants.spacingSmall),
          Card(
            child: Column(
              children: [
                _buildComingSoonItem(
                  context,
                  key: const Key('settings_notifications_item'),
                  icon: Icons.notifications_none_rounded,
                  title: 'Notifications',
                  subtitle: 'Notification preferences are not available yet',
                ),
                Divider(color: semantic.border, height: 1),
                _buildComingSoonItem(
                  context,
                  key: const Key('settings_security_item'),
                  icon: Icons.security_outlined,
                  title: 'Security',
                  subtitle: 'Biometrics and PIN are not available yet',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingXLarge),
          _buildSectionHeader(context, 'About'),
          const SizedBox(height: AppConstants.spacingSmall),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('App Version'),
              subtitle: Text('1.0.0 • Sandbox MVP'),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXLarge),
          Card(
            child: ListTile(
              key: const Key('logout_button'),
              minVerticalPadding: AppConstants.spacingMedium,
              leading: Icon(
                Icons.logout_rounded,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Logout',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () async {
                await ref.read(authProvider.notifier).logout();
              },
            ),
          ),
          const SizedBox(height: AppConstants.spacingLarge),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildComingSoonItem(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);

    return ListTile(
      key: key,
      enabled: false,
      minVerticalPadding: AppConstants.spacingMedium,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          const SizedBox(height: AppConstants.spacingSmall),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingSmall,
              vertical: AppConstants.spacingXSmall,
            ),
            decoration: BoxDecoration(
              color: semantic.neutralContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Coming soon',
              style: theme.textTheme.labelSmall?.copyWith(
                color: semantic.onNeutralContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
