import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/services.dart';
import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/errors.dart';
import '../../data/settings/app_settings.dart';
import '../../formats/format_registry.dart';
import '../../services/app_lock.dart';
import '../../services/backup_service.dart';
import '../../services/font_service.dart';
import '../../services/reminder_service.dart';
import '../../services/sync/sync_service.dart';
import '../import/import_actions.dart';
import '../reader/model/reader_prefs.dart';
import '../reader/widgets/reader_settings_panel.dart';
import '../security/lock_screen.dart';
import '../security/unlock_dialog.dart';
import '../splash/splash_screen.dart';
import 'sync_screen.dart';
import 'theme_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final p = LireoPalette.of(context);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.sm),
          child: Text(title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.primary, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
        );
    Widget tile(IconData icon, String title, {String? subtitle, VoidCallback? onTap, Widget? trailing}) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded) : null),
          onTap: onTap,
        );
    Widget toggle(IconData icon, String title, bool value, ValueChanged<bool> onChanged, {String? subtitle}) => SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          value: value,
          onChanged: onChanged,
        );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('Paramètres'), backgroundColor: p.background),
          SliverList.list(children: [
            section('Apparence'),
            tile(Icons.palette_outlined, 'Thème', subtitle: s.activeSeason == null ? s.themePreset.label : '${s.activeSeason!.label} (événement)',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ThemeScreen()))),
            toggle(Icons.animation_rounded, 'Animations', s.animationsEnabled, s.setAnimations,
                subtitle: 'Transitions, apparitions, micro-interactions'),
            toggle(Icons.vibration_rounded, 'Retour haptique', s.hapticsEnabled, s.setHaptics),
            toggle(Icons.battery_saver_outlined, 'Économie d\'énergie', s.batterySaver, s.setBatterySaver,
                subtitle: 'Désactive les flous et animations'),

            section('Bibliothèque'),
            ListTile(
              leading: const Icon(Icons.shelves),
              title: const Text('Affichage'),
              trailing: SegmentedButton<LibraryLayout>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: LibraryLayout.shelves, icon: Icon(Icons.shelves, size: 18)),
                  ButtonSegment(value: LibraryLayout.grid, icon: Icon(Icons.grid_view_rounded, size: 18)),
                  ButtonSegment(value: LibraryLayout.list, icon: Icon(Icons.view_list_rounded, size: 18)),
                ],
                selected: {s.libraryLayout},
                onSelectionChanged: (v) => s.setLibraryLayout(v.first),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_size_select_large_rounded),
              title: const Text('Taille des couvertures'),
              subtitle: Slider(value: s.coverScale, min: 0.7, max: 1.4, divisions: 7, onChanged: s.setCoverScale),
            ),
            tile(Icons.add_circle_outline_rounded, 'Ajouter des livres', onTap: () => ImportActions.showImportMenu(context)),
            tile(Icons.folder_open_rounded, 'Parcourir l\'appareil', onTap: () => ImportActions.openFileManager(context)),

            section('Lecture'),
            tile(Icons.text_fields_rounded, 'Réglages de lecture par défaut', subtitle: '${s.readerPrefs.fontFamily}, ${s.readerPrefs.fontSize.round()} pt, ${s.readerPrefs.animation.label}',
                onTap: () => ReaderSettingsPanel.show(context, prefs: s.readerPrefs, onChanged: s.setReaderPrefs)),
            tile(Icons.bookmarks_outlined, 'Profils de lecture', subtitle: s.profiles.isEmpty ? 'Aucun profil' : '${s.profiles.length} profil${s.profiles.length > 1 ? 's' : ''}',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _ProfilesScreen()))),
            tile(Icons.font_download_outlined, 'Polices importées', subtitle: '${context.watch<FontService>().customFamilies.length} police(s)',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _FontsScreen()))),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Objectif quotidien'),
              trailing: DropdownButton<int>(
                value: [10, 15, 20, 30, 45, 60, 90, 120].contains(s.dailyGoalMinutes) ? s.dailyGoalMinutes : null,
                hint: Text('${s.dailyGoalMinutes} min'),
                underline: const SizedBox(),
                items: [for (final m in [10, 15, 20, 30, 45, 60, 90, 120]) DropdownMenuItem(value: m, child: Text('$m min'))],
                onChanged: (v) => v == null ? null : s.setDailyGoal(v),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Rappel de lecture quotidien'),
              subtitle: Text(s.reminderEnabled ? 'Chaque jour à ${s.reminderTime.format(context)}' : 'Désactivé'),
              value: s.reminderEnabled,
              onChanged: (v) => _toggleReminder(context, v),
            ),
            if (s.reminderEnabled)
              ListTile(
                leading: const SizedBox(width: 24),
                title: const Text('Heure du rappel'),
                trailing: Text(s.reminderTime.format(context), style: Theme.of(context).textTheme.titleMedium),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: s.reminderTime);
                  if (t != null) await s.setReminder(time: t);
                },
              ),
            ListTile(
              leading: const Icon(Icons.self_improvement_rounded),
              title: const Text('Rappel de pause'),
              subtitle: const Text('Après une longue période de lecture continue'),
              trailing: DropdownButton<int>(
                value: s.breakReminderMinutes,
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Jamais')),
                  for (final m in [30, 45, 60, 90]) DropdownMenuItem(value: m, child: Text('$m min')),
                ],
                onChanged: (v) => v == null ? null : s.setBreakReminder(v),
              ),
            ),

            section('Confidentialité et sécurité'),
            tile(Icons.pin_outlined, s.hasPin ? 'Modifier le code PIN' : 'Définir un code PIN',
                subtitle: s.hasPin ? 'LIREO se verrouille après 45 s en arrière-plan' : 'Verrouille l\'application et les collections privées',
                onTap: () => _setupPin(context)),
            if (s.hasPin) ...[
              FutureBuilder<bool>(
                future: context.read<AppLock>().biometricsAvailable(),
                builder: (context, snap) => snap.data == true
                    ? toggle(Icons.fingerprint_rounded, 'Déverrouillage biométrique', s.biometricEnabled, (v) async {
                        if (v || await confirmOwner(context, reason: 'Confirmez pour désactiver la biométrie')) await s.setBiometric(v);
                      })
                    : const SizedBox.shrink(),
              ),
              toggle(Icons.visibility_off_outlined, 'Masquer les collections privées', s.hidePrivateCollections, (v) async {
                if (v || await confirmOwner(context, reason: 'Confirmez pour afficher les collections privées')) await s.setHidePrivate(v);
              },
                  subtitle: 'Leurs livres n\'apparaissent pas sans déverrouillage'),
              tile(Icons.lock_reset_rounded, 'Supprimer le code PIN', onTap: () async {
                if (!await confirmOwner(context, reason: 'Saisissez le code actuel pour le supprimer')) return;
                await s.setPin(null);
                AppError.toast('Code PIN supprimé');
              }),
            ],
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('Aucun pistage, aucune publicité'),
              subtitle: Text('Aucune donnée ne quitte l\'appareil, sauf actions explicites (partage, définition, traduction).'),
            ),

            section('Synchronisation et sauvegarde'),
            tile(Icons.cloud_sync_outlined, 'Synchronisation',
                subtitle: switch (context.watch<SyncService>().active) {
                  null => 'Désactivée · Dropbox ou Google Drive',
                  final p => 'Activée · ${p.label}',
                },
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen()))),
            tile(Icons.backup_outlined, 'Exporter une sauvegarde',
                subtitle: 'Progression, annotations, collections, statistiques, réglages (JSON)', onTap: () => _export(context)),
            tile(Icons.settings_backup_restore_rounded, 'Restaurer une sauvegarde',
                subtitle: 'Les livres sont reconnus par empreinte : importez-les d\'abord', onTap: () => _restore(context)),

            section('À propos'),
            tile(Icons.description_outlined, 'Formats pris en charge', subtitle: FormatRegistry.formats.map((f) => f.label).join(', ')),
            tile(Icons.bug_report_outlined, 'Journal des erreurs', subtitle: '${AppError.recent.length} entrée(s)', onTap: () => _showLog(context)),
            tile(Icons.gavel_outlined, 'Licences', onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'LIREO',
                  applicationIcon: Padding(padding: const EdgeInsets.all(8), child: LireoMark(size: 40, color: p.primary)),
                  applicationLegalese: 'Polices : Inter, Lora, Literata, Merriweather, Atkinson Hyperlegible — SIL Open Font License 1.1.',
                )),
            const SizedBox(height: 130),
          ]),
        ],
      ),
    );
  }

  Future<void> _toggleReminder(BuildContext context, bool enable) async {
    final settings = context.read<AppSettings>();
    if (!enable) return settings.setReminder(enabled: false);
    if (!ReminderService.supported) {
      AppError.toast('Rappels indisponibles sur cette plateforme');
      return;
    }
    final granted = await context.read<AppServices>().observers.reminders.requestPermission();
    if (!granted) {
      AppError.toast('Autorisez les notifications de LIREO pour recevoir le rappel');
      return;
    }
    await settings.setReminder(enabled: true);
    AppError.toast('Rappel programmé à ${settings.reminderTime.hour}h${settings.reminderTime.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _setupPin(BuildContext context) async {
    if (context.read<AppSettings>().hasPin && !await confirmOwner(context, reason: 'Saisissez le code actuel pour le modifier')) return;
    if (!context.mounted) return;
    final pin = await Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _PinSetupPage()));
    if (pin == null || !context.mounted) return;
    await context.read<AppSettings>().setPin(pin);
    AppError.toast('Code PIN enregistré');
  }

  Future<void> _export(BuildContext context) async {
    final services = context.read<AppServices>();
    await AppError.guard(() async {
      final json = await BackupService(services.database.db, services.settings).export();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(Uint8List.fromList(utf8.encode(json)), mimeType: 'application/json', name: 'lireo-sauvegarde-$date.json')],
        fileNameOverrides: ['lireo-sauvegarde-$date.json'],
        subject: 'Sauvegarde LIREO',
      ));
    }, context: 'backup');
  }

  Future<void> _restore(BuildContext context) async {
    final services = context.read<AppServices>();
    if (!await confirmOwner(context, reason: 'Confirmez pour restaurer une sauvegarde')) return;
    final file = await FilePicker.pickFile(dialogTitle: 'Choisir une sauvegarde LIREO');
    if (file == null) return;
    final matched = await AppError.guard(() async {
      final json = utf8.decode(await file.readAsBytes());
      return BackupService(services.database.db, services.settings).restore(json);
    }, context: 'restore');
    if (matched == null) return;
    services.library.notifyChanged();
    AppError.toast('Sauvegarde restaurée ($matched livre${matched > 1 ? 's' : ''} retrouvé${matched > 1 ? 's' : ''})');
  }

  void _showLog(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Journal des erreurs'),
          content: SizedBox(
            width: double.maxFinite,
            child: AppError.recent.isEmpty
                ? const Text('Aucune erreur enregistrée pendant cette session.')
                : ListView(shrinkWrap: true, children: [for (final l in AppError.recent.reversed) Text(l, style: const TextStyle(fontSize: 12))]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
        ),
      );
}

