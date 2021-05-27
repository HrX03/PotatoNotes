import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/data/model/list_content.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/internal/device_info.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/image/image_helper.dart';
import 'package:potato_notes/internal/utils.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MigrationTask {
  MigrationTask._();

  static Future<String> get v1DatabasePath async => join(
        DeviceInfo.isDesktop
            ? await databaseFactoryFfi.getDatabasesPath()
            : await databaseFactory.getDatabasesPath(),
        'notes_database.db',
      );

  static Future<bool> isMigrationAvailable(String path) async =>
      File(path).exists();

  static Future<List<Note>?> migrate(String? path) async {
    if (path == null) return null;

    final Database db = DeviceInfo.isDesktop
        ? await databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(readOnly: true),
          )
        : await databaseFactory.openDatabase(
            path,
            options: OpenDatabaseOptions(readOnly: true),
          );

    final List<Map<String, dynamic>> rawV1Notes = await db.query('notes');
    final List<Note> notes = [];

    final List<NoteV1Model> v1Notes = List.generate(rawV1Notes.length, (index) {
      return NoteV1Model(
        id: rawV1Notes[index]['id'] as int,
        title: rawV1Notes[index]['title'] as String,
        content: rawV1Notes[index]['content'] as String,
        isStarred: rawV1Notes[index]['isStarred'] as int,
        date: rawV1Notes[index]['date'] as int,
        color: rawV1Notes[index]['color'] as int,
        imagePath: rawV1Notes[index]['imagePath'] as String?,
        isList: rawV1Notes[index]['isList'] as int,
        listParseString: rawV1Notes[index]['listParseString'] as String?,
        reminders: rawV1Notes[index]['reminders'] as String?,
        hideContent: rawV1Notes[index]['hideContent'] as int,
        password: rawV1Notes[index]['password'] as String?,
        isDeleted: rawV1Notes[index]['isDeleted'] as int,
        isArchived: rawV1Notes[index]['isArchived'] as int,
      );
    });

    for (final NoteV1Model v1Note in v1Notes) {
      final List<ListItem> listItems = [];
      final List<String> rawListItems =
          v1Note.listParseString?.split("'..'") ?? [];
      final String id = Utils.generateId();

      for (int i = 0; i < rawListItems.length; i++) {
        final String rawListItem = rawListItems[i];
        final List<String> listItem = rawListItem.split("',,'");

        listItems.add(
          ListItem(
            id: i,
            text: listItem[1],
            status: int.parse(listItem[0]) == 1,
          ),
        );
      }

      SavedImage? savedImage;
      if (v1Note.imagePath != null) {
        final Response response = await dio.get<Uint8List>(
          v1Note.imagePath!,
          options: Options(responseType: ResponseType.bytes),
        );
        final File file = File(join(appInfo.tempDirectory.path, "$id.jpg"))
          ..create();
        await file.writeAsBytes(Utils.asList<int>(response.data));
        savedImage = await ImageHelper.copyToCache(file);
        await file.delete();
        imageQueue.addUpload(savedImage, id);
      }

      final Note note = Note(
        id: id,
        title: v1Note.title ?? "",
        content: v1Note.content != null && v1Note.isList == 0
            ? v1Note.content ?? ""
            : "",
        starred: v1Note.isStarred == 1,
        creationDate: DateTime.fromMillisecondsSinceEpoch(v1Note.date!),
        lastModifyDate: DateTime.now(),
        color: v1Note.color ?? 0,
        images: [if (savedImage != null) savedImage],
        list: v1Note.isList == 1,
        listContent: listItems,
        reminders: [],
        tags: [],
        hideContent: v1Note.hideContent == 1,
        lockNote: false,
        usesBiometrics: false,
        deleted: v1Note.isDeleted == 1,
        archived: v1Note.isArchived == 1,
        synced: false,
      );

      notes.add(note);
    }

    db.close();

    return notes;
  }
}

@immutable
class NoteV1Model {
  final int? id;
  final String? title;
  final String? content;
  final int? isStarred;
  final int? date;
  final int? color;
  final String? imagePath;
  final int? isList;
  final String? listParseString;
  final String? reminders;
  final int? hideContent;
  final String? pin;
  final String? password;
  final int? isDeleted;
  final int? isArchived;

  const NoteV1Model({
    this.id,
    this.title,
    this.content,
    this.isStarred,
    this.date,
    this.color,
    this.imagePath,
    this.isList,
    this.listParseString,
    this.reminders,
    this.hideContent,
    this.pin,
    this.password,
    this.isDeleted,
    this.isArchived,
  });
}
