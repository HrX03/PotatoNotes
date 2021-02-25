package io.flutter.plugins;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry;

/**
 * Generated file. Do not edit.
 * This file is generated by the Flutter tool based on the
 * plugins that support the Android platform.
 */
@Keep
public final class GeneratedPluginRegistrant {
  public static void registerWith(@NonNull FlutterEngine flutterEngine) {
    ShimPluginRegistry shimPluginRegistry = new ShimPluginRegistry(flutterEngine);
      com.mr.flutter.plugin.filepicker.FilePickerPlugin.registerWith(shimPluginRegistry.registrarFor("com.mr.flutter.plugin.filepicker.FilePickerPlugin"));
    flutterEngine.getPlugins().add(new vn.hunghd.flutterdownloader.FlutterDownloaderPlugin());
    flutterEngine.getPlugins().add(new com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin());
    flutterEngine.getPlugins().add(new io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin());
    flutterEngine.getPlugins().add(new com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin());
      io.flutter.plugins.imagepicker.ImagePickerPlugin.registerWith(shimPluginRegistry.registrarFor("io.flutter.plugins.imagepicker.ImagePickerPlugin"));
    flutterEngine.getPlugins().add(new de.ffuf.in_app_update.InAppUpdatePlugin());
    flutterEngine.getPlugins().add(new io.flutter.plugins.localauth.LocalAuthPlugin());
    flutterEngine.getPlugins().add(new hrx.loggy.LoggyPlugin());
    flutterEngine.getPlugins().add(new io.flutter.plugins.packageinfo.PackageInfoPlugin());
    flutterEngine.getPlugins().add(new io.flutter.plugins.pathprovider.PathProviderPlugin());
    flutterEngine.getPlugins().add(new io.flutter.plugins.quickactions.QuickActionsPlugin());
    flutterEngine.getPlugins().add(new io.flutter.plugins.share.SharePlugin());
    flutterEngine.getPlugins().add(new io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin());
    flutterEngine.getPlugins().add(new com.tekartik.sqflite.SqflitePlugin());
    flutterEngine.getPlugins().add(new eu.simonbinder.sqlite3_flutter_libs.Sqlite3FlutterLibsPlugin());
    flutterEngine.getPlugins().add(new io.flutter.plugins.urllauncher.UrlLauncherPlugin());
  }
}
