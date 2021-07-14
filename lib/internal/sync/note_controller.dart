import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/internal/extensions.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/controller.dart';
import 'package:potato_notes/internal/utils.dart';

class NoteController extends Controller {
  Future<String> add(Note note) async {
    try {
      final String noteJson = json.encode(note.toSyncMap());
      final Map<String, dynamic> data = {
        'id': note.id,
        'content': noteJson,
        'last_changed': note.lastModifyDate.millisecondsSinceEpoch
      };
      final Response addResult = await dio.post(
        url("note"),
        data: data,
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      return handleResponse(addResult).toString();
    } on SocketException {
      throw "Could not connect to server";
    }
  }

  Future<String> delete(String id) async {
    try {
      final Response deleteResponse = await dio.delete(
        url("note/$id"),
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      return handleResponse(deleteResponse).toString();
    } on SocketException {
      throw "Could not connect to server";
    }
  }

  Future<String> deleteAll() async {
    try {
      final Response deleteResult = await dio.delete(
        url("note/all"),
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      return handleResponse(deleteResult).toString();
    } on SocketException {
      throw "Could not connect to server";
    }
  }

  Future<List<Note>> list(int lastUpdated) async {
    final List<Note> notes = [];
    try {
      final Response listResult = await dio.get(
        url("note?last_updated=$lastUpdated"),
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      handleResponse(listResult);
      final List<Map<String, dynamic>> _notes =
          Utils.asList<Map<String, dynamic>>(listResult.data);
      for (final Map<String, dynamic> _note in _notes) {
        final Note note = NoteX.fromSyncMap(jsonDecode(_note["content"] as String) as Map<String, dynamic>);
        notes.add(note.copyWith(synced: true));
      }
      return notes;
    } on SocketException {
      throw "Could not connect to server";
    }
  }

  Future<String> update(String id, Note note) async {
    try {
      final String noteJson = json.encode(note.toSyncMap());
      final Map<String, dynamic> data = {
        'content': noteJson,
        'last_changed': note.lastModifyDate.millisecondsSinceEpoch
      };

      final Response updateResult = await dio.patch(
        url("note/$id"),
        data: data,
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      return handleResponse(updateResult).toString();
    } on SocketException {
      throw "Could not connect to server";
    }
  }

  Future<List<String>> listDeleted(List<String> localIdList) async {
    try {
      final String idListJson = jsonEncode(localIdList);
      final Response listResult = await dio.post(
        url("note/deleted"),
        data: idListJson,
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      handleResponse(listResult);
      final List<String> idList = (listResult.data as List<dynamic>)
          .map((e) => e.toString())
          .toList();
      return idList;
    } on SocketException {
      throw "Could not connect to server";
    }
  }

  static Object? handleResponse(Response response) {
    switch (response.statusCode) {
      case 401:
        throw "Token is not valid";
      default:
        return response.data;
    }
  }

  @override
  String get prefix => "notes";
}
