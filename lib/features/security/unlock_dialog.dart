import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/settings/app_settings.dart';
import '../../services/app_lock.dart';
import 'lock_screen.dart';

/// Demande le PIN (ou la biométrie) pour accéder au contenu privé.
/// Sans PIN configuré, propose d'en créer un dans les paramètres.
Future<bool> showUnlockDialog(BuildContext context) async {
  final settings = context.read<AppSettings>();
  final lock = context.read<AppLock>();
  if (!settings.hasPin) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code PIN requis'),
        content: const Text('Définissez un code PIN dans Paramètres › Sécurité pour protéger vos collections privées.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Compris'))],
      ),
    );
    return lock.privateUnlocked;
  }
  if (settings.biometricEnabled && await lock.unlockWithBiometrics(reason: 'Accéder aux collections privées')) return true;
  if (!context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => Scaffold(
      appBar: AppBar(),
      body: PinPrompt(title: 'Contenu privé', prompt: 'Saisissez votre code PIN', unlock: true, onAccepted: () => Navigator.pop(ctx, true)),
    ),
  ));
  return ok ?? false;
}

/// Fait prouver au propriétaire qu'il l'est (biométrie si activée, sinon PIN)
/// avant une action sensible. Sans PIN configuré, il n'y a rien à protéger.
Future<bool> confirmOwner(BuildContext context, {required String reason}) async {
  final settings = context.read<AppSettings>();
  final lock = context.read<AppLock>();
  if (!settings.hasPin) return true;
  if (settings.biometricEnabled && await lock.verifyBiometrics(reason)) return true;
  if (!context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => Scaffold(
      appBar: AppBar(),
      body: PinPrompt(
        title: 'Confirmez votre identité',
        prompt: reason,
        onAccepted: () => Navigator.pop(ctx, true),
        onBiometric: settings.biometricEnabled
            ? () async {
                if (await lock.verifyBiometrics(reason) && ctx.mounted) Navigator.pop(ctx, true);
              }
            : null,
      ),
    ),
  ));
  return ok ?? false;
}

