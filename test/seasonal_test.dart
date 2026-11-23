import 'package:flutter_test/flutter_test.dart';
import 'package:lireo/core/design/palette.dart';
import 'package:lireo/core/design/seasonal.dart';
import 'package:lireo/data/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  SeasonalEvent? on(int y, int m, int d) => SeasonalEvent.activeOn(DateTime(y, m, d, 15));

  test('date de Pâques', () {
    expect(SeasonalEvent.easterSunday(2024), DateTime(2024, 3, 31));
    expect(SeasonalEvent.easterSunday(2025), DateTime(2025, 4, 20));
    expect(SeasonalEvent.easterSunday(2026), DateTime(2026, 4, 5));
    expect(SeasonalEvent.easterSunday(2027), DateTime(2027, 3, 28));
  });

  test('périodes des événements', () {
    expect(on(2026, 11, 30), isNull);
    expect(on(2026, 12, 1), SeasonalEvent.christmas);
    expect(on(2026, 12, 25), SeasonalEvent.christmas);
    expect(on(2026, 12, 31), SeasonalEvent.newYear);
    expect(on(2027, 1, 1), SeasonalEvent.newYear);
    expect(on(2027, 1, 15), SeasonalEvent.newYear);
    expect(on(2027, 1, 16), isNull);
    expect(on(2027, 2, 3), isNull);
    expect(on(2027, 2, 11), SeasonalEvent.cameroonYouth);
    expect(on(2027, 2, 15), isNull);
    // Pâques 2027 : 28 mars → du 21 au 29 mars.
    expect(on(2027, 3, 20), isNull);
    expect(on(2027, 3, 21), SeasonalEvent.easter);
    expect(on(2027, 3, 29), SeasonalEvent.easter);
    expect(on(2027, 3, 30), isNull);
    expect(on(2027, 6, 13), isNull);
    expect(on(2027, 6, 21), SeasonalEvent.fetMusique);
    expect(on(2027, 6, 23), isNull);
  });

  test('bascule automatique, option et thème forcé', () async {
    SharedPreferences.setMockInitialValues({'theme': 'paper'});
    var now = DateTime(2026, 11, 30, 23, 59);
    final settings = AppSettings(await SharedPreferences.getInstance(), clock: () => now);
    expect(settings.activeSeason, isNull);
    expect(settings.palette, LireoPalette.paper);

    now = DateTime(2026, 12, 1, 0, 1);
    settings.refreshSeason();
    expect(settings.activeSeason, SeasonalEvent.christmas);
    expect(settings.palette, SeasonalEvent.christmas.palette);

    await settings.setSeasonalAuto(false);
    expect(settings.palette, LireoPalette.paper);

    await settings.forceSeason(SeasonalEvent.easter);
    expect(settings.activeSeason, SeasonalEvent.easter);

    // Choisir un thème classique annule le thème forcé.
    await settings.setTheme(ThemePreset.sage);
    expect(settings.seasonForced, isNull);
    expect(settings.palette, LireoPalette.sage);
  });
}
