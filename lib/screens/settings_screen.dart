/// Settings screen — app configuration and information.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_theme.dart';
import '../widgets/feedback_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        children: [
          // About section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'За приложението',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mutedText),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart, size: 24, color: AppTheme.primaryGreen),
            title: const Text('Количка'),
            subtitle: const Text('Сравни цени на хранителни продукти около теб'),
          ),
          ListTile(
            leading: const Icon(Icons.code, size: 20),
            title: const Text('Версия'),
            subtitle: const Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, size: 20),
            title: const Text('Отворен код'),
            subtitle: const Text('GPLv3 лиценз'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _launchUrl('https://github.com/kalatarz/kolichka-mobile'),
          ),

          const Divider(height: 32),

          // Links section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              'Връзки',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mutedText),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language, size: 20),
            title: const Text('Уеб версия'),
            subtitle: const Text('Отвори в браузър'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _launchUrl('https://kolichka.gotvach.com'),
          ),
          ListTile(
            leading: const Icon(Icons.star_rate_rounded, size: 24, color: AppTheme.warnAmber),
            title: const Text('Оцени приложението'),
            subtitle: const Text('Дай оценка с 5 звезди'),
            onTap: () => showRatingSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.feedback_outlined, size: 20),
            title: const Text('Обратна връзка'),
            subtitle: const Text('Сподели мнение или докладвай проблем'),
            onTap: () => showRatingSheet(context),
          ),

          const Divider(height: 32),

          // Legal section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              'Правна информация',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mutedText),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, size: 20),
            title: const Text('Поверителност'),
            subtitle: const Text('Политика за поверителност'),
            onTap: () => _launchUrl('mailto:privacy@gotvach.com'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined, size: 20),
            title: const Text('Лиценз'),
            subtitle: const Text('GNU General Public License v3.0'),
          ),

          const SizedBox(height: 24),

          // Powered by footer
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Данните се предоставят от Количка (kolichka.gotvach.com). Цените са информативни.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppTheme.mutedText),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
