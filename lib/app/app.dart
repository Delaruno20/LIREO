import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../core/design/app_theme.dart';
import '../core/design/tokens.dart';
import '../core/errors.dart';
import '../data/settings/app_settings.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/security/lock_screen.dart';
import '../features/shell/main_shell.dart';
import '../features/splash/splash_screen.dart';
import '../services/app_lock.dart';
import 'services.dart';

class LireoApp extends StatefulWidget {
  const LireoApp({super.key});

  @override
  State<LireoApp> createState() => _LireoAppState();
}

class _LireoAppState extends State<LireoApp> {
  late final Future<AppServices> _services = _boot();

  Future<AppServices> _boot() async {
    await pdfrxFlutterInitialize();
    return AppServices.create();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _services,
      builder: (context, snap) {
        if (snap.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Text('Impossible de démarrer LIREO :\n${snap.error}'),
              ),
            ),
          );
        }
        final services = snap.data;
        if (services == null) return const SplashApp();
        return LireoRoot(services: services);
      },
    );
  }
}

/// Racine de l'application une fois les services prêts.
class LireoRoot extends StatelessWidget {
  const LireoRoot({super.key, required this.services});
  final AppServices services;

  /// Couvertures et illustrations sont décodées à la taille d'affichage :
  /// 48 Mo suffisent et évitent de garder 100 Mo d'images hors écran.
  static const imageCacheBytes = 48 << 20;

  @override
  Widget build(BuildContext context) {
    PaintingBinding.instance.imageCache.maximumSizeBytes = imageCacheBytes;
    return MultiProvider(
      providers: [
        Provider.value(value: services),
        Provider.value(value: services.library),
        Provider.value(value: services.annotations),
        Provider.value(value: services.stats),
        Provider.value(value: services.storage),
        ChangeNotifierProvider.value(value: services.settings),
        ChangeNotifierProvider.value(value: services.importer),
        ChangeNotifierProvider.value(value: services.lock),
        ChangeNotifierProvider.value(value: services.fonts),
        ChangeNotifierProvider.value(value: services.sync),
      ],
      child: const _ThemedApp(),
    );
  }
}

class _ThemedApp extends StatefulWidget {
  const _ThemedApp();

  @override
  State<_ThemedApp> createState() => _ThemedAppState();
}

/// Recalcule le thème événementiel au retour dans l'app et à chaque minuit,
/// pour qu'une app restée ouverte bascule le jour même de l'événement.
class _ThemedAppState extends State<_ThemedApp> with WidgetsBindingObserver {
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(now), () {
      context.read<AppSettings>().refreshSeason();
      _scheduleMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppSettings>().refreshSeason();
      _scheduleMidnight();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final palette = settings.palette;
    return MaterialApp(
      title: 'LIREO',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: AppError.messengerKey,
      theme: buildTheme(palette),
      themeAnimationDuration: settings.effectiveAnimations
          ? Motion.slow
          : Duration.zero,
      themeAnimationCurve: Motion.curve,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MotionScope(
        enabled: settings.effectiveAnimations,
        child: _LockGate(child: child ?? const SizedBox()),
      ),
      home: settings.onboardingDone
          ? const MainShell()
          : const OnboardingScreen(),
    );
  }
}

/// Superpose l'écran de verrouillage tant que l'app est verrouillée.
class _LockGate extends StatelessWidget {
  const _LockGate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final locked = context.select<AppLock, bool>((l) => l.locked);
    return Stack(
      children: [
        // Contenu masqué (et retiré de l'accessibilité) tant que verrouillé.
        ExcludeSemantics(
          excluding: locked,
          child: Offstage(offstage: locked, child: child),
        ),
        if (locked) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}
