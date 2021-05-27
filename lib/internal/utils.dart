import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/auth_strings.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:potato_notes/data/dao/note_helper.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/internal/app_info.dart';
import 'package:potato_notes/internal/backup_delegate.dart';
import 'package:potato_notes/internal/constants.dart';
import 'package:potato_notes/internal/device_info.dart';
import 'package:potato_notes/internal/extensions.dart';
import 'package:potato_notes/internal/locales/locale_strings.g.dart';
import 'package:potato_notes/internal/notification_payload.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/image/blake/stub.dart';
import 'package:potato_notes/internal/sync/image/image_helper.dart';
import 'package:potato_notes/internal/themes.dart';
import 'package:potato_notes/routes/note_page.dart';
import 'package:potato_notes/widget/backup_password_prompt.dart';
import 'package:potato_notes/widget/bottom_sheet_base.dart';
import 'package:potato_notes/widget/dialog_sheet_base.dart';
import 'package:potato_notes/widget/dismissible_route.dart';
import 'package:potato_notes/widget/note_color_selector.dart';
import 'package:potato_notes/widget/pass_challenge.dart';
import 'package:potato_notes/widget/restore_confirmation_dialog.dart';
import 'package:potato_notes/widget/selection_bar.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/utils/utils.dart' as utils;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

class Utils {
  Utils._();

  static final OverlayEntry _loadingOverlayEntry = OverlayEntry(
    builder: (context) => const SizedBox.expand(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    ),
  );

  static void deleteNoteSafely(Note note) {
    ImageHelper.handleNoteDeletion(note);
    helper.deleteNote(note);
  }

  static void handleNotePagePop(Note note) {
    //ImageService.handleDeletes();
    //helper.listNotes(ReturnMode.LOCAL).then((notes) => {
    //      SyncRoutine.syncNote(notes.firstWhere((local) => local.id == note.id))
    //    });
  }

  static Future<bool?> showPassChallengeSheet(
    BuildContext context, {
    String? description,
  }) async {
    return showModalBottomSheet<bool>(
      context: context,
      builder: (context) => PassChallenge(
        onChallengeSuccess: () => context.pop(true),
        description: description,
      ),
    );
  }

