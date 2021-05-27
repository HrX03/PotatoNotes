import 'dart:convert';
import 'dart:core';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:potato_notes/data/dao/note_helper.dart';
import 'package:potato_notes/data/dao/tag_helper.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/internal/extensions.dart';
import 'package:potato_notes/internal/logger_provider.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/controller.dart';
import 'package:potato_notes/internal/utils.dart';

import 'image/image_helper.dart';

class SyncRoutine with LoggerProvider {
  static const Set<String> _settingsToSync = {
    "custom_accent",
    "use_amoled",
    "use_grid",
    "use_custom_accent"
  };

  final List<Note> _localNotes = [];
  final List<Note> _addedNotes = [];
  final List<Note> _deletedNotes = [];
  final Map<Note, Map<String, dynamic>> _updatedNotes = {};
  final List<Tag> localTags = [];
  final List<Tag> _addedTags = [];
  final List<Tag> _deletedTags = [];
  final Map<Tag, Map<String, dynamic>> _updatedTags = {};

  SyncRoutine();

  final ValueNotifier<bool> _syncing = ValueNotifier(false);
  ValueNotifier<bool> get syncing => _syncing;

  Future<bool> _checkOnlineStatus() async {
    final url = Controller.note.url("ping");
    final Response pingResponse = await dio.get(url);
    if (pingResponse.statusCode != 200) {
      logger.e("Server did not respond with 200 on ping");
      return false;
    }
    if (pingResponse.data != "Pong!") {
      logger.e("Server did not respond with Pong!");
      return false;
    }
    return true;
  }

  Future<bool> checkLoginStatus() async {
    if (prefs.accessToken == null) {
      logger.d("Tried syncing without accesstoken");
      return false;
    }

    try {
      final Response securePingResponse = await dio.get(
        Controller.note.url("secure-ping"),
        options: Options(
          headers: {"Authorization": prefs.accessToken},
        ),
      );
      if (securePingResponse.statusCode == 401) {
        logger.e("Token is not valid");
        return false;
      }
      if (securePingResponse.statusCode != 200) {
        logger.e("Server did not respond with 200 on ping");
        return false;
      }
      if (securePingResponse.data != "Pong!") {
        logger.e("Server did not respond with Pong!");
        return false;
      }
      return true;
    } catch (e) {
      throw "Error when securely pinging server: $e";
    }
  }

  Future<void> sync() async {
    _syncing.value = true;
    await _syncNotes();
    _syncing.value = false;
    prefs.lastUpdated = DateTime.now().millisecondsSinceEpoch;
  }

  Future<bool> _syncNotes() async {
    // Check if the app is able to access the remote server
    final bool status = await _checkOnlineStatus();
    if (status != true) throw "Could not connect to server";
    final bool secureStatus = await checkLoginStatus();
    if (secureStatus != true) {
      throw "Not logged in!";
    }
    imageQueue.uploadQueue.clear();
    await imageQueue.fillUploadQueue();
    await imageQueue.process();
    // Receive and send changes from API
    await _sendSettingUpdates();

    // Fill the list of added, deleted and updated notes to create a local cache
    await _updateLists();

    _addedNotes.clear();
    _updatedNotes.clear();
    _deletedNotes.clear();
    _localNotes.clear();
    _addedTags.clear();
    _updatedTags.clear();
    _deletedTags.clear();
    localTags.clear();

    await _updateLists();

    // Send all of the note-related requests to the remote server
    try {
      await _sendNoteUpdates();
    } catch (e) {
      return false;
    }

    // Send all of the tag-related requests to the remote server
    try {
      await _sendTagUpdates();
    } catch (e) {
      return false;
    }

    _addedNotes.clear();
    _updatedNotes.clear();
    _deletedNotes.clear();
    _localNotes.clear();
    _addedTags.clear();
    _updatedTags.clear();
    _deletedTags.clear();
    localTags.clear();

    // Get the last time the client has updated
    final int lastUpdated = prefs.lastUpdated;

    // Get a list of tags which have been updated since the client updated
    try {
      final List<Tag> tags = await Controller.tag.list(lastUpdated);
      logger.i("Got these tags: ${tags.map((tag) => tag.id).join(",")}");
      for (final Tag tag in tags) {
        logger.i("Saving tag: $tag.id");
        await _saveSyncedTag(tag);
      }
    } catch (e) {
      logger.e(e.toString());
      throw "Failed to list tags: $e";
    }

    // Get a list of notes which have been updated since the client updated
    final List<Note> notes = await Controller.note.list(lastUpdated);
    logger.i("Got these notes: ${notes.map((note) => note.id).join(",")}");
    for (final Note note in notes) {
      logger.i("Saving note: ${note.id}");

      //TODO Add a way of disabling this when adding data saving setting
      /*for (SavedImage savedImage in note.images.data) {
          await ImageService.downloadImage(savedImage);
        }*/
      await _saveSyncedNote(note);
    }
    prefs.lastUpdated = DateTime.now().millisecondsSinceEpoch;
    await ImageHelper.handleDownloads(await helper.listNotes(ReturnMode.local));
    return true;
  }

