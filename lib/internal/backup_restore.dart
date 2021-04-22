import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:moor/moor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/data/model/image_list.dart';
import 'package:potato_notes/data/model/list_content.dart';
import 'package:potato_notes/data/model/reminder_list.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/data/model/tag_list.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/utils.dart';

class BackupRestore {
  static Future<void> saveNote(Note note, String password) async {
    final Map<String, dynamic> payload = {
      'note': note.toJson(serializer: const _TypeAwareValueSerializer()),
      'password': password,
      'buildNumber': appInfo.packageInfo.buildNumberInt,
    };

    await compute(_rawSaveNote, json.encode(payload));
  }

  static Future<void> _rawSaveNote(String payload) async {
    final Map<String, dynamic> data =
        json.decode(payload) as Map<String, dynamic>;

    final Note note = Note.fromJson(
      data['note']! as Map<String, dynamic>,
      serializer: const _TypeAwareValueSerializer(),
    );
    final String password = data['password']! as String;
    final int buildNumber = data['buildNumber']! as int;

    final Directory baseDir = await getTemporaryDirectory();
    final Directory noteDir =
        Directory(p.join(baseDir.path, "${note.id}-export"));
    await _createNoteFolderStructure(
      note: note,
      baseDir: noteDir,
      buildNumber: buildNumber,
    );

    final Directory docsDir = await getApplicationDocumentsDirectory();
    final Directory outDir = Directory(p.join(
      docsDir.path,
      "LeafletBackups",
    ));
    final String formattedDate =
        DateFormat("dd_MM_yyyy-HH_mm_ss").format(DateTime.now());
    final ZipByteEncoder encoder = ZipByteEncoder()
      ..create()
      ..addDirectory(noteDir, includeDirName: false);
    final List<int> fileBytes = encoder.close();
    File(p.join(outDir.path, "note-$formattedDate.note"))
        .writeAsBytes(await _encryptBytes(fileBytes, password));

    await noteDir.delete(recursive: true);
  }

  static Future<File> createBackup({
    required List<Note> notes,
    required String password,
    String? name,
    ValueChanged<int>? onProgress,
  }) async {
    final Directory tempDir = await getTemporaryDirectory();
    final DateTime now = DateTime.now();
    final String formattedDate = DateFormat("dd_MM_yyyy-HH_mm_ss").format(now);
    final Directory baseDir =
        Directory(p.join(tempDir.path, "$formattedDate-backup"));
    await baseDir.create();

    final Map<String, dynamic> metadata = {};
    final List<String> noteIds = [];
    for (int i = 0; i < notes.length; i++) {
      final Note note = notes[i];
      final Directory noteDir =
          Directory(p.join(baseDir.path, "${note.id}-export"));
      noteIds.add(note.id);
      await _createNoteFolderStructure(
        note: note,
        baseDir: noteDir,
        buildNumber: appInfo.packageInfo.buildNumberInt,
      );
      onProgress?.call(i + 1);
    }
    final String _name = name ?? formattedDate;
    metadata["name"] = _name;
    metadata["notes"] = noteIds;
    metadata["note_count"] = notes.length;
    metadata["creation_date"] = now.millisecondsSinceEpoch;
    metadata["app_version"] = appInfo.packageInfo.buildNumberInt;
    final File metadataFile = File(p.join(baseDir.path, "meta.data"));
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('    ').convert(metadata),
    );

    final Directory docsDir = await getApplicationDocumentsDirectory();
    final Directory outDir = Directory(p.join(
      docsDir.path,
      "LeafletBackups",
    ));
    final ZipByteEncoder encoder = ZipByteEncoder()
      ..create()
      ..addDirectory(baseDir, includeDirName: false)
      ..close();
    final List<int> fileBytes = encoder.close();
    File(p.join(outDir.path, "backup-$_name.backup"))
        .writeAsBytes(await _encryptBytes(fileBytes, password));

    await baseDir.delete(recursive: true);