class _PinSetupPage extends StatefulWidget {
  const _PinSetupPage();

  @override
  State<_PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<_PinSetupPage> {
  String _pin = '';
  String? _first;
  bool _error = false;

  void _submit() {
    if (_pin.length < 4) {
      setState(() => _error = true);
      return;
    }
    if (_first == null) {
      setState(() {
        _first = _pin;
        _pin = '';
        _error = false;
      });
    } else if (_first == _pin) {
      Navigator.pop(context, _pin);
    } else {
      setState(() {
        _first = null;
        _pin = '';
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: PinPad(
        title: _first == null ? 'Nouveau code PIN' : 'Confirmez le code',
        subtitle: _error ? 'Les codes ne correspondent pas (4 à 8 chiffres)' : '4 à 8 chiffres, puis validez',
        error: _error,
        length: _pin.length,
        onDigit: (d) => setState(() {
          if (_pin.length < 8) _pin += d;
          _error = false;
        }),
        onDelete: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
        onSubmit: _submit,
      ),
    );
  }
}

class _ProfilesScreen extends StatelessWidget {
  const _ProfilesScreen();

  Future<void> _import(BuildContext context) async {
    final file = await FilePicker.pickFile(dialogTitle: 'Importer des profils (JSON)');
    if (file == null || !context.mounted) return;
    final settings = context.read<AppSettings>();
    await AppError.guard(() async {
      final data = jsonDecode(utf8.decode(await file.readAsBytes()));
      final list = (data is List ? data : [data]).cast<Map>();
      final imported = [for (final m in list) ReadingProfile.fromJson(Map<String, dynamic>.from(m))];
      await settings.saveProfiles([...settings.profiles, ...imported]);
      AppError.toast('${imported.length} profil(s) importé(s)');
    }, context: 'profiles');
  }

  Future<void> _export(List<ReadingProfile> profiles) => AppError.guard(() => SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert([for (final p in profiles) p.toJson()]))),
            mimeType: 'application/json',
            name: 'lireo-profils.json',
          ),
        ],
        fileNameOverrides: ['lireo-profils.json'],
      )));

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final profiles = settings.profiles;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profils de lecture'),
        actions: [
          IconButton(tooltip: 'Importer', icon: const Icon(Icons.file_download_outlined), onPressed: () => _import(context)),
          IconButton(tooltip: 'Exporter', icon: const Icon(Icons.ios_share_rounded), onPressed: profiles.isEmpty ? null : () => _export(profiles)),
        ],
      ),
      body: profiles.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: Text('Créez un profil depuis le lecteur : Aa › icône profils › « Enregistrer comme profil ». '
                  'Un profil peut s\'appliquer automatiquement à un format (ex. PDF, TXT).'),
            )
          : ListView(children: [
              for (var i = 0; i < profiles.length; i++)
                ListTile(
                  leading: Text('Aa', style: TextStyle(fontFamily: profiles[i].prefs.fontFamily, fontSize: 22)),
                  title: Text(profiles[i].name),
                  subtitle: Text([
                    '${profiles[i].prefs.fontFamily} ${profiles[i].prefs.fontSize.round()} pt',
                    profiles[i].prefs.surface.label,
                    if (profiles[i].format != null) 'auto : ${profiles[i].format!.toUpperCase()}',
                  ].join(' · ')),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      final list = [...profiles];
                      if (v == 'default') {
                        settings.setReaderPrefs(profiles[i].prefs);
                        AppError.toast('Profil appliqué par défaut');
                      } else {
                        list.removeAt(i);
                        settings.saveProfiles(list);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'default', child: Text('Utiliser par défaut')),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
                ),
            ]),
    );
  }
}

class _FontsScreen extends StatelessWidget {
  const _FontsScreen();

  @override
  Widget build(BuildContext context) {
    final fonts = context.watch<FontService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Polices')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final file = await FilePicker.pickFile(dialogTitle: 'Importer une police (TTF/OTF)');
          if (file == null || !context.mounted) return;
          await AppError.guard(() async => fonts.importFont(file.name, await file.readAsBytes()));
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Importer'),
      ),
      body: ListView(children: [
        for (final MapEntry(key: family, value: label) in fonts.families.entries)
          ListTile(
            title: Text(label),
            subtitle: Text('Portez-vous bien, lecteur curieux.', style: TextStyle(fontFamily: family, fontSize: 17)),
            trailing: fonts.customFamilies.contains(family)
                ? IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () => fonts.removeFont(family))
                : null,
          ),
      ]),
    );
  }
}
