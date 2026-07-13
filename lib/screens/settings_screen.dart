/// Settings screen — app configuration and information.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/feedback_sheet.dart';
import '../config.dart';
import '../widgets/subscribe_sheet.dart';
import '../services/notify_service.dart';
import '../services/local_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: SafeArea(top: false, child: ListView(
        children: [
          // About section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'За приложението',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ListTile(
            leading: Image.asset('assets/icons/app_icon.png', width: 28, height: 28, filterQuality: FilterQuality.medium),
            title: const Text('Количка'),
            subtitle: const Text('Сравни цени на хранителни продукти около теб'),
          ),
          ListTile(
            leading: const Icon(Icons.code, size: 20),
            title: const Text('Версия'),
            subtitle: Text('${Config.appVersion} (${Config.appBuild})'),
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
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
            leading: Icon(Icons.mark_email_read_outlined, size: 22, color: Theme.of(context).colorScheme.primary),
            title: const Text('Седмични оферти по имейл'),
            subtitle: const Text('Получавай най-добрите цени около теб'),
            onTap: () => showSubscribeSheet(context),
          ),
          const _NotifyToggleTile(),
          ListTile(
            leading: const Icon(Icons.star_rate_rounded, size: 24, color: Colors.amber),
            title: const Text('Оцени и сподели мнение'),
            subtitle: const Text('Дай оценка с 5 звезди или докладвай проблем'),
            onTap: () => showRatingSheet(context),
          ),

          const Divider(height: 32),

          // Legal section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              'Правна информация',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, size: 20),
            title: const Text('Поверителност'),
            subtitle: const Text('Политика за поверителност'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _launchUrl('https://kolichka.gotvach.com/privacy.html'),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined, size: 20),
            title: const Text('Условия за ползване'),
            subtitle: const Text('Общи условия'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _launchUrl('https://kolichka.gotvach.com/terms.html'),
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
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      )),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Toggle for the daily favourite-promo push reminders (morning + evening).
class _NotifyToggleTile extends StatefulWidget {
  const _NotifyToggleTile();
  @override
  State<_NotifyToggleTile> createState() => _NotifyToggleTileState();
}

class _NotifyToggleTileState extends State<_NotifyToggleTile> {
  bool _on = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LocalStore.notifyEnabled().then((v) { if (mounted) setState(() => _on = v); });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    try {
      if (v) {
        final ok = await NotifyService.enableDailyReminders();
        if (!mounted) return;
        setState(() => _on = ok);
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Разреши известия от системните настройки, после опитай пак.')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Включено! Ще напомняме сутрин (7:30) и вечер (20:00).')));
        }
      } else {
        await NotifyService.disable();
        if (!mounted) return;
        setState(() => _on = false);
      }
    } catch (_) {
      if (mounted) setState(() => _on = false);
    } finally {
      // Always clear the busy flag so the switch never gets stuck/disabled.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(Icons.notifications_active_outlined, size: 22, color: Theme.of(context).colorScheme.primary),
      title: const Text('Известия за намаления на любими'),
      subtitle: const Text('Напомняне сутрин (7:30) и вечер (20:00)'),
      value: _on,
      onChanged: _busy ? null : _toggle,
    );
  }
}