    return File(p.join(outDir.path, "backup-$_name.backup"));
  }

  static Future<void> _createNoteFolderStructure({
    required Note note,
    required Directory baseDir,
    required int buildNumber,
  }) async {
    await baseDir.create();
    final DateTime now = DateTime.now();
    final File noteDataFile = File(p.join(baseDir.path, "note.data"));
    final Map<String, dynamic> noteData = {};
    noteData["note"] = note.toJson();
    noteData["creation_date"] = now.millisecondsSinceEpoch;
    noteData["app_version"] = buildNumber;

    await noteDataFile.writeAsString(
      const JsonEncoder.withIndent('    ').convert(noteData),
    );

    if (note.images.isNotEmpty) {
      final Directory imagesDirectory =
          Directory(p.join(baseDir.path, "images"));
      await imagesDirectory.create();
      for (final SavedImage image in note.images) {
        await File(image.path).copy(
          p.join(imagesDirectory.path, "${image.id}${image.fileExtension}"),
        );
      }
    }
  }

  static Future<Note?> restoreNote(String path, String password) async {
    final Map<String, dynamic> payload = {
      'path': path,
      'password': password,
    };

    final String rawNote = await compute(_rawRestoreNote, json.encode(payload));
    if (rawNote != "null") {
      final Note note = Note.fromJson(
        json.decode(rawNote) as Map<String, dynamic>,
        serializer: const _TypeAwareValueSerializer(),
      );
      await helper.saveNote(note);
    }
  }

  static Future<String> _rawRestoreNote(String payload) async {
    final Map<String, dynamic> data =
        json.decode(payload) as Map<String, dynamic>;

    final String path = data['path']! as String;
    final String password = data['password']! as String;

    final Directory imagesDir = await getTemporaryDirectory();
    final File zipFile = File(path);
    final List<int> fileBytes = await zipFile.readAsBytes();
    final List<ArchiveFile> files = ZipDecoder()
        .decodeBytes(await _decryptBytes(fileBytes, password))
        .files;
    Note? returnNote;

    for (final ArchiveFile file in files) {
      if (file.isFile) {
        if (file.name == "note.data") {
          final String content = utf8.decode(file.content as List<int>);
          final Map<String, dynamic> decodedContent =
              Utils.asMap<String, dynamic>(json.decode(content));
          final Map<String, dynamic> noteJson =
              Utils.asMap<String, dynamic>(decodedContent["note"]);
          final Note note = Note.fromJson(
            noteJson,
            serializer: const _TypeAwareValueSerializer(),
          );
          returnNote = note;
        } else if (file.name.startsWith("images/")) {
          final File image = File(
            p.join(
              imagesDir.path,
              file.name.replaceAll("images/", ""),
            ),
          );
          await image.writeAsBytes(file.content as List<int>);
        }
      }
    }

    return returnNote?.toJsonString(
          serializer: const _TypeAwareValueSerializer(),
        ) ??
        "null";
  }

  static Future<List<int>> _encryptBytes(
      List<int> origin, String password) async {
    final keySalt = _generateNonce();
    final key = await _deriveKey(password, keySalt);

    final aes = AesGcm.with256bits();
    final ciphertext = await aes.encrypt(origin, secretKey: key);

    return [
      ...keySalt,
      ...ciphertext.nonce,
      ...ciphertext.mac.bytes,
      ...ciphertext.cipherText,
    ];
  }

  static Future<List<int>> _decryptBytes(
      List<int> origin, String password) async {
    final keySalt = origin.sublist(0, 16);
    final aesNonce = origin.sublist(16, 28);
    final macBytes = origin.sublist(28, 44);
    final payload = origin.sublist(44);

    final key = await _deriveKey(password, keySalt);

    final aes = AesGcm.with256bits();
    final plaintext = await aes.decrypt(
      SecretBox(
        payload,
        nonce: aesNonce,
        mac: Mac(macBytes),
      ),
      secretKey: key,
    );

    return plaintext;
  }

  static List<int> _generateNonce([int length = 16]) => List.generate(
        length,
        (index) => Random.secure().nextInt(255),
      );

  static Future<SecretKey> _deriveKey(String password, List<int> nonce) async {
    final kdf = Pbkdf2(
      bits: 256,
      iterations: 100000,
      macAlgorithm: Hmac.sha512(),
    );
    final key = await kdf.deriveKey(
      secretKey: SecretKey(password.codeUnits),
      nonce: nonce,
    );

    return key;
  }
}

