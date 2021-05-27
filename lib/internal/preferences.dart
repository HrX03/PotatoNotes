import 'package:flutter/material.dart';
import 'package:mobx/mobx.dart';
import 'package:potato_notes/data/dao/tag_helper.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/internal/jwt_decode.dart';
import 'package:potato_notes/internal/logger_provider.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/controller.dart';

part 'preferences.g.dart';

class Preferences = _PreferencesBase with _$Preferences;

abstract class _PreferencesBase with Store, LoggerProvider {
  _PreferencesBase() {
    loadData();
  }

  @observable
  String _masterPassValue = "";

  @observable
  ThemeMode _themeModeValue = sharedPrefs.themeMode;

  @observable
  Color? _customAccentValue = sharedPrefs.customAccent;

  @observable
  bool _useAmoledValue = sharedPrefs.useAmoled;

  @observable
  bool _useGridValue = sharedPrefs.useGrid;

  @observable
  bool _useCustomAccentValue = sharedPrefs.useCustomAccent;

  @observable
  bool _welcomePageSeenValue = sharedPrefs.welcomePageSeen;

  @observable
  bool _protectBackupsValue = sharedPrefs.protectBackups;

  @observable
  String _apiUrlValue = sharedPrefs.apiUrl;

  @observable
  String? _accessTokenValue = sharedPrefs.accessToken;

  @observable
  String? _refreshTokenValue = sharedPrefs.refreshToken;

  @observable
  String? _usernameValue = sharedPrefs.username;

  @observable
  String? _emailValue = sharedPrefs.email;

  @observable
  String? _avatarUrlValue = sharedPrefs.avatarUrl;

  @observable
  int _logLevelValue = sharedPrefs.logLevel;

  @observable
  List<dynamic> _tagsValue = [];

  @observable
  List<String> _downloadedImagesValue = sharedPrefs.downloadedImages;

  @observable
  List<String> _deletedImagesValue = sharedPrefs.deletedImages;

  @observable
  int _lastUpdatedValue = sharedPrefs.lastUpdated;

  @observable
  String? _deleteQueueValue = sharedPrefs.deleteQueue;

  String get masterPass => _masterPassValue;
  ThemeMode get themeMode => _themeModeValue;
  Color? get customAccent => _customAccentValue;
  bool get useAmoled => _useAmoledValue;
  bool get useGrid => _useGridValue;
  bool get useCustomAccent => _useCustomAccentValue;
  bool get welcomePageSeen => _welcomePageSeenValue;
  bool get protectBackups => _protectBackupsValue;
  String get apiUrl => _apiUrlValue;
  String? get accessToken => _accessTokenValue;
  String? get refreshToken => _refreshTokenValue;
  String? get username => _usernameValue;
  String? get email => _emailValue;
  String? get avatarUrl => _avatarUrlValue;
  String? get avatarUrlAsKey => _avatarUrlValue?.split("?").first;
  int get logLevel => _logLevelValue;
  List<Tag> get tags => _tagsValue.map((e) => e as Tag).toList();
  List<String> get downloadedImages => _downloadedImagesValue;
  List<String> get deletedImages => _deletedImagesValue;
  int get lastUpdated => _lastUpdatedValue;
  String? get deleteQueue => _deleteQueueValue;

  set masterPass(String value) {
    _masterPassValue = value;

    keystore.setMasterPass(value);
  }

  set themeMode(ThemeMode value) {
    _themeModeValue = value;
    sharedPrefs.themeMode = value;
  }

  set customAccent(Color? value) {
    _customAccentValue = value;
    sharedPrefs.customAccent = value;
  }

  set useAmoled(bool value) {
    _useAmoledValue = value;
    sharedPrefs.useAmoled = value;
  }

  set useGrid(bool value) {
    _useGridValue = value;
    sharedPrefs.useGrid = value;
  }

  set useCustomAccent(bool value) {
    _useCustomAccentValue = value;
    sharedPrefs.useCustomAccent = value;
  }

  set welcomePageSeen(bool value) {
    _welcomePageSeenValue = value;
    sharedPrefs.welcomePageSeen = value;
  }

  set protectBackups(bool value) {
    _protectBackupsValue = value;
    sharedPrefs.protectBackups = value;
  }

  set apiUrl(String value) {
    _apiUrlValue = value;
    sharedPrefs.apiUrl = value;
  }

  set accessToken(String? value) {
    _accessTokenValue = value;
    sharedPrefs.accessToken = value;
  }

  set refreshToken(String? value) {
    _refreshTokenValue = value;
    sharedPrefs.refreshToken = value;
  }

  set username(String? value) {
    _usernameValue = value;
    sharedPrefs.username = value;
  }

  set email(String? value) {
    _emailValue = value;
    sharedPrefs.email = value;
  }

  set avatarUrl(String? value) {
    _avatarUrlValue = value;
    sharedPrefs.avatarUrl = value;
  }

  set logLevel(int value) {
    _logLevelValue = value;
    sharedPrefs.logLevel = value;
  }

  set downloadedImages(List<String> value) {
    _downloadedImagesValue = value;
    sharedPrefs.downloadedImages = value;
  }

  set deletedImages(List<String> value) {
    _deletedImagesValue = value;
    sharedPrefs.deletedImages = value;
  }

  set lastUpdated(int value) {
    _lastUpdatedValue = value;
    sharedPrefs.lastUpdated = value;
  }

  set deleteQueue(String? value) {
    _deleteQueueValue = value;
    sharedPrefs.deleteQueue = value;
  }

  Object? getFromCache(String key) {
    return sharedPrefs.prefs.get(key);
  }

  Future<void> loadData() async {
    _masterPassValue = await keystore.getMasterPass();

    _tagsValue = await tagHelper.listTags(TagReturnMode.local);

    tagHelper.watchTags(TagReturnMode.local).listen((newTags) {
      _tagsValue = newTags;
    });

    if (sharedPrefs.accessToken != null) {
      avatarUrl = Controller.files.url("get/avatar.jpg");
    }
  }

  Future<String> getToken() async {
    final bool tokenExpired = accessToken != null
        ? DateTime.fromMillisecondsSinceEpoch(
            (Jwt.parseJwt(accessToken!)["exp"] as int) * 1000,
          ).isBefore(DateTime.now())
        : false;

    if (accessToken == null || tokenExpired) {
      final AuthResponse response = await Controller.account.refreshToken();

      if (!response.status) {
        logger.w(response.message);
      }
    }

    return accessToken!;
  }
}
