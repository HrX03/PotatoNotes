import 'dart:convert';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:loggy/loggy.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:potato_notes/data/dao/note_helper.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/internal/app_info.dart';
import 'package:potato_notes/internal/locales/native_names.dart';
import 'package:potato_notes/internal/sync/controller.dart';
import 'package:potato_notes/internal/in_app_update.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/utils.dart';
import 'package:potato_notes/internal/locales/locale_strings.g.dart';
import 'package:potato_notes/routes/about_page.dart';
import 'package:potato_notes/routes/backup_and_restore/backup_page.dart';
import 'package:potato_notes/routes/backup_and_restore/import_page.dart';
import 'package:potato_notes/widget/dependent_scaffold.dart';
import 'package:potato_notes/widget/pass_challenge.dart';
import 'package:potato_notes/widget/rgb_color_picker.dart';
import 'package:potato_notes/widget/settings_category.dart';
import 'package:potato_notes/widget/settings_tile.dart';
import 'package:potato_notes/widget/sync_url_editor.dart';
import 'package:recase/recase.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:universal_platform/universal_platform.dart';

class SettingsPage extends StatefulWidget {
  final bool trimmed;

  const SettingsPage({
    Key? key,
    this.trimmed = false,
  }) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool removingMasterPass = false;

  @override
  Widget build(BuildContext context) {
    if (widget.trimmed) return Observer(builder: (context) => commonSettings);

    return DependentScaffold(
      resizeToAvoidBottomInset: false,
      body: Observer(builder: (context) {
        return ListView(
          padding: EdgeInsets.only(
            top: context.padding.top,
            bottom: context.viewInsets.bottom,
          ),
          children: [
            commonSettings,
            SettingsCategory(
              header: "Backup & Restore",
              children: [
                SettingsTile(
                  icon: const Icon(MdiIcons.contentSaveOutline),
                  title: const Text("Backup"),
                  description: const Text("Create a local copy of your notes"),
                  onTap: () async {
                    await Utils.showNotesModalBottomSheet(
                      context: context,
                      builder: (context) => BackupPage(),
                    );
                  },
                ),
                SettingsTile(
                  icon: const Icon(MdiIcons.restore),
                  title: const Text("Restore"),
                  description: const Text(
                      "Restore a backup created from a version of Leaflet"),
                  onTap: () {
                    context.scaffoldMessenger.removeCurrentSnackBar();
                    context.scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                            "This feature is not yet available on this version."),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                SettingsTile(
                  icon: const Icon(MdiIcons.fileImportOutline),
                  title: const Text("Migrate"),
                  description:
                      const Text("Import notes from a version of PotatoNotes"),
                  onTap: () async {
                    await Utils.showSecondaryRoute(
                      context,
                      ImportPage(),
                    );
                  },
                ),
              ],
            ),
            SettingsCategory(
              header: LocaleStrings.settings.infoTitle,
              children: <Widget>[
                SettingsTile(
                  icon: const Icon(Icons.info_outline),
                  title: Text(LocaleStrings.settings.infoAboutApp),
                  onTap: () => Utils.showSecondaryRoute(
                    context,
                    AboutPage(),
                  ),
                ),
                SettingsTile(
                  icon: const Icon(Icons.update_outlined),
                  title: const Text("Check for app updates"),
                  onTap: () => InAppUpdater.checkForUpdate(
                    context,
                    showNoUpdatesAvailable: true,
                  ),
                ),
              ],
            ),
            Visibility(
              // ignore: avoid_redundant_argument_values
              visible: kDebugMode,
              child: SettingsCategory(
                header: LocaleStrings.settings.debugTitle,
                children: [
                  SettingsTile.withSwitch(
                    icon: const Icon(MdiIcons.humanGreeting),
                    title: Text(
                      LocaleStrings.settings.debugShowSetupScreen,
                    ),
                    value: !prefs.welcomePageSeen,
                    activeColor: context.theme.accentColor,
                    onChanged: (value) async {
                      prefs.welcomePageSeen = !value;
                    },
                  ),
                  SettingsTile(
                    icon: const Icon(Icons.timer),
                    title: const Text("Test loading overlay"),
                    onTap: () {
                      Utils.showLoadingOverlay(context);
                      Future.delayed(
                        const Duration(milliseconds: 5000),
                        () async => Utils.hideLoadingOverlay(context),
                      );
                    },
                  ),
                  SettingsTile(
                    icon: const Icon(MdiIcons.databaseRemoveOutline),
                    title: Text(LocaleStrings.settings.debugClearDatabase),
                    onTap: () async {
                      await helper.deleteAllNotes();
                      if (AppInfo.supportsNotesApi &&
                          prefs.accessToken != null) {
                        await Controller.note.deleteAll();
                      }
                    },
                  ),
                  SettingsTile(
                    icon: const Icon(MdiIcons.databasePlusOutline),
                    title: const Text("Generate trash"),
                    onTap: () async {
                      for (int i = 0; i < 100; i++) {
                        final Random r = Random();
                        final Note n = NoteX.emptyNote.copyWith(
                          id: Utils.generateId(),
                          title: String.fromCharCodes(
                            List.generate(
                              32,
                              (index) => 33 + r.nextInt(126 - 33),
                            ),
                          ),
                          content: String.fromCharCodes(
                            List.generate(
                              128,
                              (index) => 33 + r.nextInt(126 - 33),
                            ),
                          ),
                          starred: r.nextBool(),
                          color: r.nextInt(10),
                          images: List.generate(
                            2,
                            (index) => SavedImage.fromJson(
                              json.decode(
                                '{"id": "fe4fbad3-8f4e-4bbd-95ca-b3ed12490ba8","storageLocation": "local","hash": null,"blurHash": null,"fileExtension": ".png","encrypted": false,"width": 708.0,"height": 491.0,"uploaded": false}',
                              ) as Map<String, dynamic>,
                            ),
                          ),
                        );
                        await helper.saveNote(n);
                      }
                    },
                  ),
                  SettingsTile(
                    icon: const Icon(Icons.text_snippet_outlined),
                    title: Text(LocaleStrings.settings.debugLogLevel),
                    onTap: () {
                      showDropdownSheet(
                        context: context,
                        itemBuilder: (context, index) {
                          final bool selected = prefs.logLevel == index;

                          return dropDownTile(
                            selected: selected,
                            title: Text(
                              LogLevel.values[index].name,
                            ),
                            onTap: () {
                              prefs.logLevel = index;
                              context.pop();
                            },
                          );
                        },
                        itemCount: LogLevel.values.length,
                      );
                    },
                    subtitle: Text(LogLevel.values[prefs.logLevel].name),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget get commonSettings {
    return Column(
      children: <Widget>[
        SettingsCategory(
          header: LocaleStrings.settings.personalizationTitle,
          children: [
            SettingsTile(
              icon: const Icon(Icons.brightness_medium_outlined),
              title: Text(LocaleStrings.settings.personalizationThemeMode),
              onTap: () {
                showDropdownSheet(
                  context: context,
                  itemBuilder: (context, index) {
                    final ThemeMode themeMode = ThemeMode.values[index];

                    if (themeMode == ThemeMode.system &&
                            UniversalPlatform.isWindows ||
                        UniversalPlatform.isLinux) {
                      return const SizedBox();
                    }
                    final bool selected = prefs.themeMode == themeMode;

                    return dropDownTile(
                      selected: selected,
                      title: Text(
                        getThemeModeName(themeMode),
                      ),
                      onTap: () {
                        prefs.themeMode = themeMode;
                        context.pop();
                      },
                    );
                  },
                  itemCount: ThemeMode.values.length,
                );
              },
              subtitle: Text(getThemeModeName(prefs.themeMode)),
            ),
            SettingsTile.withSwitch(
              value: prefs.useAmoled,
              onChanged: (value) => prefs.useAmoled = value,
              title: Text(LocaleStrings.settings.personalizationUseAmoled),
              icon: const Icon(Icons.brightness_2_outlined),
              activeColor: context.theme.accentColor,
            ),
            if (deviceInfo.canUseSystemAccent)
              SettingsTile.withSwitch(
                value: !deviceInfo.canUseSystemAccent
                    ? false
                    : !prefs.useCustomAccent,
                onChanged: (value) => prefs.useCustomAccent = !value,
                title: Text(
                  LocaleStrings.settings.personalizationUseCustomAccent,
                ),
                icon: const Icon(Icons.color_lens_outlined),
                activeColor: context.theme.accentColor,
              ),
            SettingsTile(
              title: Text(
                LocaleStrings.settings.personalizationCustomAccent,
              ),
              icon: const Icon(Icons.colorize_outlined),
              enabled: !deviceInfo.canUseSystemAccent || prefs.useCustomAccent,
              trailing: AnimatedOpacity(
                opacity: !deviceInfo.canUseSystemAccent || prefs.useCustomAccent
                    ? 1
                    : 0.5,
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  width: 60,
                  child: Icon(
                    Icons.brightness_1,
                    color: prefs.customAccent ?? Utils.defaultAccent,
                    size: 28,
                  ),
                ),
              ),
              onTap: () async {
                final int? result = await Utils.showNotesModalBottomSheet(
                  context: context,
                  builder: (context) => RGBColorPicker(
                    initialColor: context.theme.accentColor,
                  ),
                );

                if (result != null) {
                  if (result == -1) {
                    prefs.customAccent = null;
                  } else {
                    prefs.customAccent = Color(result);
                  }
                }
              },
            ),
            SettingsTile.withSwitch(
              value: prefs.useGrid,
              onChanged: (value) => prefs.useGrid = value,
              title: Text(LocaleStrings.settings.personalizationUseGrid),
              icon: const Icon(Icons.dashboard_outlined),
              activeColor: context.theme.accentColor,
            ),
            SettingsTile(
              icon: const Icon(Icons.translate),
              title: Text(LocaleStrings.settings.personalizationLocale),
              onTap: () {
                showDropdownSheet(
                  context: context,
                  initialIndex: context.savedLocale != null
                      ? context.supportedLocales.indexOf(context.savedLocale!) +
                          1
                      : 0,
                  scrollable: true,
                  itemBuilder: (context, index) {
                    final Locale? locale =
                        index == 0 ? null : context.supportedLocales[index - 1];
                    final String nativeName = locale != null
                        ? firstLetterToUppercase(
                            localeNativeNames[locale.languageCode]!,
                          )
                        : "Device default";
                    final bool selected = context.savedLocale == locale;

                    return dropDownTile(
                      title: Text(nativeName),
                      selected: selected,
                      onTap: () {
                        if (locale == null) {
                          context.deleteSaveLocale();
                        } else {
                          context.setLocale(locale);
                        }
                        setState(() {});
                        context.pop();
                      },
                    );
                  },
                  itemCount: context.supportedLocales.length + 1,
                );
              },
              subtitle: Text(
                context.savedLocale != null
                    ? firstLetterToUppercase(
                        localeNativeNames[context.savedLocale!.languageCode]!,
                      )
                    : "Device default",
              ),
            ),
            SettingsTile(
              icon: const Icon(Icons.autorenew),
              title: const Text("Change sync API url"),
              visible: AppInfo.supportsNotesApi,
              onTap: () async {
                final bool? status = await showInfoSheet(
                  context,
                  content:
                      "If you decide to change the sync api url every note will get deleted to prevent conflicts. Do this only if you know what are you doing.",
                  buttonAction: LocaleStrings.common.goOn,
                );
                if (status ?? false) {
                  Utils.showNotesModalBottomSheet(
                    context: context,
                    builder: (context) => SyncUrlEditor(),
                  );
                }
              },
            )
          ],
        ),
        SettingsCategory(
          header: LocaleStrings.settings.privacyTitle,
          children: [
            SettingsTile.withSwitch(
              value: prefs.masterPass != "",
              onChanged: (value) async {
                if (prefs.masterPass == "") {
                  final bool? status = await showInfoSheet(
                    context,
                    content:
                        LocaleStrings.settings.privacyUseMasterPassDisclaimer,
                    buttonAction: LocaleStrings.common.goOn,
                  );
                  if (status ?? false) showPassChallengeSheet(context);
                } else {
                  final bool? confirm =
                      await showPassChallengeSheet(context, false);

                  if (confirm ?? false) {
                    prefs.masterPass = "";

                    final List<Note> notes =
                        await helper.listNotes(ReturnMode.local);

                    setState(() => removingMasterPass = true);
                    context.basePage!.setBottomBarEnabled(false);
                    for (int i = 0; i < notes.length; i++) {
                      final Note note = notes[i];
                      if (note.lockNote) {
                        await helper.saveNote(
                          note.markChanged().copyWith(lockNote: false),
                        );
                      }
                    }
                    context.basePage!.setBottomBarEnabled(true);
                  }
                }
              },
              icon: const Icon(Icons.vpn_key_outlined),
              title: Text(LocaleStrings.settings.privacyUseMasterPass),
              activeColor: context.theme.accentColor,
              subtitle:
                  removingMasterPass ? const LinearProgressIndicator() : null,
            ),
            SettingsTile(
              icon: const Icon(MdiIcons.formTextboxPassword),
              title: Text(LocaleStrings.settings.privacyModifyMasterPass),
              enabled: prefs.masterPass != "",
              onTap: () async {
                final bool? confirm =
                    await showPassChallengeSheet(context, false);
                if (confirm ?? false) showPassChallengeSheet(context);
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<bool?> showInfoSheet(
    BuildContext context, {
    required String content,
    required String buttonAction,
  }) async {
    return await Utils.showNotesModalBottomSheet(
          context: context,
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(content),
              ),
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: Text(buttonAction),
                onTap: () {
                  context.pop(true);
                },
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<dynamic> showDropdownSheet({
    required BuildContext context,
    required IndexedWidgetBuilder itemBuilder,
    required int itemCount,
    int initialIndex = 0,
    bool scrollable = false,
  }) async {
    return Utils.showNotesModalBottomSheet(
      context: context,
      childHandlesScroll: scrollable,
      builder: (context) => scrollable
          ? ScrollablePositionedList.builder(
              itemBuilder: itemBuilder,
              itemCount: itemCount,
              initialScrollIndex: initialIndex,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                itemCount,
                (index) => itemBuilder(context, index),
              ),
            ),
    );
  }

  Widget dropDownTile({
    required Widget title,
    Widget? subtitle,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return ListTile(
      selected: selected,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      title: title,
      subtitle: subtitle,
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }

  String getThemeModeName(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.light:
        return LocaleStrings.settings.personalizationThemeModeLight;
      case ThemeMode.dark:
        return LocaleStrings.settings.personalizationThemeModeDark;
      case ThemeMode.system:
      default:
        return LocaleStrings.settings.personalizationThemeModeSystem;
    }
  }

  Future<bool?> showPassChallengeSheet(BuildContext context,
      [bool editMode = true]) async {
    return Utils.showNotesModalBottomSheet(
      context: context,
      builder: (context) => PassChallenge(
        editMode: editMode,
        onChallengeSuccess: () => context.pop(true),
        onSave: (text) async {
          prefs.masterPass = Utils.hashedPass(text);

          context.pop();
        },
      ),
    );
  }

  String firstLetterToUppercase(String origin) {
    return ReCase(origin).sentenceCase;
  }
}

extension _LogLevelName on LogLevel {
  String get name {
    return toString().split(".").last.sentenceCase;
  }
}
