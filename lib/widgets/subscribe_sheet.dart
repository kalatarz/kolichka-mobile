/// Weekly-offers email subscription sheet. Posts to /api/subscribe; the server
/// emails a confirmation link (double opt-in). Uses the saved location so the
/// offers are localized.
library;

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/analytics.dart';
import '../services/local_store.dart';

Future<void> showSubscribeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (_) => const _SubscribeSheet(),
  );
}

class _SubscribeSheet extends StatefulWidget {
  const _SubscribeSheet();

  @override
  State<_SubscribeSheet> createState() => _SubscribeSheetState();
}

class _SubscribeSheetState extends State<_SubscribeSheet> {
  final ApiService _api = ApiService();
  final LocationService _location = LocationService();
  final TextEditingController _email = TextEditingController();
  bool _submitting = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _api.close();
    super.dispose();
  }

  bool _validEmail(String e) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e);

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!_validEmail(email)) {
      setState(() => _error = 'Въведи валиден имейл адрес');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final pos = await _location.getLastPosition();
      await _api.subscribe(email: email, lat: pos?.latitude, lng: pos?.longitude);
      Analytics.instance.track('subscribe_email', {});
      await LocalStore.setSubscribeDone(); // stop the browsing nudge from re-appearing
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _done = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Възникна грешка. Опитай отново.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: _done ? _buildDone(textColor) : _buildForm(textColor),
      ),
    );
  }

  Widget _buildDone(Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Icon(Icons.mark_email_read, size: 44, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text('Провери имейла си за потвърждение.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Готово'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text('Седмични оферти по имейл',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textColor)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('Най-добрите цени около теб, веднъж седмично.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'имейл адрес',
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _error,
            prefixIcon: const Icon(Icons.email_outlined),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _submitting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Абонирай се'),
          ),
        ),
      ],
    );
  }
}