  static Future<bool> showBiometricPrompt() async {
    try {
      return await LocalAuthentication().authenticate(
        localizedReason: "",
        biometricOnly: true,
        stickyAuth: true,
        androidAuthStrings: AndroidAuthMessages(
          signInTitle: LocaleStrings.common.biometricsPrompt,
          cancelButton: LocaleStrings.common.cancel,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  static Future<bool> showNoteLockDialog({
    required BuildContext context,
    required bool showLock,
    bool showBiometrics = false,
    String? description,
  }) async {
    if (showLock && prefs.masterPass != '') {
      bool status;

      final bool bioAuth = showBiometrics && !DeviceInfo.isDesktopOrWeb
          ? await Utils.showBiometricPrompt()
          : false;

      if (bioAuth) {
        status = bioAuth;
      } else {
        status = await Utils.showPassChallengeSheet(
              context,
              description: description,
            ) ??
            false;
      }

      return status;
    }

    return true;
  }

  static Future<String?> showBackupPasswordPrompt({
    required BuildContext context,
    bool confirmationMode = true,
  }) async {
    final String? password = await Utils.showModalBottomSheet(
      context: context,
      builder: (context) =>
          BackupPasswordPrompt(confirmationMode: confirmationMode),
    );

    return password;
  }

  static Future<T?> showModalBottomSheet<T extends Object?>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? backgroundColor,
    double? elevation,
    ShapeBorder? shape,
    Clip? clipBehavior,
    Color? barrierColor,
    bool enableDismiss = true,
  }) async {
    return context.push<T?>(
      BottomSheetRoute(
        child: builder(context),
        backgroundColor: backgroundColor,
        elevation: elevation,
        shape: shape,
        clipBehavior: clipBehavior,
        enableDismiss: enableDismiss,
      ),
    );
  }

  static Future<void> showAlertDialog({
    required BuildContext context,
    Widget? title,
    Widget? content,
    List<Widget>? Function(BuildContext)? actions,
  }) {
    return Utils.showModalBottomSheet(
      context: context,
      builder: (context) => DialogSheetBase(
        title: title,
        content: content,
        actions: actions?.call(context) ??
            [
              TextButton(
                onPressed: () => context.pop(),
                child: Text(LocaleStrings.common.ok),
              ),
            ],
      ),
    );
  }

  static void showLoadingOverlay(BuildContext context) =>
      context.overlay!.insert(_loadingOverlayEntry);
  static void hideLoadingOverlay(BuildContext context) =>
      _loadingOverlayEntry.remove();

  static String generateId() {
    return const Uuid().v4();
  }

  static SelectionOptions getSelectionOptionsForMode(ReturnMode mode) {
    return SelectionOptions(
      options: (context, notes) {
        final bool anyStarred = notes.any((item) => item.starred);
        final bool showUnpin = notes.firstOrNull?.pinned ?? false;

        return [
          SelectionOptionEntry(
            title: LocaleStrings.mainPage.selectionBarSelect,
            icon: Icons.check,
            value: 'select',
            showOnlyOnRightClickMenu: true,
          ),
          SelectionOptionEntry(
            title: LocaleStrings.mainPage.selectionBarSelectAll,
            icon: Icons.select_all_outlined,
            value: 'selectall',
            showOnlyOnRightClickMenu: true,
          ),
          if (mode == ReturnMode.normal)
            SelectionOptionEntry(
              title: anyStarred
                  ? LocaleStrings.mainPage.selectionBarRemoveFavourites
                  : LocaleStrings.mainPage.selectionBarAddFavourites,
              icon: anyStarred ? Icons.favorite : Icons.favorite_border,
              value: 'favourites',
            ),
          if (mode == ReturnMode.normal)
            SelectionOptionEntry(
              title: LocaleStrings.mainPage.selectionBarChangeColor,
              icon: Icons.color_lens_outlined,
              value: 'color',
            ),
          if (mode != ReturnMode.archive)
            SelectionOptionEntry(
              title: LocaleStrings.mainPage.selectionBarArchive,
              icon: Icons.inventory_2_outlined,
              value: 'archive',
            ),
          SelectionOptionEntry(
            title: mode == ReturnMode.trash
                ? LocaleStrings.mainPage.selectionBarPermaDelete
                : LocaleStrings.mainPage.selectionBarDelete,
            icon: Icons.delete_outline,
            value: mode == ReturnMode.trash ? 'perma_delete' : 'delete',
          ),
          if (mode != ReturnMode.normal)
            SelectionOptionEntry(
              icon: Icons.settings_backup_restore,
              title: LocaleStrings.common.restore,
              value: 'restore',
            ),
          if (AppInfo.supportsNotePinning)
            SelectionOptionEntry(
              icon: showUnpin ? MdiIcons.pinOffOutline : MdiIcons.pinOutline,
              title: showUnpin
                  ? LocaleStrings.mainPage.selectionBarUnpin
                  : LocaleStrings.mainPage.selectionBarPin,
              value: 'pin',
              oneNoteOnly: true,
            ),
          SelectionOptionEntry(
            title: LocaleStrings.mainPage.selectionBarSave,
            icon: Icons.save_alt_outlined,
            value: 'export',
            oneNoteOnly: true,
          ),
          /* SelectionOptionEntry(
            icon: Icons.share_outlined,
            title: LocaleStrings.mainPage.selectionBarShare,
            value: 'share',
            oneNoteOnly: true,
          ), */
        ];
      },
      onSelected: _onSelected,
    );
  }

  static Future<void> _onSelected(
      BuildContext context, List<Note> notes, String value) async {
    final state = context.selectionState;

    switch (value) {
      case 'select':
        state.selecting = true;
        state.addSelectedNote(notes.first);
        break;
      case 'selectall':
        state.selecting = true;
        final List<Note> notes = await helper.listNotes(state.noteKind);
        for (final Note note in notes) {
          state.addSelectedNote(note);
        }
        break;
      case 'favourites':
        final bool unlocked = await Utils.showNoteLockDialog(
          context: context,
          showLock: notes.any((n) => n.lockNote && !n.isEmpty),
          showBiometrics: notes.any((n) => n.usesBiometrics),
        );

        if (unlocked) {
          final bool anyStarred = notes.any((item) => item.starred);

          for (final Note note in notes) {
            if (anyStarred) {
              await helper.saveNote(
                note.markChanged().copyWith(starred: false),
              );
            } else {
              await helper.saveNote(
                note.markChanged().copyWith(starred: true),
              );
            }
          }

          state.closeSelection();
        }
        break;
      case 'color':
        final bool unlocked = await Utils.showNoteLockDialog(
          context: context,
          showLock: notes.any((n) => n.lockNote && !n.isEmpty),
          showBiometrics: notes.any((n) => n.usesBiometrics),
        );

        if (unlocked) {
          int? selectedColor;

          if (notes.length > 1) {
            final int color = notes.first.color;

            if (notes.every((item) => item.color == color)) {
              selectedColor = color;
            } else {
              selectedColor = 0;
            }
          } else {
            selectedColor = notes.first.color;
          }

          selectedColor = await Utils.showModalBottomSheet<int>(
            context: context,
            builder: (context) => NoteColorSelector(
              selectedColor: selectedColor!,
              onColorSelect: (color) {
                context.pop(color);
              },
            ),
          );

          if (selectedColor != null) {
            for (final Note note in notes) {
              await helper.saveNote(note.copyWith(color: selectedColor));
            }

            state.closeSelection();
          }
        }
        break;
      case 'archive':
        final bool archived = await Utils.deleteNotes(
          context: context,
          notes: notes,
          reason: LocaleStrings.mainPage.notesArchived(notes.length),
          archive: true,
        );

        if (archived) state.closeSelection();
        break;
      case 'delete':
        final List<Note> notesToTrash = notes.where((n) => !n.deleted).toList();

        final bool deleted = await Utils.deleteNotes(
          context: context,
          notes: List.from(notesToTrash),
          reason: LocaleStrings.mainPage.notesDeleted(notes.length),
        );

        if (deleted) state.closeSelection();
        break;
      case 'perma_delete':
        final List<Note> notesToBeDeleted =
            notes.where((n) => n.deleted).toList();

        final bool deleted = await Utils.deleteNotes(
          context: context,
          notes: List.from(notesToBeDeleted),
          reason: LocaleStrings.mainPage.notesPermaDeleted(notes.length),
          permaDelete: true,
        );

        if (deleted) state.closeSelection();
        break;
      case 'restore':
        final bool restored = await Utils.restoreNotes(
          context: context,
          notes: notes,
          reason: LocaleStrings.mainPage.notesRestored(notes.length),
        );

        if (restored) state.closeSelection();
        break;
      case 'pin':
        final bool unlocked = await Utils.showNoteLockDialog(
          context: context,
          showLock: notes.first.lockNote && !notes.first.pinned,
          showBiometrics: notes.first.usesBiometrics,
        );

        if (unlocked) {
          handlePinNotes(context, notes.first);

          state.closeSelection();
        }
        break;
      case 'export':
        final bool unlocked = await Utils.showNoteLockDialog(
          context: context,
          showLock: notes.any((n) => n.lockNote && !n.isEmpty),
          showBiometrics: notes.any((n) => n.usesBiometrics),
          description: notes.length > 1
              ? "Some notes are locked, master pass is required."
              : "The note is locked, master pass is required.",
        );

        if (unlocked) {
          final String? password = await Utils.showBackupPasswordPrompt(
            context: context,
            confirmationMode: false,
          );
          if (password != null) {
            Utils.showLoadingOverlay(context);
            final bool exported =
                await backupDelegate.saveNote(notes.first, password);
            Utils.hideLoadingOverlay(context);
            context.basePage?.hideCurrentSnackBar();
            context.basePage?.showSnackBar(
              SnackBar(
                content: Text(exported
                    ? "Note successfully exported."
                    : "Something went wrong while exporting."),
                behavior: SnackBarBehavior.floating,
                width: min(640, context.mSize.width - 32),
              ),
            );
          }

          state.closeSelection();
        }
        break;
      case 'share':
        final bool unlocked = await Utils.showNoteLockDialog(
          context: context,
          showLock: notes.first.lockNote,
          showBiometrics: notes.first.usesBiometrics,
        );

        if (unlocked) {
          Share.share(
            (notes.first.title.isNotEmpty ? "${notes.first.title}\n\n" : "") +
                notes.first.content,
          );

          state.closeSelection();
        }
        break;
    }
  }

  static Future<void> handlePinNotes(BuildContext context, Note note) async {
    if (note.pinned) {
      appInfo.notifications?.cancel(note.notificationId);
    } else {
      appInfo.notifications?.show(
        note.notificationId,
        note.title.isEmpty
            ? LocaleStrings.common.notificationDefaultTitle
            : note.title,
        note.content,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'pinned_notifications',
            LocaleStrings.common.notificationDetailsTitle,
            LocaleStrings.common.notificationDetailsDesc,
            color: Constants.defaultAccent,
            ongoing: true,
            priority: Priority.max,
          ),
          iOS: const IOSNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: const MacOSNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: json.encode(
          NotificationPayload(
            action: NotificationAction.pin,
            id: int.parse(note.id.split("-")[0], radix: 16).toUnsigned(31),
            noteId: note.id,
          ).toJson(),
        ),
      );
    }
  }

  static String getNameFromMode(ReturnMode mode, {int tagIndex = 0}) {
    switch (mode) {
      case ReturnMode.normal:
        return LocaleStrings.mainPage.titleNotes;
      case ReturnMode.archive:
        return LocaleStrings.mainPage.titleArchive;
      case ReturnMode.trash:
        return LocaleStrings.mainPage.titleTrash;
      case ReturnMode.favourites:
        return LocaleStrings.mainPage.titleFavourites;
      case ReturnMode.tag:
        if (prefs.tags.isNotEmpty) {
          return prefs.tags[tagIndex].name;
        } else {
          return LocaleStrings.mainPage.titleTag;
        }
      case ReturnMode.all:
      default:
        return LocaleStrings.mainPage.titleAll;
    }
  }

  static Future<bool> deleteNotes({
    required BuildContext context,
    required List<Note> notes,
    required String reason,
    bool archive = false,
    bool showAuthDialog = true,
    bool permaDelete = false,
  }) async {
    final bool lockSuccess = await Utils.showNoteLockDialog(
      context: context,
      showLock: notes.any((n) => n.lockNote && !n.isEmpty) && showAuthDialog,
      showBiometrics: notes.any((n) => n.usesBiometrics),
    );
    if (!lockSuccess) return false;

    for (final Note note in notes) {
      if (archive) {
        await helper.saveNote(
            note.markChanged().copyWith(deleted: false, archived: true));
      } else {
        if (permaDelete) {
          Utils.deleteNoteSafely(note);
        } else {
          await helper.saveNote(
              note.markChanged().copyWith(deleted: true, archived: false));
        }
      }
    }

    final List<Note> backupNotes = List.from(notes);

    context.basePage?.hideCurrentSnackBar();
    context.basePage?.showSnackBar(
      SnackBar(
        content: Text(reason),
        behavior: SnackBarBehavior.floating,
        width: min(640, context.mSize.width - 32),
        action: SnackBarAction(
          label: LocaleStrings.common.undo,
          onPressed: () async {
            for (final Note note in backupNotes) {
              await helper.saveNote(note);
            }
          },
        ),
      ),
    );

    return true;
  }

  static Future<bool> restoreNotes({
    required BuildContext context,
    required List<Note> notes,
    required String reason,
    bool archive = false,
    bool showAuthDialog = true,
  }) async {
    final bool lockSuccess = await Utils.showNoteLockDialog(
      context: context,
      showLock: notes.any((n) => n.lockNote && !n.isEmpty) && showAuthDialog,
      showBiometrics: notes.any((n) => n.usesBiometrics),
    );
    if (!lockSuccess) return false;

    for (final Note note in notes) {
      await helper.saveNote(
          note.markChanged().copyWith(deleted: false, archived: false));
    }

    final List<Note> backupNotes = List.from(notes);

    context.basePage?.hideCurrentSnackBar();
    context.basePage?.showSnackBar(
      SnackBar(
        content: Text(reason),
        behavior: SnackBarBehavior.floating,
        width: min(640, context.mSize.width - 32),
        action: SnackBarAction(
          label: LocaleStrings.common.undo,
          onPressed: () async {
            for (final Note note in backupNotes) {
              await helper.saveNote(note);
            }
          },
        ),
      ),
    );

    return true;
  }

  static Future<dynamic> showSecondaryRoute(
    BuildContext context,
    Widget route, {
    bool allowGestures = true,
    bool pushImmediate = false,
  }) async {
    return context.push(
      DismissiblePageRoute(
        builder: (context) => ScaffoldMessenger(
          child: route,
        ),
        allowGestures: allowGestures,
        pushImmediate: pushImmediate,
      ),
    );
  }

  static Widget quickIllustration(
      BuildContext context, Widget illustration, String text) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 128,
          child: Center(
            child: illustration,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          text,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: context.theme.iconTheme.color,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static Future<void> newNote(BuildContext context) async {
    final int currentLength =
        (await helper.listNotes(ReturnMode.normal)).length;
    final String id = generateId();

    await Utils.showSecondaryRoute(
      context,
      NotePage(
        note: NoteX.emptyNote.copyWith(id: id),
        focusTitle: true,
      ),
    );

    deleteLastNoteIfEmpty(context, currentLength, id);
  }

  static Future<void> deleteLastNoteIfEmpty(
    BuildContext context,
    int currentLength,
    String id,
  ) async {
    final List<Note> notes = await helper.listNotes(ReturnMode.normal);
    final int newLength = notes.length;

    if (newLength > currentLength) {
      final Note? lastNote = notes.firstWhereOrNull(
        (element) => element.id == id,
      );
      if (lastNote == null) return;
      Utils.handleNotePagePop(lastNote);

      if (lastNote.isEmpty) {
        Utils.deleteNotes(
          context: context,
          notes: [lastNote],
          reason: LocaleStrings.mainPage.deletedEmptyNote,
        );
      }
    }
  }

  static Future<void> newImage(BuildContext context, ImageSource source) async {
    Note note = NoteX.emptyNote;
    final File? image = await pickImage();

    if (image != null) {
      final SavedImage savedImage =
          await ImageHelper.copyToCache(File(image.path));
      note.images.add(savedImage);

      final int currentLength =
          (await helper.listNotes(ReturnMode.normal)).length;
      final String id = generateId();

      note = note.copyWith(id: id);

      await Utils.showSecondaryRoute(
        context,
        NotePage(
          note: note,
        ),
      );

      helper.saveNote(note.markChanged());

      deleteLastNoteIfEmpty(context, currentLength, id);
    }
  }

  static Future<void> newList(BuildContext context) async {
    final int currentLength =
        (await helper.listNotes(ReturnMode.normal)).length;
    final String id = generateId();

    await Utils.showSecondaryRoute(
      context,
      NotePage(
        note: NoteX.emptyNote.copyWith(id: id),
        openWithList: true,
      ),
    );

    deleteLastNoteIfEmpty(context, currentLength, id);
  }

  static Future<void> newDrawing(BuildContext context) async {
    final int currentLength =
        (await helper.listNotes(ReturnMode.normal)).length;
    final String id = generateId();

    await Utils.showSecondaryRoute(
      context,
      NotePage(
        note: NoteX.emptyNote.copyWith(id: id),
        openWithDrawing: true,
      ),
    );

    deleteLastNoteIfEmpty(context, currentLength, id);
  }

  static Future<void> importNotes(BuildContext context) async {
    final String? pickedFile = await Utils.pickFile(
      allowedExtensions: ['note'],
    );
    if (pickedFile == null || p.extension(pickedFile) != ".note") return;
    final MetadataExtractionResult? extractionResult =
        await BackupDelegate.extractMetadataFromFile(pickedFile);

    late final RestoreResultStatus status;
    if (extractionResult != null) {
      final bool? confirmation = await Utils.showModalBottomSheet<bool>(
        context: context,
        builder: (context) =>
            RestoreConfirmationDialog(metadata: extractionResult.metadata),
      );

      if (confirmation != true) return;

      final String? password =
          await Utils.showBackupPasswordPrompt(context: context);
      if (password == null) return;

      Utils.showLoadingOverlay(context);
      final RestoreResult result =
          await backupDelegate.restoreNote(extractionResult, password);
      if (result.status == RestoreResultStatus.success) {
        final Note note = result.notes.first;
        final List<Tag> tags = result.tags;

        if (!await helper.noteExists(note)) {
          await helper.saveNote(note);
          for (final Tag tag in tags) {
            await tagHelper.saveTag(tag);
          }
          status = RestoreResultStatus.success;
        } else {
          status = RestoreResultStatus.alreadyExists;
        }
      } else {
        status = result.status;
      }
      Utils.hideLoadingOverlay(context);
    } else {
      status = RestoreResultStatus.wrongFormat;
    }

    context.scaffoldMessenger.removeCurrentSnackBar();
    context.scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(Utils.getMessageFromRestoreStatus(status)),
        behavior: SnackBarBehavior.floating,
        width: min(640, context.mSize.width - 32),
      ),
    );
  }

