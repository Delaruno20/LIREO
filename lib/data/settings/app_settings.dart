import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design/palette.dart';
import '../../core/design/seasonal.dart';
import '../../features/reader/model/reader_prefs.dart';

enum LibraryLayout { shelves, grid, list }

/// Préférences globales de l'application, persistées localement.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _load();
  }

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  late ThemePreset themePreset;

  /// Bascule automatique vers le thème de l'événement en cours.
  late bool seasonalAuto;

  /// Thème événementiel choisi à la main (prioritaire sur tout le reste).
  SeasonalEvent? seasonForced;
  SeasonalEvent? _seasonToday;
  late Color customAccent;
  late Color customBackground;
  late bool customDark;
  late bool animationsEnabled;
  late bool hapticsEnabled;
  late LibraryLayout libraryLayout;
  late double coverScale;
  late bool onboardingDone;
  late int dailyGoalMinutes;
  late ReaderPrefs readerPrefs;
  late List<ReadingProfile> profiles;
  late bool biometricEnabled;
  late bool hidePrivateCollections;
  late bool batterySaver;
  late int breakReminderMinutes;
  late double ttsRate;
  late double ttsPitch;
  String? ttsVoice;
  late bool reminderEnabled;

  /// Heure du rappel, en minutes depuis minuit.
  late int reminderMinutes;
  String? _pinHash;

  bool get hasPin => _pinHash != null;

  void _load() {
    themePreset = ThemePreset.values.firstWhere(
      (t) => t.name == _prefs.getString('theme'),
      orElse: () => ThemePreset.warmLibrary,
    );
    seasonalAuto = _prefs.getBool('seasonalAuto') ?? true;
    seasonForced = SeasonalEvent.values.where((e) => e.name == _prefs.getString('seasonForced')).firstOrNull;
    _seasonToday = SeasonalEvent.activeOn(_clock());
    customAccent = Color(_prefs.getInt('customAccent') ?? 0xFFA0683A);
    customBackground = Color(_prefs.getInt('customBackground') ?? 0xFFF3ECE1);
    customDark = _prefs.getBool('customDark') ?? false;
    animationsEnabled = _prefs.getBool('animations') ?? true;
    hapticsEnabled = _prefs.getBool('haptics') ?? true;
    libraryLayout = LibraryLayout.values.firstWhere(
      (l) => l.name == _prefs.getString('libraryLayout'),
      orElse: () => LibraryLayout.shelves,
    );
    coverScale = _prefs.getDouble('coverScale') ?? 1.0;
    onboardingDone = _prefs.getBool('onboardingDone') ?? false;
    dailyGoalMinutes = _prefs.getInt('dailyGoal') ?? 20;
    readerPrefs = ReaderPrefs.decode(_prefs.getString('readerPrefs'));
    profiles = (_prefs.getStringList('profiles') ?? const [])
        .map((s) {
          try {
            return ReadingProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<ReadingProfile>()
        .toList();
    biometricEnabled = _prefs.getBool('biometric') ?? false;
    hidePrivateCollections = _prefs.getBool('hidePrivate') ?? true;
    batterySaver = _prefs.getBool('batterySaver') ?? false;
    breakReminderMinutes = _prefs.getInt('breakReminder') ?? 0;
    ttsRate = _prefs.getDouble('ttsRate') ?? 0.5;
    ttsPitch = _prefs.getDouble('ttsPitch') ?? 1.0;
    ttsVoice = _prefs.getString('ttsVoice');
    reminderEnabled = _prefs.getBool('reminderEnabled') ?? false;
    reminderMinutes = _prefs.getInt('reminderMinutes') ?? 21 * 60;
    _pinHash = _prefs.getString('pinHash');
  }

  TimeOfDay get reminderTime => TimeOfDay(hour: reminderMinutes ~/ 60, minute: reminderMinutes % 60);

  Future<void> setReminder({bool? enabled, TimeOfDay? time}) async {
    reminderEnabled = enabled ?? reminderEnabled;
    if (time != null) reminderMinutes = time.hour * 60 + time.minute;
    notifyListeners();
    await _prefs.setBool('reminderEnabled', reminderEnabled);
    await _prefs.setInt('reminderMinutes', reminderMinutes);
  }

  Future<void> setTts({double? rate, double? pitch, String? voice}) async {
    ttsRate = rate ?? ttsRate;
    ttsPitch = pitch ?? ttsPitch;
    ttsVoice = voice ?? ttsVoice;
    notifyListeners();
    await _prefs.setDouble('ttsRate', ttsRate);
    await _prefs.setDouble('ttsPitch', ttsPitch);
    if (ttsVoice != null) await _prefs.setString('ttsVoice', ttsVoice!);
  }

  /// Événement en cours aujourd'hui (indépendamment de l'option automatique).
  SeasonalEvent? get seasonToday => _seasonToday;

  /// Thème événementiel effectivement appliqué, ou `null`.
  SeasonalEvent? get activeSeason => seasonForced ?? (seasonalAuto ? _seasonToday : null);

  LireoPalette get palette {
    final season = activeSeason;
    if (season != null) return season.palette;
    return themePreset == ThemePreset.custom
        ? LireoPalette.custom(accent: customAccent, background: customBackground, dark: customDark)
        : LireoPalette.forPreset(themePreset);
  }

  /// Recalcule l'événement du jour (au retour dans l'app, à minuit).
  void refreshSeason() {
    final today = SeasonalEvent.activeOn(_clock());
    if (today == _seasonToday) return;
    _seasonToday = today;
    notifyListeners();
  }

  Future<void> setSeasonalAuto(bool v) async {
    seasonalAuto = v;
    notifyListeners();
    await _prefs.setBool('seasonalAuto', v);
  }

  /// Force un thème événementiel (`null` : revenir au comportement normal).
  Future<void> forceSeason(SeasonalEvent? e) async {
    seasonForced = e;
    notifyListeners();
    if (e == null) {
      await _prefs.remove('seasonForced');
    } else {
      await _prefs.setString('seasonForced', e.name);
    }
  }

  /// Animations effectives : désactivées aussi en mode économie d'énergie.
  bool get effectiveAnimations => animationsEnabled && !batterySaver;

  Future<void> setTheme(ThemePreset t) async {
    themePreset = t;
    seasonForced = null;
    notifyListeners();
    await _prefs.remove('seasonForced');
    await _prefs.setString('theme', t.name);
  }

  Future<void> setCustomTheme({Color? accent, Color? background, bool? dark}) async {
    customAccent = accent ?? customAccent;
    customBackground = background ?? customBackground;
    customDark = dark ?? customDark;
    themePreset = ThemePreset.custom;
    seasonForced = null;
    notifyListeners();
    await _prefs.remove('seasonForced');
    await _prefs.setInt('customAccent', customAccent.toARGB32());
    await _prefs.setInt('customBackground', customBackground.toARGB32());
    await _prefs.setBool('customDark', customDark);
    await _prefs.setString('theme', themePreset.name);
  }

  Future<void> setAnimations(bool v) async {
    animationsEnabled = v;
    notifyListeners();
    await _prefs.setBool('animations', v);
  }

  Future<void> setHaptics(bool v) async {
    hapticsEnabled = v;
    notifyListeners();
    await _prefs.setBool('haptics', v);
  }

  Future<void> setLibraryLayout(LibraryLayout v) async {
    libraryLayout = v;
    notifyListeners();
    await _prefs.setString('libraryLayout', v.name);
  }

  Future<void> setCoverScale(double v) async {
    coverScale = v;
    notifyListeners();
    await _prefs.setDouble('coverScale', v);
  }

  Future<void> completeOnboarding() async {
    onboardingDone = true;
    notifyListeners();
    await _prefs.setBool('onboardingDone', true);
  }

  Future<void> setDailyGoal(int minutes) async {
    dailyGoalMinutes = minutes;
    notifyListeners();
    await _prefs.setInt('dailyGoal', minutes);
  }

  /// Date de dernière modification des réglages synchronisés.
  int get syncedSettingsUpdatedAt => _prefs.getInt('settingsUpdatedAt') ?? 0;
  Future<void> _touchSynced() => _prefs.setInt('settingsUpdatedAt', DateTime.now().millisecondsSinceEpoch);

  /// Applique des réglages reçus d'un autre appareil (sans changer leur date).
  Future<void> applySyncedSettings(ReaderPrefs prefs, List<ReadingProfile> list, int updatedAt) async {
    readerPrefs = prefs;
    profiles = List.unmodifiable(list);
    notifyListeners();
    await _prefs.setString('readerPrefs', prefs.encode());
    await _prefs.setStringList('profiles', list.map((p) => jsonEncode(p.toJson())).toList());
    await _prefs.setInt('settingsUpdatedAt', updatedAt);
  }

  Future<void> setReaderPrefs(ReaderPrefs p) async {
    readerPrefs = p;
    notifyListeners();
    await _touchSynced();
    await _prefs.setString('readerPrefs', p.encode());
  }

  Future<void> saveProfiles(List<ReadingProfile> list) async {
    profiles = List.unmodifiable(list);
    notifyListeners();
    await _touchSynced();
    await _prefs.setStringList('profiles', list.map((p) => jsonEncode(p.toJson())).toList());
  }

  ReadingProfile? profileForFormat(String format) {
    for (final p in profiles) {
      if (p.format == format) return p;
    }
    return null;
  }

  Future<void> setBiometric(bool v) async {
    biometricEnabled = v;
    notifyListeners();
    await _prefs.setBool('biometric', v);
  }

  Future<void> setHidePrivate(bool v) async {
    hidePrivateCollections = v;
    notifyListeners();
    await _prefs.setBool('hidePrivate', v);
  }

  Future<void> setBatterySaver(bool v) async {
    batterySaver = v;
    notifyListeners();
    await _prefs.setBool('batterySaver', v);
  }

  Future<void> setBreakReminder(int minutes) async {
    breakReminderMinutes = minutes;
    notifyListeners();
    await _prefs.setInt('breakReminder', minutes);
  }

  // ----------------------------------------------------------------- PIN

  static String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String? pin) async {
    if (pin == null) {
      _pinHash = null;
      biometricEnabled = false;
      await _prefs.remove('pinHash');
      await _prefs.remove('pinSalt');
      await _prefs.remove('pinLength');
      await _prefs.setBool('biometric', false);
    } else {
      final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      _pinHash = _hash(pin, salt);
      await _prefs.setString('pinSalt', salt);
      await _prefs.setString('pinHash', _pinHash!);
      await _prefs.setInt('pinLength', pin.length);
    }
    await recordPinFailures(0, null);
    notifyListeners();
  }

  bool verifyPin(String pin) {
    final salt = _prefs.getString('pinSalt');
    if (_pinHash == null || salt == null) return false;
    final ok = _hash(pin, salt) == _pinHash;
    // PIN créé avant l'enregistrement de sa longueur : on l'apprend ici.
    if (ok && pinLength == null) _prefs.setInt('pinLength', pin.length);
    return ok;
  }

  /// Longueur du PIN : permet la validation automatique au dernier chiffre
  /// sans tester chaque préfixe (ce qui contournerait la temporisation).
  int? get pinLength => _prefs.getInt('pinLength');

  /// Codes faux consécutifs et fin de la temporisation en cours ; persistés
  /// pour qu'un redémarrage de l'app ne remette pas le compteur à zéro.
  int get pinFailures => _prefs.getInt('pinFailures') ?? 0;

  DateTime? get pinLockoutUntil {
    final ms = _prefs.getInt('pinLockoutUntil');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Les deux écritures partent ensemble : le cache est à jour dès le retour
  /// de l'appel, même si l'appelant n'attend pas le Future.
  Future<void> recordPinFailures(int failures, DateTime? lockoutUntil) => Future.wait([
        _prefs.setInt('pinFailures', failures),
        lockoutUntil == null ? _prefs.remove('pinLockoutUntil') : _prefs.setInt('pinLockoutUntil', lockoutUntil.millisecondsSinceEpoch),
      ]);
}
