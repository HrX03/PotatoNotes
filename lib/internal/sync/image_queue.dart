import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:potato_notes/data/dao/note_helper.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/internal/logger_provider.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/image/upload_queue_item.dart';
import 'package:potato_notes/internal/utils.dart';

import 'image/delete_queue_item.dart';
import 'image/download_queue_item.dart';
import 'image/queue_item.dart';

class ImageQueue extends ChangeNotifier with LoggerProvider {
  List<QueueItem> get queue => List.from(downloadQueue)..addAll(uploadQueue);

  final List<UploadQueueItem> uploadQueue = [];
  final List<DeleteQueueItem> deleteQueue = [];
  final List<DownloadQueueItem> downloadQueue = [];

  ImageQueue() {
    deleteQueue.addAll(deleteQueueFromPrefs());
  }

  void addUpload(SavedImage data, String noteId) {
    final UploadQueueItem item = UploadQueueItem(
        localPath: data.path,
        noteId: noteId,
        savedImage: data,
        storageLocation: data.storageLocation);
    uploadQueue.add(item);
    notifyListeners();
  }

  void addDelete(SavedImage data) {
    if (data.storageLocation != StorageLocation.sync || !data.uploaded) return;
    final DeleteQueueItem item = DeleteQueueItem(
      localPath: data.path,
      savedImage: data,
      storageLocation: data.storageLocation,
    );
    deleteQueue.add(item);
    saveToPrefs();
  }

  void addDownload(SavedImage data, String noteId) {
    final DownloadQueueItem item = DownloadQueueItem(
        savedImage: data, noteId: noteId, localPath: data.path);
    downloadQueue.add(item);
    notifyListeners();
  }

  //This method can only be run if all images have been processed (e.g. have a hash)
  Future<bool> hasDuplicates(
    SavedImage data, {
    NoteHelper? noteHelper,
  }) async {
    final _helper = noteHelper ?? helper;
    final List<Note> notes = await _helper.listNotes(ReturnMode.local);

    for (final Note note in notes) {
      if (note.images.indexWhere(
              (e) => e.id != data.id && e.uploaded && e.hash == data.hash) !=
          -1) return true;
    }
    return false;
  }

  Future<void> fillUploadQueue() async {
    final List<Note> notes = await helper.listNotes(ReturnMode.local);
    for (final Note note in notes) {
      note.images
          .where((image) => !image.uploaded)
          .forEach((image) => addUpload(image, note.id));
    }
  }

  Future<void> processDownloads() async {
    logger.d("DownloadQueue has ${downloadQueue.length} items queued");
    logger.d("Started processing downloads");
    await Future.wait(downloadQueue.map((item) => item.downloadImage()));
    /*for (final DownloadQueueItem item in downloadQueue) {
      await item.downloadImage();
    }*/
    for (final DownloadQueueItem item in downloadQueue) {
      if (item.status.value == QueueItemStatus.complete) await updateItem(item);
    }
    downloadQueue.removeWhere(
      (item) => item.status.value == QueueItemStatus.complete,
    );
    logger.d(
      "DownloadQueue now contains ${downloadQueue.length} items",
    );
  }

  Future<void> process() async {
    final String tempDirectory = appInfo.tempDirectory.path;

    logger.d("UploadQueue has ${uploadQueue.length} items queued");
    logger.d("Started processing uploads");
    await Future.wait(
        uploadQueue.map((item) => uploadItem(item, tempDirectory)));

    //Update items that are uploaded in notes
    for (final UploadQueueItem item in uploadQueue) {
      if (item.status.value != QueueItemStatus.complete) continue;
      await updateItem(item);
    }

    logger.d("DeleteQueue has ${downloadQueue.length} items queued");
    logger.d("Started processing uploads");
    for (final item in deleteQueue) {
      if (await hasDuplicates(item.savedImage)) {
        item.status.value = QueueItemStatus.complete;
      } else {
        await item.deleteImage();
      }
    }

    //Remove the items from the queue
    uploadQueue
        .removeWhere((item) => item.status.value == QueueItemStatus.complete);
    deleteQueue
        .removeWhere((item) => item.status.value == QueueItemStatus.complete);

    logger.d("UploadQueue now contains ${uploadQueue.length} items");
    logger.d("DeleteQueue now contains ${deleteQueue.length} items");
  }

  Future<void> deleteItem(DeleteQueueItem item) async {
    if (await hasDuplicates(item.savedImage)) {
      item.status.value = QueueItemStatus.complete;
    } else {
      await item.deleteImage();
    }
  }

  Future<void> uploadItem(UploadQueueItem item, String tempDirectory) async {
    await item.process(tempDirectory);
    if (item.storageLocation == StorageLocation.sync &&
        await hasDuplicates(item.savedImage)) {
      item.savedImage.uploaded = true;
      item.status.value = QueueItemStatus.complete;
      return;
    } else {
      await item.uploadImage();
    }
  }

  Future<void> updateItem(QueueItem item) async {
    final List<Note> notes = await helper.listNotes(ReturnMode.local);
    for (final Note note in notes) {
      for (int i = 0; i < note.images.length; i++) {
        if (note.images[i].id != item.savedImage.id) continue;
        note.images[i] = item.savedImage;
      }
      await helper.saveNote(note);
    }
  }

  void saveToPrefs() {
    prefs.deleteQueue = jsonEncode(deleteQueue);
  }

  List<DeleteQueueItem> deleteQueueFromPrefs() {
    if (prefs.deleteQueue == null || (prefs.deleteQueue?.isEmpty ?? true)) {
      return [];
    }

    //logger.d(prefs.deleteQueue);
    final List<DeleteQueueItem> queue =
        Utils.asList<Map<String, dynamic>>(json.decode(prefs.deleteQueue!))
            .map((i) => DeleteQueueItem.fromJson(i))
            .toList();
    return queue;
  }
}