class _TypeAwareValueSerializer extends ValueSerializer {
  const _TypeAwareValueSerializer();

  @override
  T fromJson<T>(dynamic jsonContent) {
    if (jsonContent == null) {
      return null as T;
    }

    final _typeList = <T>[];

    if (_typeList is List<DateTime?>) {
      return DateTime.fromMillisecondsSinceEpoch(jsonContent as int) as T;
    }

    if (_typeList is List<double> && jsonContent is int) {
      return jsonContent.toDouble() as T;
    }

    // blobs are encoded as a regular json array, so we manually convert that to
    // a Uint8List
    if (_typeList is List<Uint8List> && jsonContent is! Uint8List) {
      final asList = (jsonContent as List).cast<int>();
      return Uint8List.fromList(asList) as T;
    }

    if (jsonContent is List<dynamic> && _typeList is List<List<SavedImage>>) {
      return const ImageListConverter().mapToDart(json.encode(jsonContent))
          as T;
    }

    if (jsonContent is List<dynamic> && _typeList is List<List<ListItem>>) {
      return const ListContentConverter().mapToDart(json.encode(jsonContent))
          as T;
    }

    if (jsonContent is List<dynamic> && _typeList is List<List<DateTime>>) {
      return const ReminderListConverter().mapToDart(json.encode(jsonContent))
          as T;
    }

    if (jsonContent is List<dynamic> && _typeList is List<List<String>>) {
      return const TagListConverter().mapToDart(json.encode(jsonContent)) as T;
    }

    return jsonContent as T;
  }

  @override
  dynamic toJson<T>(T value) {
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }

    return value;
  }
}

class ZipByteEncoder {
  late String zipPath;
  late OutputStream _output;
  late ZipEncoder _encoder;

  static const int store = 0;
  static const int gzip = 1;

  void zipDirectory(Directory dir, {String? filename, int? level}) {
    level ??= gzip;
    create(level: level);
    addDirectory(dir, includeDirName: false, level: level);
    close();
  }

  void create({int? level}) {
    _output = OutputStream();
    _encoder = ZipEncoder();
    _encoder.startEncode(_output, level: level);
  }

  void addDirectory(Directory dir, {bool includeDirName = true, int? level}) {
    final List<FileSystemEntity> files = dir.listSync(recursive: true);
    for (final FileSystemEntity file in files) {
      if (file is! File) {
        continue;
      }

      final f = file;
      final dirName = p.basename(dir.path);
      final relPath = p.relative(f.path, from: dir.path);
      addFile(f, includeDirName ? ('$dirName/$relPath') : relPath, level);
    }
  }

  void addFile(File file, [String? filename, int? level = gzip]) {
    final InputFileStream fileStream = InputFileStream.file(file);
    final ArchiveFile archiveFile = ArchiveFile.stream(
        filename ?? p.basename(file.path), file.lengthSync(), fileStream);

    if (level == store) {
      archiveFile.compress = false;
    }

    archiveFile.lastModTime = file.lastModifiedSync().millisecondsSinceEpoch;
    archiveFile.mode = file.statSync().mode;

    _encoder.addFile(archiveFile);
    fileStream.close();
  }

  void addArchiveFile(ArchiveFile file) {
    _encoder.addFile(file);
  }

  List<int> close() {
    _encoder.endEncode();
    return _output.getBytes();
  }
}
