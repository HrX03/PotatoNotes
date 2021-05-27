import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mobx/mobx.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:potato_notes/internal/backup_delegate.dart';
import 'package:potato_notes/internal/device_info.dart';
import 'package:potato_notes/internal/notification_payload.dart';
import 'package:potato_notes/internal/utils.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:universal_platform/universal_platform.dart';

part 'app_info.g.dart';

class AppInfo extends _AppInfoBase with _$AppInfo {
  AppInfo();

  /// This bool defines whether the app is ready to
  /// support the notes api in a production environment
  static bool supportsNotesApi = true;

  static bool supportsNotePinning =
      UniversalPlatform.isAndroid || UniversalPlatform.isIOS;
}

abstract class _AppInfoBase with Store {
  static const EventChannel accentStreamChannel =
      EventChannel('potato_notes_accents');
  static const MethodChannel backupPromptChannel =
      MethodChannel('potato_notes_backup_prompt');

  _AppInfoBase() {
    loadData();
  }

  late Directory tempDirectory;
  FlutterLocalNotificationsPlugin? notifications;
  QuickActions? quickActions;
  late PackageInfo packageInfo;

  @observable
  @protected
  int _accentDataValue = Colors.blue.value;

  int get accentData => _accentDataValue;

  @observable
  @protected
  List<ActiveNotification> _activeNotificationsValue = [];

  List<ActiveNotification> get activeNotifications => _activeNotificationsValue;

  Future<void> _initNotifications() async {
    notifications = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('notes_icon');
    const IOSInitializationSettings initializationSettingsIOS =
        IOSInitializationSettings();
    const MacOSInitializationSettings initializationSettingsMacOS =
        MacOSInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      macOS: initializationSettingsMacOS,
    );
    await notifications!.initialize(initializationSettings,
        onSelectNotification: _handleNotificationTap);
    /* notifications!
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()!
        .requestPermissions(); */
  }

  Future<dynamic> _handleNotificationTap(String? payload) async {
    if (payload == null) return;

    final NotificationPayload nPayload = NotificationPayload.fromJson(
      Utils.asMap<String, dynamic>(json.decode(payload)),
    );

    switch (nPayload.action) {
      case NotificationAction.pin:
        notifications!.cancel(nPayload.id);
        break;
      case NotificationAction.reminder:
        break;
    }
  }

  Future<void> loadData() async {
    tempDirectory = await getTemporaryDirectory();
    final String backupDir = await BackupDelegate.getOutputDir();
    Directory(backupDir).create();

    if (AppInfo.supportsNotePinning) {
      _initNotifications();
    }
    packageInfo = await PackageInfo.fromPlatform();

    if (DeviceInfo.isAndroid) {
      accentStreamChannel.receiveBroadcastStream().listen(updateAccent);
    } else {
      _accentDataValue = -1;
    }

    if (DeviceInfo.isAndroid) {
      pollForActiveNotifications();
    }
  }

  @action
  void updateAccent(dynamic event) {
    _accentDataValue = event as int;
  }

  @action
  void pollForActiveNotifications() {
    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      final List<ActiveNotification>? _activeNotifications = await notifications
          ?.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.getActiveNotifications();
      _activeNotificationsValue = _activeNotifications ?? [];
    });
  }

  Future<String?> requestBackupExport(String name, String path) async {
    final String? result = await backupPromptChannel.invokeMethod<String>(
      'requestBackupExport',
      {'name': name, 'path': path},
    );
    return result;
  }
}
