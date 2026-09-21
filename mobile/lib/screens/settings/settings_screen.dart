import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        children: [
          _buildSectionHeader(context, 'Account'),
          _buildSettingsItem(context, icon: Icons.person_outline, title: 'Profile', subtitle: 'Nafris (Mock Data)'),
          _buildSettingsItem(context, icon: Icons.payment_outlined, title: 'Payment Methods', subtitle: 'Manage saved cards'),
          const Divider(),
          _buildSectionHeader(context, 'Preferences'),
          _buildSettingsItem(context, icon: Icons.notifications_none, title: 'Notifications'),
          _buildSettingsItem(context, icon: Icons.security, title: 'Security', subtitle: 'Biometrics & PIN'),
          const Divider(),
          _buildSectionHeader(context, 'About'),
          _buildSettingsItem(context, icon: Icons.info_outline, title: 'App Version', subtitle: '1.0.0 (Phase 4 Foundation)'),
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
        // Mock action for Phase 4
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title settings will be available later.')),
        );
      },
    );
  }
}
