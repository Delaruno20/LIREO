import 'dart:async';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/errors.dart';
import '../../data/repositories/library_repository.dart';
import '../../services/home_widget_service.dart';

import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../collections/collections_screen.dart';
import '../discover/discover_screen.dart';
import '../library/home_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Navigation principale : barre flottante sur téléphone, rail latéral sur tablette.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _visited = <int>{0};
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    // Reprise directe d'un livre depuis le widget d'écran d'accueil (Android seul).
    if (!Platform.isAndroid) return;
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget).catchError((_) {});
    _widgetClicks = HomeWidget.widgetClicked.listen(_openFromWidget, onError: (_) {});
  }

  Future<void> _openFromWidget(Uri? uri) async {
    final id = LibraryObservers.bookIdFrom(uri);
    if (id == null || !mounted) return;
    final book = await context.read<LibraryRepository>().book(id);
    if (book == null || !mounted) return AppError.toast('Ce livre n\'est plus dans la bibliothèque');
    await Routes.reader(context, book);
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
    super.dispose();
  }

  static const _destinations = [
    _Destination('Accueil', Icons.home_outlined, Icons.home_rounded),
    _Destination('Découvrir', Icons.explore_outlined, Icons.explore_rounded),
    _Destination('Collections', Icons.collections_bookmark_outlined, Icons.collections_bookmark_rounded),
    _Destination('Statistiques', Icons.insights_outlined, Icons.insights_rounded),
    _Destination('Paramètres', Icons.settings_outlined, Icons.settings_rounded),
  ];

  Widget _page(int i) => switch (i) {
        0 => const HomeScreen(),
        1 => const DiscoverScreen(),
        2 => const CollectionsScreen(),
        3 => const StatsScreen(),
        _ => const SettingsScreen(),
      };

  void _select(int i) {
    if (i == _index) return;
    haptic(context);
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final p = LireoPalette.of(context);
    // Les onglets ne sont construits qu'à la première visite, puis conservés.
    final stack = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _destinations.length; i++) _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: p.surface,
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              indicatorColor: p.primary.withValues(alpha: 0.15),
              selectedIconTheme: IconThemeData(color: p.primary),
              selectedLabelTextStyle: TextStyle(color: p.primary, fontWeight: FontWeight.w600, fontFamily: Fonts.ui),
              unselectedLabelTextStyle: TextStyle(color: p.textMuted, fontFamily: Fonts.ui),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.activeIcon), label: Text(d.label)),
              ],
            ),
            VerticalDivider(width: 1, color: p.divider),
            Expanded(child: stack),
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: stack,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Glass(
          radius: Radii.lg,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              for (var i = 0; i < _destinations.length; i++)
                Expanded(child: _NavItem(destination: _destinations[i], active: i == _index, onTap: () => _select(i))),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.active, required this.onTap});

  final _Destination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final color = active ? p.primary : p.textMuted;
    return Semantics(
      selected: active,
      button: true,
      label: destination.label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Motion.scaled(context, Motion.medium),
                curve: Motion.curve,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: active ? p.primary.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: const BorderRadius.all(Radii.pill),
                ),
                child: Icon(active ? destination.activeIcon : destination.icon, color: color, size: 23),
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontFamily: Fonts.ui,
                  fontSize: 10.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
