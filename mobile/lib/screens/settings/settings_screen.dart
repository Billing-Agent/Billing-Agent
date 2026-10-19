import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final userSubtitle = user != null ? '${user.name} (${user.email})' : 'Not Logged In';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        children: [
          _buildSectionHeader(context, 'Account'),
          _buildSettingsItem(
            context,
            icon: Icons.person_outline,
            title: 'Profile',
            subtitle: userSubtitle,
          ),
          _buildSettingsItem(
            context,
            icon: Icons.payment_outlined,
            title: 'Payment Methods',
            subtitle: 'Manage saved cards',
          ),
          const Divider(),
          _buildSectionHeader(context, 'Preferences'),
          _buildSettingsItem(context, icon: Icons.notifications_none, title: 'Notifications'),
          _buildSettingsItem(context, icon: Icons.security, title: 'Security', subtitle: 'Biometrics & PIN'),
          const Divider(),
          _buildSectionHeader(context, 'About'),
          _buildSettingsItem(
            context,
            icon: Icons.info_outline,
            title: 'App Version',
            subtitle: '1.0.0 (Phase 6 Authentication)',
          ),
          const Divider(),
          ListTile(
            key: const Key('logout_button'),
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildSettingsItem(BuildContext context, {required IconData icon, required String title, String? subtitle}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title settings will be available later.')),
        );
      },
    );
  }
}
