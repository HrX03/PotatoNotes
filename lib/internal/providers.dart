import 'package:dio/dio.dart';
import 'package:potato_notes/data/dao/note_helper.dart';
import 'package:potato_notes/data/dao/tag_helper.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/internal/app_config.dart';
import 'package:potato_notes/internal/app_info.dart';
import 'package:potato_notes/internal/backup_delegate.dart';
import 'package:potato_notes/internal/device_info.dart';
import 'package:potato_notes/internal/keystore.dart';
import 'package:potato_notes/internal/preferences.dart';
import 'package:potato_notes/internal/shared_prefs.dart';
import 'package:potato_notes/internal/sync/image/image_helper.dart';
import 'package:potato_notes/internal/sync/image_queue.dart';
import 'package:potato_notes/internal/sync/request_interceptor.dart';
import 'package:potato_notes/internal/sync/sync_routine.dart';

class _ProvidersSingleton {
  _ProvidersSingleton._();

  late Keystore _keystore;
  late SharedPrefs _sharedPrefs;
  late AppConfig _appConfig;
  late AppInfo _appInfo;
  late DeviceInfo _deviceInfo;
  late Preferences _prefs;
  late BackupDelegate _backupDelegate;
  late ImageQueue _imageQueue;
  late Dio _dio;
  late NoteHelper _helper;
  late TagHelper _tagHelper;
  late SyncRoutine _syncRoutine;
  late ImageHelper _imageHelper;

  static final _ProvidersSingleton instance = _ProvidersSingleton._();

  Future<void> initKeystore() async {
    _keystore = await Keystore.newInstance();
  }

  Future<void> initProviders(AppDatabase _db) async {
    _sharedPrefs = await SharedPrefs.newInstance();
    _appConfig = await AppConfig.load();
    _helper = _db.noteHelper;
    _tagHelper = _db.tagHelper;
    _dio = Dio();
    _dio.interceptors.add(RequestInterceptor());
    _prefs = Preferences();
    _deviceInfo = DeviceInfo();
    _imageQueue = ImageQueue();
    _appInfo = AppInfo();
    _backupDelegate = BackupDelegate();
    _syncRoutine = SyncRoutine();
    _imageHelper = ImageHelper();
  }
}

Future<void> initKeystore() async =>
    _ProvidersSingleton.instance.initKeystore();

Future<void> initProviders(AppDatabase _db) async =>
    _ProvidersSingleton.instance.initProviders(_db);

Keystore get keystore => _ProvidersSingleton.instance._keystore;

AppConfig get appConfig => _ProvidersSingleton.instance._appConfig;

SharedPrefs get sharedPrefs => _ProvidersSingleton.instance._sharedPrefs;

AppInfo get appInfo => _ProvidersSingleton.instance._appInfo;

DeviceInfo get deviceInfo => _ProvidersSingleton.instance._deviceInfo;

Preferences get prefs => _ProvidersSingleton.instance._prefs;

BackupDelegate get backupDelegate =>
    _ProvidersSingleton.instance._backupDelegate;

ImageQueue get imageQueue => _ProvidersSingleton.instance._imageQueue;

Dio get dio => _ProvidersSingleton.instance._dio;

NoteHelper get helper => _ProvidersSingleton.instance._helper;

TagHelper get tagHelper => _ProvidersSingleton.instance._tagHelper;

SyncRoutine get syncRoutine => _ProvidersSingleton.instance._syncRoutine;
