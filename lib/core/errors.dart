import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';

/// Erreur dont le message peut être montré tel quel à l'utilisateur.
class UserFacingError implements Exception {
  const UserFacingError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Gestion centralisée des erreurs : journalisation + message lisible.
abstract final class AppError {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static final _log = <String>[];

  /// Dernières erreurs (consultables dans Paramètres › À propos).
  static List<String> get recent => List.unmodifiable(_log);

  static void install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(details.exception, details.stack, context: 'flutter');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, context: 'platform');
      return true;
    };
  }

  static void report(Object error, StackTrace? stack, {String context = ''}) {
    final line = '[${DateTime.now().toIso8601String()}] $context: $error';
    _log.add(line);
    if (_log.length > 50) _log.removeAt(0);
    debugPrint(line);
    if (stack != null) debugPrintStack(stackTrace: stack, maxFrames: 8);
  }

  static String describe(Object e) => switch (e) {
        UserFacingError(:final message) => message,
        FileSystemException(:final message) => 'Fichier inaccessible ($message)',
        FormatException(:final message) => 'Fichier illisible : $message',
        TimeoutException() => 'L\'opération a pris trop de temps',
        _ => e.toString().replaceFirst('Exception: ', ''),
      };

  static void toast(String message, {SnackBarAction? action}) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action, duration: const Duration(seconds: 3)));
  }

  /// Exécute [task] et affiche l'erreur éventuelle sans planter l'app.
  static Future<T?> guard<T>(Future<T> Function() task, {String? context}) async {
    try {
      return await task();
    } catch (e, st) {
      report(e, st, context: context ?? 'guard');
      toast(describe(e));
      return null;
    }
  }
}