  static Future<File?> pickImage() async {
    String? path;

    if (DeviceInfo.isDesktop) {
      final XFile? image = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: 'images',
            extensions: [
              'png',
              'jpg',
              'jpeg',
              'bmp',
            ],
          ),
        ],
      );

      path = image?.path;
    } else {
      final PickedFile? image =
          await ImagePicker().getImage(source: ImageSource.gallery);

      path = image?.path;
    }

    return path != null ? File(path) : null;
  }

  static Future<String?> pickFile({
    List<String>? allowedExtensions,
    String? initialDirectory,
  }) async {
    final dynamic asyncFile = DeviceInfo.isDesktop
        ? await openFile(
            acceptedTypeGroups: [
              XTypeGroup(
                extensions: allowedExtensions,
              ),
            ],
            initialDirectory: initialDirectory,
          )
        : (await FilePicker.platform.pickFiles())?.files.first;

    if (asyncFile == null) return null;

    return asyncFile.path as String;
  }

  static Future<List<String>?> pickFiles({
    List<String>? allowedExtensions,
    String? initialDirectory,
  }) async {
    final List<dynamic>? asyncFiles = DeviceInfo.isDesktop
        ? await openFiles(
            acceptedTypeGroups: [
              XTypeGroup(
                extensions: allowedExtensions,
              ),
            ],
            initialDirectory: initialDirectory,
          )
        : (await FilePicker.platform.pickFiles(allowMultiple: true))?.files;

    if (asyncFiles == null) return null;

    return asyncFiles.map((e) => e.path as String).toList();
  }

  static Future<bool> launchUrl(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final bool canLaunchLink = await canLaunch(url);

    if (canLaunchLink) {
      return launch(url, headers: headers);
    }

    return false;
  }

  static List<T> asList<T>(dynamic obj) {
    return List<T>.from(obj as List<dynamic>);
  }

  static Map<K, V> asMap<K, V>(dynamic obj) {
    return Map<K, V>.from(obj as Map<dynamic, dynamic>);
  }

  static String hashedPass(String pass) {
    final Blake2 blake = Blake2();
    blake.updateWithString(pass);
    return utils.hex(blake.digest());
  }

  static Color getMainColorFromTheme() {
    final MediaQueryData data =
        MediaQueryData.fromWindow(WidgetsBinding.instance!.window);
    final bool isDarkSystemTheme = data.platformBrightness == Brightness.dark;
    final ThemeMode themeMode = prefs.themeMode;
    final bool useAmoled = prefs.useAmoled;

    if (themeMode == ThemeMode.system && isDarkSystemTheme ||
        themeMode == ThemeMode.dark) {
      return useAmoled ? Themes.blackColor : Themes.darkColor;
    }

    return Themes.lightColor;
  }

  static String getMessageFromRestoreStatus(RestoreResultStatus status) {
    switch (status) {
      case RestoreResultStatus.success:
        return LocaleStrings.settings.backupRestoreRestoreStatusSuccess;
      case RestoreResultStatus.wrongFormat:
        return LocaleStrings.settings.backupRestoreRestoreStatusWrongFormat;
      case RestoreResultStatus.wrongPassword:
        return LocaleStrings.settings.backupRestoreRestoreStatusWrongPassword;
      case RestoreResultStatus.alreadyExists:
        return LocaleStrings.settings.backupRestoreRestoreStatusAlreadyExists;
      case RestoreResultStatus.unknown:
        return LocaleStrings.settings.backupRestoreRestoreStatusUnknown;
    }
  }
}

class SuspendedCurve extends Curve {
  /// Creates a suspended curve.
  const SuspendedCurve(
    this.startingPoint, {
    this.curve = Curves.easeOutCubic,
  });

  /// The progress value at which [curve] should begin.
  ///
  /// This defaults to [Curves.easeOutCubic].
  final double startingPoint;

  /// The curve to use when [startingPoint] is reached.
  final Curve curve;

  @override
  double transform(double t) {
    assert(t >= 0.0 && t <= 1.0);
    assert(startingPoint >= 0.0 && startingPoint <= 1.0);

    if (t < startingPoint) {
      return t;
    }

    if (t == 1.0) {
      return t;
    }

    final double curveProgress = (t - startingPoint) / (1 - startingPoint);
    final double transformed = curve.transform(curveProgress);
    return lerpDouble(startingPoint, 1, transformed)!;
  }
}
