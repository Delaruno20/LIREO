import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/design/palette.dart';
import '../../core/design/seasonal.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../data/settings/app_settings.dart';
import '../onboarding/onboarding_screen.dart';

/// Galerie de thèmes + éditeur du thème personnalisé.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  static const _accents = [
    Color(0xFFA0683A), Color(0xFFD9A55B), Color(0xFF8B3A3A), Color(0xFF5E7552),
    Color(0xFF3F6E8C), Color(0xFF6B4E8A), Color(0xFFC0705A), Color(0xFF4E5257),
  ];
  static const _backgrounds = [
    (Color(0xFFF6EFE4), false), (Color(0xFFFBF8F1), false), (Color(0xFFEEF1E8), false), (Color(0xFFEDEFF3), false),
    (Color(0xFF080808), true), (Color(0xFF16181D), true), (Color(0xFF1B1A17), true), (Color(0xFF132019), true),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Thèmes')),
      body: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          Text('Galerie', style: t.titleLarge),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.md,
            children: [
              for (final preset in ThemePreset.values.where((t) => t != ThemePreset.custom))
                ThemeSwatch(preset: preset, selected: settings.seasonForced == null && settings.themePreset == preset, onTap: () => settings.setTheme(preset)),
              ThemeSwatch(
                preset: ThemePreset.custom,
                palette: LireoPalette.custom(accent: settings.customAccent, background: settings.customBackground, dark: settings.customDark),
                selected: settings.seasonForced == null && settings.themePreset == ThemePreset.custom,
                onTap: () => settings.setTheme(ThemePreset.custom),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Text('Thèmes événementiels', style: t.titleLarge),
          const SizedBox(height: Space.sm),
          Container(
            decoration: BoxDecoration(color: p.surface, borderRadius: const BorderRadius.all(Radii.lg), border: Border.all(color: p.divider)),
            child: SwitchListTile(
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.lg)),
              title: const Text('Changer automatiquement'),
              subtitle: Text(
                settings.seasonToday == null
                    ? 'Le thème de l\'événement s\'applique pendant sa période, puis votre thème revient.'
                    : 'En ce moment : ${settings.seasonToday!.label} ${settings.seasonToday!.emoji}',
                style: t.bodySmall,
              ),
              value: settings.seasonalAuto,
              onChanged: settings.setSeasonalAuto,
            ),
          ),
          const SizedBox(height: Space.md),
          Text('Touchez un thème pour l\'utiliser dès maintenant ; touchez-le à nouveau pour revenir à votre thème.', style: t.bodySmall),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.md,
            children: [
              for (final e in SeasonalEvent.values)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThemeSwatch(
                      preset: settings.themePreset,
                      palette: e.palette,
                      label: '${e.label} ${e.emoji}',
                      selected: settings.activeSeason == e,
                      onTap: () => settings.forceSeason(settings.seasonForced == e ? null : e),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(width: 140, child: Text(e.period, style: t.labelSmall, maxLines: 2)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Text('Thème personnalisé', style: t.titleLarge),
          const SizedBox(height: Space.sm),
          Text('Choisissez une couleur d\'accent et un fond ; le reste de la palette est dérivé automatiquement.', style: t.bodySmall),
          const SizedBox(height: Space.lg),
          Text('Couleur d\'accent', style: t.titleSmall),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.md, runSpacing: Space.md, children: [
            for (final c in _accents)
              _Dot(color: c, selected: settings.themePreset == ThemePreset.custom && settings.customAccent == c,
                  onTap: () => settings.setCustomTheme(accent: c)),
          ]),
          const SizedBox(height: Space.lg),
          Text('Fond', style: t.titleSmall),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.md, runSpacing: Space.md, children: [
            for (final (c, dark) in _backgrounds)
              _Dot(color: c, selected: settings.themePreset == ThemePreset.custom && settings.customBackground == c,
                  onTap: () => settings.setCustomTheme(background: c, dark: dark)),
          ]),
          const SizedBox(height: Space.xl),
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(color: p.surface, borderRadius: const BorderRadius.all(Radii.lg), border: Border.all(color: p.divider)),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: p.primary),
              const SizedBox(width: Space.md),
              Expanded(child: Text('Le fond des pages se règle séparément, dans le lecteur (Aa › Fond).', style: t.bodyMedium)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.scaled(context, Motion.fast),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? p.primary : p.divider, width: selected ? 3 : 1),
        ),
        child: selected ? Icon(Icons.check_rounded, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white, size: 20) : null,
      ),
    );
  }
}
