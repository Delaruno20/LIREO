import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/errors.dart';
import '../data/models/book.dart';

/// Rappel de lecture quotidien (notification locale, aucune connexion requise).
class ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _id = 1;
  static bool get supported => Platform.isAndroid || Platform.isIOS;

  Future<bool> _init() async {
    if (_ready) return true;
    if (!supported) return false;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
      );
      _ready = true;
      return true;
    } catch (e, st) {
      AppError.report(e, st, context: 'reminder.init');
      return false;
    }
  }

  /// Demande l'autorisation d'afficher des notifications (Android 13+, iOS).
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  /// Programme (ou reprogramme) le rappel quotidien. Le texte mentionne le
  /// livre en cours au moment de la programmation.
  Future<void> schedule(TimeOfDay time, {Book? current}) async {
    if (!await _init()) return;
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    final body = current == null
        ? 'Quelques pages avant de dormir ? Votre bibliothèque vous attend.'
        : 'Reprenez « ${current.title} » là où vous l\'avez laissé (${(current.progress * 100).round()} %).';
    await _plugin.cancel(id: _id);
    await _plugin.zonedSchedule(
      id: _id,
      scheduledDate: at,
      title: 'C\'est l\'heure de lire',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'reading_reminder',
          'Rappel de lecture',
          channelDescription: 'Rappel quotidien pour garder l\'habitude de lire',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // Inexact : aucune autorisation d'alarme exacte nécessaire, économe en batterie.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel() async {
    if (!await _init()) return;
    await _plugin.cancel(id: _id);
  }
}
