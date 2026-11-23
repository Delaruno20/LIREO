import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../data/settings/app_settings.dart';
import '../splash/splash_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    (
      Icons.auto_stories_rounded,
      'Votre bibliothèque, magnifiée',
      'Importez vos EPUB, PDF, MOBI, FB2, DOCX, TXT ou BD. LIREO extrait titres, auteurs et couvertures, puis les range sur de vraies étagères.',
    ),
    (
      Icons.tune_rounded,
      'Une lecture à votre mesure',
      'Polices, interligne, marges, fonds, animation de page, gestes : chaque détail se règle, et peut être mémorisé pour chaque livre.',
    ),
    (
      Icons.lock_outline_rounded,
      'Hors ligne et privé',
      'Aucune publicité, aucun pistage. Vos livres, notes et statistiques restent sur votre appareil.',
    ),
  ];

  void _finish() => context.read<AppSettings>().completeOnboarding();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final last = _page == _slides.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.sm, 0),
              child: Row(
                children: [
                  LireoMark(size: 30, color: p.primary),
                  const SizedBox(width: Space.sm),
                  Text('Lireo', style: t.headlineSmall),
                  const Spacer(),
                  if (!last) TextButton(onPressed: _finish, child: const Text('Passer')),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final (icon, title, body) in _slides)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [p.accent.withValues(alpha: 0.35), p.background]),
                            ),
                            child: Icon(icon, size: 64, color: p.primary),
                          ),
                          const SizedBox(height: Space.xxl),
                          Text(title, style: t.displaySmall, textAlign: TextAlign.center),
                          const SizedBox(height: Space.lg),
                          Text(body, style: t.bodyLarge?.copyWith(color: p.textMuted), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  const _ThemeStep(),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i <= _slides.length; i++)
                  AnimatedContainer(
                    duration: Motion.scaled(context, Motion.medium),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page ? p.primary : p.divider,
                      borderRadius: const BorderRadius.all(Radii.pill),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? _finish
                      : () => _controller.nextPage(duration: Motion.scaled(context, Motion.medium), curve: Motion.curve),
                  child: Text(last ? 'Entrer dans ma bibliothèque' : 'Continuer'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeStep extends StatelessWidget {
  const _ThemeStep();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final t = Theme.of(context).textTheme;
    final p = LireoPalette.of(context);
    const options = [ThemePreset.warmLibrary, ThemePreset.oledMidnight, ThemePreset.paper, ThemePreset.sage];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Choisissez votre ambiance', style: t.displaySmall, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          Text('Modifiable à tout moment dans les paramètres.', style: t.bodyMedium?.copyWith(color: p.textMuted)),
          const SizedBox(height: Space.xl),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.md,
            alignment: WrapAlignment.center,
            children: [
              for (final o in options) ThemeSwatch(preset: o, selected: settings.themePreset == o, onTap: () => settings.setTheme(o)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aperçu miniature d'un thème (réutilisé dans la personnalisation).
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({super.key, required this.preset, required this.selected, required this.onTap, this.palette, this.label});

  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;
  final LireoPalette? palette;

  /// Libellé à la place de celui du preset (thèmes événementiels).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final sp = palette ?? LireoPalette.forPreset(preset);
    final p = LireoPalette.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: label ?? preset.label,
      child: AnimatedContainer(
        duration: Motion.scaled(context, Motion.fast),
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: sp.background,
          borderRadius: const BorderRadius.all(Radii.md),
          border: Border.all(color: selected ? p.primary : p.divider, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final c in [sp.primary, sp.accent, sp.shelfFront])
                  Container(
                    width: 26,
                    height: 38,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(color: c, borderRadius: Radii.cover),
                  ),
              ],
            ),
            Container(height: 5, color: sp.shelfTop),
            const SizedBox(height: 8),
            Text(label ?? preset.label, style: TextStyle(fontFamily: Fonts.ui, fontSize: 13, fontWeight: FontWeight.w600, color: sp.text)),
          ],
        ),
      ),
    );
  }
}