  Future<bool> _addNote(Note note) async {
    try {
      await Controller.note.add(note);
      await _saveSyncedNote(note);
      logger.i("Added note: ${note.id}");
      return true;
    } catch (e) {
      logger.e("Failed to add note: $e");
      return false;
    }
  }

  Future<bool> _sendNoteUpdates() async {
    // Send the post requests to add new notes
    for (final Note note in _addedNotes) {
      if (await _addNote(note) == false) {
        return false;
      }
    }
    // Get list of notes which should be deleted on the client since they are deleted on the remote server
    try {
      final List<String> deletedIdList = await Controller.note
          .listDeleted(_localNotes.map((note) => note.id).toList());
      for (final String id in deletedIdList) {
        final Note localNote = _localNotes.firstWhere((note) => note.id == id);
        await helper.deleteNote(localNote);
        await helper
            .deleteNote(localNote.copyWith(id: "${localNote.id}-synced"));
        _updatedNotes.removeWhere((note, _delta) => note.id == localNote.id);
        _deletedNotes.removeWhere((note) => note.id == localNote.id);
      }
    } catch (e) {
      logger.e(e.toString());
      throw "Failed to list deleted notes: $e";
    }
    _updatedNotes.forEach((note, delta) async {
      try {
        await Controller.note.update(note.id, delta);
        await _saveSyncedNote(note);
        logger.i("Updated note: ${note.id}");
      } catch (e) {
        logger.e(e);
      }
    });
    for (final Note note in _deletedNotes) {
      final String localNoteId = note.id.replaceFirst("-synced", "");
      try {
        await Controller.note.delete(localNoteId);
        await _deleteSyncedNote(note);
        logger.i("Deleted note: $localNoteId");
      } catch (e) {
        logger.e(e.toString());
        throw "Failed to delete notes: $e";
      }
    }
    return true;
  }

  Future<bool> _sendTagUpdates() async {
    // Send the post requests to add new tags
    for (final Tag tag in _addedTags) {
      try {
        await Controller.tag.add(tag);
        await _saveSyncedTag(tag);
        logger.i("Added tag: ${tag.id}");
      } catch (e) {
        logger.e(e.toString());
        throw "Failed to add tags: $e";
      }
    }
    // Get list of tags which should be deleted on the client since they are deleted on the remote server
    try {
      final List<String> deletedIdList = await Controller.tag
          .listDeleted(localTags.map((tag) => tag.id).toList());
      for (final String id in deletedIdList) {
        final Tag localTag = localTags.firstWhere((tag) => tag.id == id);
        await tagHelper.deleteTag(localTag);
        await tagHelper
            .deleteTag(localTag.copyWith(id: "${localTag.id}-synced"));
        _updatedTags.removeWhere((tag, _delta) => tag.id == localTag.id);
        _deletedTags.removeWhere((tag) => tag.id == localTag.id);
      }
    } catch (e) {
      logger.e(e.toString());
      throw "Failed to list deleted tags: $e";
    }
    _updatedTags.forEach((tag, delta) async {
      try {
        await Controller.tag.update(tag.id, delta);
        await _saveSyncedTag(tag);
        logger.i("Updated tag: ${tag.id}");
      } catch (e) {
        logger.e(e);
        throw "Failed to update tags: $e";
      }
    });
    for (final Tag tag in _deletedTags) {
      final String localTagId = tag.id.replaceFirst("-synced", "");
      try {
        await Controller.tag.delete(localTagId);
        await _deleteSyncedTag(tag);
        logger.i("Deleted tag: $localTagId");
      } catch (e) {
        logger.e(e.toString());
        throw "Failed to delete tags: $e";
      }
    }
    return true;
  }

  Future<void> _sendSettingUpdates() async {
    Map<String, String> changedSettings;
    changedSettings = await Controller.setting.getChanged(prefs.lastUpdated);

    changedSettings.forEach((key, value) {
      final Object? original = prefs.getFromCache(key);
      switch (original.runtimeType) {
        case String:
          {
            sharedPrefs.setString(key, value);
            break;
          }
        case bool:
          {
            sharedPrefs.setBool(key, value == "true");
            break;
          }
        case double:
          {
            sharedPrefs.setDouble(key, double.parse(value));
            break;
          }
        case int:
          {
            sharedPrefs.setInt(key, int.parse(value));
            break;
          }
        case List:
          {
            final List<String> list = Utils.asList<String>(json.decode(value));
            sharedPrefs.setStringList(key, list);
            break;
          }
      }
    });

    final List<String> keys = sharedPrefs.changedKeys;

    for (final String key in keys) {
      if (_settingsToSync.contains(key) &&
          !changedSettings.keys.contains(key)) {
        try {
          logger.v("Preparing to save $key");
          Object? value = prefs.getFromCache(key);
          if (key == "tags") {
            value = json.encode(value);
          }
          await Controller.setting.set(key, value.toString());
          logger.v("Saved setting $key");
        } catch (e) {
          logger.e(e);
          throw "Failed to save setting: $e";
        }
      }
    }
    sharedPrefs.clearChangedKeys();
  }

