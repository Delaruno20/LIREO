import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../data/settings/app_settings.dart';
import '../../services/app_lock.dart';
import '../splash/splash_screen.dart';

/// Écran de verrouillage par code PIN (avec biométrie si activée).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    if (!mounted || !context.read<AppSettings>().biometricEnabled) return;
    await context.read<AppLock>().unlockWithBiometrics();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LireoPalette.of(context).background,
      child: SafeArea(
        child: PinPrompt(
          title: 'LIREO est verrouillé',
          prompt: 'Saisissez votre code PIN',
          unlock: true,
          onAccepted: () {},
          onBiometric: context.watch<AppSettings>().biometricEnabled ? _tryBiometric : null,
        ),
      ),
    );
  }
}

/// Saisie d'un PIN existant, avec temporisation après plusieurs codes faux
/// (voir [AppLock.lockoutFor]). Utilisée par l'écran de verrouillage, l'accès
/// aux collections privées et la confirmation d'actions sensibles.
class PinPrompt extends StatefulWidget {
  const PinPrompt({
    super.key,
    required this.title,
    required this.prompt,
    required this.onAccepted,
    this.unlock = false,
    this.onBiometric,
  });

  final String title;
  final String prompt;
  final VoidCallback onAccepted;

  /// Déverrouille l'application en cas de succès (sinon simple vérification).
  final bool unlock;
  final VoidCallback? onBiometric;

  @override
  State<PinPrompt> createState() => _PinPromptState();
}

class _PinPromptState extends State<PinPrompt> {
  String _pin = '';
  bool _error = false;
  bool _tooShort = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (context.read<AppLock>().lockoutRemaining > Duration.zero) _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (context.read<AppLock>().lockoutRemaining == Duration.zero) t.cancel();
      setState(() {});
    });
  }

  void _attempt() {
    final lock = context.read<AppLock>();
    final result = widget.unlock ? lock.unlockWithPin(_pin) : lock.checkPin(_pin);
    if (result == PinCheck.ok) return widget.onAccepted();
    setState(() {
      _pin = '';
      _error = true;
    });
    if (lock.lockoutRemaining > Duration.zero) _startTicker();
  }

  void _press(String digit) {
    if (_pin.length >= 8) return;
    setState(() {
      _pin += digit;
      _error = false;
      _tooShort = false;
    });
    if (context.read<AppLock>().isFullLength(_pin) || _pin.length == 8) _attempt();
  }

  void _submit() {
    if (_pin.length < 4) return setState(() => _tooShort = true);
    _attempt();
  }

  String _subtitle(Duration wait) {
    if (wait > Duration.zero) {
      final s = wait.inSeconds + 1;
      return 'Trop de codes faux. Réessayez dans ${s >= 60 ? '${(s / 60).ceil()} min' : '$s s'}';
    }
    if (_tooShort) return 'Le code compte au moins 4 chiffres';
    if (!_error) return widget.prompt;
    final left = AppLock.freeAttempts - context.read<AppSettings>().pinFailures;
    return left > 0 && left <= 2 ? 'Code incorrect · $left essai${left > 1 ? 's' : ''} avant attente' : 'Code incorrect, réessayez';
  }

  @override
  Widget build(BuildContext context) {
    final wait = context.read<AppLock>().lockoutRemaining;
    final blocked = wait > Duration.zero;
    return PinPad(
      title: widget.title,
      subtitle: _subtitle(wait),
      error: _error || _tooShort || blocked,
      length: _pin.length,
      onDigit: blocked ? (_) {} : _press,
      onDelete: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
      onSubmit: blocked ? () {} : _submit,
      onBiometric: widget.onBiometric,
    );
  }
}

/// Pavé numérique réutilisé pour la saisie et la création du PIN.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.subtitle,
    required this.length,
    required this.onDigit,
    required this.onDelete,
    required this.onSubmit,
    this.onBiometric,
    this.error = false,
  });

  final String title;
  final String subtitle;
  final int length;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onSubmit;
  final VoidCallback? onBiometric;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: icon == null ? p.surface : Colors.transparent,
              border: icon == null ? Border.all(color: p.divider) : null,
            ),
            child: icon != null ? Icon(icon, color: p.text) : Text(label, style: t.headlineMedium?.copyWith(fontFamily: Fonts.ui)),
          ),
        );

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LireoMark(size: 48, color: p.primary),
            const SizedBox(height: Space.lg),
            Text(title, style: t.headlineSmall),
            const SizedBox(height: Space.sm),
            Text(subtitle, style: t.bodyMedium?.copyWith(color: error ? Theme.of(context).colorScheme.error : p.textMuted)),
            const SizedBox(height: Space.xl),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < (length < 4 ? 4 : length); i++)
                  AnimatedContainer(
                    duration: Motion.scaled(context, Motion.fast),
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < length ? p.primary : Colors.transparent,
                      border: Border.all(color: error ? Theme.of(context).colorScheme.error : p.primary, width: 1.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.xxl),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: Space.lg),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in row) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: key(d, onTap: () => onDigit(d))),
                  ],
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: key('Effacer', icon: Icons.backspace_outlined, onTap: onDelete)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: key('0', onTap: () => onDigit('0'))),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: key('Valider', icon: Icons.check_rounded, onTap: onSubmit)),
              ],
            ),
            if (onBiometric != null) ...[
              const SizedBox(height: Space.md),
              TextButton.icon(
                onPressed: onBiometric,
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Utiliser la biométrie'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
