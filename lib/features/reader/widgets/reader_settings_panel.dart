import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors.dart';
import '../../../data/settings/app_settings.dart';
import '../../../services/font_service.dart';
import '../model/reader_prefs.dart';

enum PrefsScope { book, global }

/// Panneau de réglages du lecteur. Chaque modification est appliquée en
/// direct via [onChanged] ; la page se recompose derrière le panneau.
class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.prefs,
    required this.onChanged,
    this.scope,
    this.onScopeChanged,
    this.format,
    this.reflowable = true,
  });

  final ReaderPrefs prefs;
  final ValueChanged<ReaderPrefs> onChanged;
  final PrefsScope? scope;
  final ValueChanged<PrefsScope>? onScopeChanged;
  final String? format;
  final bool reflowable;

  static Future<void> show(
    BuildContext context, {
    required ReaderPrefs prefs,
    required ValueChanged<ReaderPrefs> onChanged,
    PrefsScope? scope,
    ValueChanged<PrefsScope>? onScopeChanged,
    String? format,
    bool reflowable = true,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.black.withValues(alpha: 0.08),
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (_) => ReaderSettingsPanel(
          prefs: prefs,
          onChanged: onChanged,
          scope: scope,
          onScopeChanged: onScopeChanged,
          format: format,
          reflowable: reflowable,
        ),
      );

  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  late ReaderPrefs _p = widget.prefs;
  late PrefsScope? _scope = widget.scope;
  int _tab = 0;

  void _set(ReaderPrefs p) {
    setState(() => _p = p);
    widget.onChanged(p);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.reflowable ? const ['Texte', 'Page', 'Fond', 'Gestes'] : const ['Fond', 'Gestes'];
    final index = _tab.clamp(0, tabs.length - 1);
    final tab = tabs[index];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.62),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [for (var i = 0; i < tabs.length; i++) ButtonSegment(value: i, label: Text(tabs[i]))],
                  selected: {index},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.lg),
                children: switch (tab) {
                  'Texte' => _textTab(),
                  'Page' => _pageTab(),
                  'Fond' => _surfaceTab(),
                  _ => _gestureTab(),
                },
              ),
            ),
            if (_scope != null) _scopeBar(),
          ],
        ),
      ),
    );
  }

  Widget _scopeBar() {
    final p = LireoPalette.of(context);
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.divider))),
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.sm, Space.sm),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<PrefsScope>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: PrefsScope.book, label: Text('Ce livre')),
                ButtonSegment(value: PrefsScope.global, label: Text('Tous les livres')),
              ],
              selected: {_scope!},
              onSelectionChanged: (s) {
                setState(() => _scope = s.first);
                widget.onScopeChanged?.call(s.first);
              },
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Profils de lecture',
            icon: const Icon(Icons.bookmarks_outlined),
            onSelected: _profileAction,
            itemBuilder: (_) {
              final profiles = context.read<AppSettings>().profiles;
              return [
                const PopupMenuItem(value: 'save', child: Text('Enregistrer comme profil…')),
                if (profiles.isNotEmpty) const PopupMenuDivider(),
                for (var i = 0; i < profiles.length; i++)
                  PopupMenuItem(
                    value: 'apply:$i',
                    child: Text('${profiles[i].name}${profiles[i].format != null ? ' (${profiles[i].format})' : ''}'),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'reset', child: Text('Réglages par défaut')),
              ];
            },
          ),
        ],
      ),
    );
  }

  Future<void> _profileAction(String action) async {
    final settings = context.read<AppSettings>();
    if (action == 'reset') return _set(const ReaderPrefs());
    if (action.startsWith('apply:')) {
      final profile = settings.profiles[int.parse(action.substring(6))];
      return _set(profile.prefs);
    }
    final name = TextEditingController();
    var forFormat = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Nouveau profil'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(hintText: 'Nom du profil')),
              if (widget.format != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: forFormat,
                  onChanged: (v) => setState(() => forFormat = v ?? false),
                  title: Text('Appliquer aux livres ${widget.format!.toUpperCase()}'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final list = [
      for (final p in settings.profiles)
        if (!(forFormat && p.format == widget.format)) p,
      ReadingProfile(name: name.text.trim(), prefs: _p, format: forFormat ? widget.format : null),
    ];
    await settings.saveProfiles(list);
    AppError.toast('Profil « ${name.text.trim()} » enregistré');
  }

  // ------------------------------------------------------------------ onglets

  List<Widget> _textTab() {
    final fonts = context.watch<FontService>();
    final p = LireoPalette.of(context);
    return [
      _label('Police'),
      SizedBox(
        height: 64,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final MapEntry(key: family, value: label) in fonts.families.entries)
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: ChoiceChip(
                  selected: _p.fontFamily == family,
                  onSelected: (_) => _set(_p.copyWith(fontFamily: family)),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Aa', style: TextStyle(fontFamily: family, fontSize: 18, height: 1.1)),
                      Text(label.split(' (').first, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ActionChip(
              avatar: Icon(Icons.add_rounded, color: p.primary),
              label: const Text('Importer'),
              onPressed: _importFont,
            ),
          ],
        ),
      ),
      _slider('Taille', _p.fontSize, 12, 36, (v) => _p.copyWith(fontSize: v), format: (v) => v.toStringAsFixed(0), divisions: 24),
      _slider('Interligne', _p.lineHeight, 1.0, 2.4, (v) => _p.copyWith(lineHeight: v), format: (v) => v.toStringAsFixed(2), divisions: 28),
      _slider('Espacement des lettres', _p.letterSpacing, -0.5, 2, (v) => _p.copyWith(letterSpacing: v), format: (v) => v.toStringAsFixed(1), divisions: 25),
      _slider('Espacement des paragraphes', _p.paragraphSpacing, 0, 2, (v) => _p.copyWith(paragraphSpacing: v), format: (v) => v.toStringAsFixed(1), divisions: 20),
      _slider('Alinéa', _p.indent, 0, 3, (v) => _p.copyWith(indent: v), format: (v) => v == 0 ? 'aucun' : '${v.toStringAsFixed(1)} em', divisions: 6),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Texte justifié'),
        value: _p.justify,
        onChanged: (v) => _set(_p.copyWith(justify: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Texte plus gras'),
        value: _p.bold,
        onChanged: (v) => _set(_p.copyWith(bold: v)),
      ),
    ];
  }

  Future<void> _importFont() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Importer une police (TTF/OTF)');
    if (file == null || !mounted) return;
    final family = await AppError.guard(() async => context.read<FontService>().importFont(file.name, await file.readAsBytes()));
    if (family != null) _set(_p.copyWith(fontFamily: family));
  }

  List<Widget> _pageTab() => [
        _label('Animation des pages'),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final a in PageAnimation.values)
              ChoiceChip(label: Text(a.label), selected: _p.animation == a, onSelected: (_) => _set(_p.copyWith(animation: a))),
          ],
        ),
        if (_p.animation != PageAnimation.none && _p.animation != PageAnimation.scroll)
          _slider('Vitesse de l\'animation', _p.animationSpeed, 0.5, 2.5, (v) => _p.copyWith(animationSpeed: v),
              format: (v) => '×${v.toStringAsFixed(1)}', divisions: 20),
        if (_p.animation == PageAnimation.curl)
          _slider('Intensité de l\'effet', _p.curlShadow, 0, 1, (v) => _p.copyWith(curlShadow: v), format: (v) => '${(v * 100).round()} %', divisions: 10),
        if (_p.animation == PageAnimation.scroll)
          _slider('Défilement automatique', _p.autoScrollSpeed, 10, 160, (v) => _p.copyWith(autoScrollSpeed: v),
              format: (v) => '${v.round()} px/s', divisions: 30),
        _label('Double page'),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final d in DoublePageMode.values)
              ChoiceChip(label: Text(d.label), selected: _p.doublePage == d, onSelected: (_) => _set(_p.copyWith(doublePage: d))),
          ],
        ),
        const SizedBox(height: Space.sm),
        _slider('Marges latérales', _p.marginH, 8, 80, (v) => _p.copyWith(marginH: v), format: (v) => '${v.round()}', divisions: 36),
        _slider('Marges verticales', _p.marginV, 8, 90, (v) => _p.copyWith(marginV: v), format: (v) => '${v.round()}', divisions: 41),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Afficher la progression en bas de page'),
          subtitle: const Text('Désactivez pour une lecture sans distraction'),
          value: _p.showProgressFooter,
          onChanged: (v) => _set(_p.copyWith(showProgressFooter: v)),
        ),
      ];

  List<Widget> _surfaceTab() {
    final p = LireoPalette.of(context);
    return [
      _label('Fond de lecture'),
      Wrap(
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          for (final s in ReadingSurface.all)
            Semantics(
              button: true,
              selected: _p.surfaceId == s.id && _p.customBackground == null,
              label: s.label,
              child: GestureDetector(
                onTap: () => _set(_p.copyWith(surfaceId: s.id, clearCustomColors: true)),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.background,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _p.surfaceId == s.id && _p.customBackground == null ? p.primary : p.divider,
                          width: _p.surfaceId == s.id && _p.customBackground == null ? 2.5 : 1,
                        ),
                      ),
                      child: Text('Aa', style: TextStyle(color: s.text, fontFamily: _p.fontFamily, fontSize: 17)),
                    ),
                    const SizedBox(height: 4),
                    Text(s.label, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: Space.lg),
      _label('Couleurs personnalisées'),
      Row(
        children: [
          Expanded(child: _colorPicker('Texte', _p.textColor, (c) => _p.copyWith(customText: c.toARGB32(), customBackground: _p.background.toARGB32()))),
          const SizedBox(width: Space.md),
          Expanded(child: _colorPicker('Fond', _p.background, (c) => _p.copyWith(customBackground: c.toARGB32(), customText: _p.textColor.toARGB32()))),
        ],
      ),
    ];
  }

  Widget _colorPicker(String label, Color current, ReaderPrefs Function(Color) apply) {
    const swatches = [
      Color(0xFF000000), Color(0xFF1F1D1A), Color(0xFF3B2A1A), Color(0xFF233021), Color(0xFF2B3440), Color(0xFF6B6B6B),
      Color(0xFFB9B2A6), Color(0xFFDCD3C4), Color(0xFFF0E6D2), Color(0xFFF6F1E7), Color(0xFFFFFFFF), Color(0xFFE6EEF5),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in swatches)
              GestureDetector(
                onTap: () => _set(apply(c)),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.toARGB32() == current.toARGB32() ? LireoPalette.of(context).primary : Colors.black26,
                        width: c.toARGB32() == current.toARGB32() ? 2.5 : 1),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _gestureTab() {
    Widget action(String label, ReaderAction value, ReaderPrefs Function(ReaderAction) apply) => Row(
          children: [
            Expanded(child: Text(label)),
            DropdownButton<ReaderAction>(
              value: value,
              underline: const SizedBox(),
              items: [for (final a in ReaderAction.values) DropdownMenuItem(value: a, child: Text(a.label))],
              onChanged: (v) => v == null ? null : _set(apply(v)),
            ),
          ],
        );
    return [
      _label('Zones de l\'écran'),
      action('Tap à gauche', _p.leftTap, (a) => _p.copyWith(leftTap: a)),
      action('Tap au centre', _p.centerTap, (a) => _p.copyWith(centerTap: a)),
      action('Tap à droite', _p.rightTap, (a) => _p.copyWith(rightTap: a)),
      action('Double tap', _p.doubleTap, (a) => _p.copyWith(doubleTap: a)),
      if (_p.doubleTap != ReaderAction.none)
        Text('Le double tap ajoute un court délai aux taps simples.', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: Space.md),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Glissement vertical : luminosité'),
        value: _p.brightnessSwipe,
        onChanged: (v) => _set(_p.copyWith(brightnessSwipe: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Touches de volume et télécommandes'),
        subtitle: const Text('Volume, flèches, Page suiv./préc., boutons média Bluetooth'),
        value: _p.volumeKeys,
        onChanged: (v) => _set(_p.copyWith(volumeKeys: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Garder l\'écran allumé'),
        value: _p.keepScreenOn,
        onChanged: (v) => _set(_p.copyWith(keepScreenOn: v)),
      ),
    ];
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: Space.sm, bottom: Space.sm),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _slider(String label, double value, double min, double max, ReaderPrefs Function(double) apply,
      {required String Function(double) format, int? divisions}) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Expanded(child: Text(label, style: t.bodyMedium)), Text(format(value), style: t.labelMedium)]),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: format(value),
            onChanged: (v) => setState(() => _p = apply(v)),
            onChangeEnd: (v) => _set(apply(v)),
          ),
        ],
      ),
    );
  }
}