  static Future<void> _saveSyncedNote(Note note) async {
    await helper.saveNote(note.copyWith(synced: true));
    final Note syncedNote = note.copyWith(id: "${note.id}-synced");
    await helper.saveNote(syncedNote);
  }

  static Future<void> _deleteSyncedNote(Note note) async {
    await helper.deleteNote(note);
  }

  static Future<void> _saveSyncedTag(Tag tag) async {
    await tagHelper.saveTag(tag);
    final Tag syncedTag = tag.copyWith(id: "${tag.id}-synced");
    await tagHelper.saveTag(syncedTag);
  }

  static Future<void> _deleteSyncedTag(Tag tag) async {
    await tagHelper.deleteTag(tag);
  }

  Future<void> _updateLists() async {
    _localNotes.clear();
    _localNotes.addAll(await helper.listNotes(ReturnMode.local));
    final List<Note> syncedNotes = await helper.listNotes(ReturnMode.synced);
    for (final Note localNote in _localNotes) {
      final int syncedIndex = syncedNotes.indexWhere(
          (syncedNote) => "${localNote.id}-synced" == syncedNote.id);
      if (syncedIndex == -1) {
        _addedNotes.add(localNote);
      } else {
        final Note syncedNote = syncedNotes.elementAt(syncedIndex);
        if (!localNote.synced) {
          _updatedNotes.putIfAbsent(
              localNote, () => _getNoteDelta(localNote, syncedNote));
        }
      }
    }
    if (syncedNotes.isNotEmpty) {
      for (final Note syncedNote in syncedNotes) {
        final int localIndex = _localNotes.indexWhere(
            (localNote) => "${localNote.id}-synced" == syncedNote.id);
        if (localIndex == -1) {
          _deletedNotes.add(syncedNote);
        }
      }
    }

    localTags.clear();
    localTags.addAll(await tagHelper.listTags(TagReturnMode.local));
    final List<Tag> syncedTags = await tagHelper.listTags(TagReturnMode.synced);
    for (final Tag localTag in localTags) {
      final int syncedIndex = syncedTags
          .indexWhere((syncedTag) => "${localTag.id}-synced" == syncedTag.id);
      if (syncedIndex == -1) {
        _addedTags.add(localTag);
      } else {
        final Tag syncedTag = syncedTags.elementAt(syncedIndex);
        if (syncedTag.lastModifyDate.millisecondsSinceEpoch <
            localTag.lastModifyDate.millisecondsSinceEpoch) {
          _updatedTags.putIfAbsent(
              localTag, () => _getTagDelta(localTag, syncedTag));
        }
      }
    }
    if (syncedTags.isNotEmpty) {
      for (final Tag syncedTag in syncedTags) {
        final int localIndex = localTags
            .indexWhere((localTag) => "${localTag.id}-synced" == syncedTag.id);
        if (localIndex == -1) {
          _deletedTags.add(syncedTag);
        }
      }
    }
  }

  Map<String, dynamic> _getNoteDelta(Note localNote, Note syncedNote) {
    final Map<String, dynamic> localMap = localNote.toSyncMap();
    final Map<String, dynamic> syncedMap = syncedNote.toSyncMap();
    final Map<String, dynamic> noteDelta = {};
    localMap.forEach((key, localValue) {
      if (localValue != syncedMap[key] &&
          (key != "note_id" && key != "synced")) {
        logger.d("$key:$localValue");
        noteDelta.putIfAbsent(key, () => localValue);
      }
    });
    return noteDelta;
  }

  Map<String, dynamic> _getTagDelta(Tag localTag, Tag syncedTag) {
    final Map<String, dynamic> localMap = Controller.tag.toSync(localTag);
    final Map<String, dynamic> syncedMap = Controller.tag.toSync(syncedTag);
    final Map<String, dynamic> tagDelta = {};
    localMap.forEach((key, localValue) {
      if (localValue != syncedMap[key] && (key != "id")) {
        logger.d("$key:$localValue");
        tagDelta.putIfAbsent(key, () => localValue);
      }
    });
    return tagDelta;
  }
}
