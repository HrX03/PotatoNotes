import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/controller.dart';
import 'package:potato_notes/internal/sync/note_controller.dart';
import 'package:potato_notes/internal/utils.dart';
import 'package:recase/recase.dart';

class TagController extends Controller {
  Future<String> add(Tag tag) async {
    try {
      final String tagJson = json.encode(toSync(tag));
      final Response addResult = await dio.post(
        url("tag"),
        data: tagJson,
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      return NoteController.handleResponse(addResult).toString();
    } on SocketException {
      throw "Could not connect to server";
    } catch (e) {
      rethrow;
    }
  }

  Future<String> delete(String id) async {
    try {
      final Response deleteResponse = await dio.delete(
        url("tag/$id"),
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      return NoteController.handleResponse(deleteResponse).toString();
    } on SocketException {
      throw "Could not connect to server";
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Tag>> list(int lastUpdated) async {
    try {
      final Response listResult = await dio.get(
        url("tag?last_updated=$lastUpdated"),
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      final List<Map<String, dynamic>> body =
          Utils.asList<Map<String, dynamic>>(listResult.data);
      final List<Tag> tags = body.map((map) {
        final Tag tag = fromSync(jsonEncode(map["content"] as String) as Map<String, dynamic>);
        return tag;
      }).toList();
      return tags.map((tag) => tag).toList();
    } on SocketException {
      throw "Could not connect to server";
    } catch (e) {
      rethrow;
    }
  }

  Future<String> update(String id, Map<String, dynamic> tagDelta) async {
    try {
      final String deltaJson = jsonEncode(tagDelta);
      final Response updateResult = await dio.patch(
        url("tag/$id"),
        data: deltaJson,
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      return NoteController.handleResponse(updateResult).toString();
    } on SocketException {
      throw "Could not connect to server";
    } catch (e) {
      rethrow;
    }
  }

  Future<List<String>> listDeleted(List<String> localIdList) async {
    try {
      final String idListJson = jsonEncode(localIdList);
      final Response listResult = await dio.post(
        url("tag/deleted"),
        data: idListJson,
        options: Options(
          headers: Controller.tokenHeaders,
        ),
      );
      NoteController.handleResponse(listResult);
      final List<dynamic> data = listResult.data as List<dynamic>;
      return data.map((id) => id.toString()).toList();
    } on SocketException {
      throw "Could not connect to server";
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> toSync(Tag tag) {
    final Map<String, dynamic> jsonMap = tag.toJson();
    final Map<String, dynamic> newMap = {};
    jsonMap.forEach((key, value) {
      final dynamic newValue = value;
      final String newKey = ReCase(key).snakeCase;
      newMap.putIfAbsent(newKey, () => newValue);
    });
    return newMap;
  }

  Tag fromSync(Map<String, dynamic> jsonMap) {
    final Map<String, dynamic> newMap = {};
    jsonMap.forEach((key, value) {
      final Object? newValue = value;
      final String newKey = ReCase(key).camelCase;
      newMap.putIfAbsent(newKey, () => newValue);
    });
    return Tag.fromJson(newMap);
  }

  @override
  String get prefix => "notes";
}
