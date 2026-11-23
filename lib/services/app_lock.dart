import 'dart:io';

import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../core/errors.dart';
import '../data/settings/app_settings.dart';

enum PinCheck { ok, wrong, lockedOut }

/// Verrouillage de l'application (PIN + biométrie) et accès aux
/// collections privées.
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock(this._settings, {DateTime Function()? clock, bool observeLifecycle = true}) : _now = clock ?? DateTime.now {
    _locked = _settings.hasPin;
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  final AppSettings _settings;
  final DateTime Function() _now;
  final _auth = LocalAuthentication();
  bool _locked = false;
  bool _privateUnlocked = false;
  DateTime? _pausedAt;

  /// Délai en arrière-plan avant reverrouillage.
  static const relockAfter = Duration(seconds: 45);

  bool get locked => _locked && _settings.hasPin;
  bool get privateUnlocked => _privateUnlocked || !_settings.hasPin;

  Future<bool> biometricsAvailable() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Codes faux tolérés avant la première temporisation.
  static const freeAttempts = 5;

  /// Temporisation après [failures] codes faux : 30 s au 5e, puis doublée
  /// à chaque nouvel échec, plafonnée à 15 min.
  static Duration lockoutFor(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final seconds = 30 << (failures - freeAttempts).clamp(0, 5);
    return Duration(seconds: seconds.clamp(30, 15 * 60));
  }

  /// Temps restant avant de pouvoir ressaisir un code (zéro sinon).
  Duration get lockoutRemaining {
    final until = _settings.pinLockoutUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Vérifie le PIN sans déverrouiller ; compte les échecs.
  PinCheck checkPin(String pin) {
    if (lockoutRemaining > Duration.zero) return PinCheck.lockedOut;
    if (_settings.verifyPin(pin)) {
      if (_settings.pinFailures > 0) _settings.recordPinFailures(0, null);
      return PinCheck.ok;
    }
    final failures = _settings.pinFailures + 1;
    final wait = lockoutFor(failures);
    _settings.recordPinFailures(failures, wait == Duration.zero ? null : _now().add(wait));
    notifyListeners();
    return PinCheck.wrong;
  }

  /// La saisie [pin] est-elle complète (validation automatique) ?
  bool isFullLength(String pin) => _settings.pinLength != null && pin.length == _settings.pinLength;

  PinCheck unlockWithPin(String pin) {
    final r = checkPin(pin);
    if (r == PinCheck.ok) _unlock();
    return r;
  }

  /// Demande la biométrie du système, sans changer l'état du verrou.
  Future<bool> verifyBiometrics(String reason) async {
    if (!_settings.biometricEnabled) return false;
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (e, st) {
      AppError.report(e, st, context: 'biometric');
      return false;
    }
  }

  Future<bool> unlockWithBiometrics({String reason = 'Déverrouiller LIREO'}) async {
    final ok = await verifyBiometrics(reason);
    if (ok) _unlock();
    return ok;
  }

  void _unlock() {
    _locked = false;
    _privateUnlocked = true;
    notifyListeners();
  }

  void lockPrivate() {
    _privateUnlocked = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _pausedAt != null) {
      if (_settings.hasPin && DateTime.now().difference(_pausedAt!) > relockAfter) {
        _locked = true;
        _privateUnlocked = false;
        notifyListeners();
      }
      _pausedAt = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
