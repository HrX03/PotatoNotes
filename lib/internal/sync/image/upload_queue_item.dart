import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobx/mobx.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/controller.dart';
import 'package:potato_notes/internal/sync/image/queue_item.dart';
import 'package:potato_notes/internal/utils.dart';

import 'image_helper.dart';

class UploadQueueItem extends QueueItem {
  final String noteId;
  final StorageLocation storageLocation;

  UploadQueueItem({
    required this.noteId,
    required String localPath,
    required SavedImage savedImage,
    this.storageLocation = StorageLocation.local,
  }) : super(localPath: localPath, savedImage: savedImage);

  @action
  Future<void> process(String tempDirectory) async {
    status.value = QueueItemStatus.ongoing;
    final Map<String, String> data = {
      "original": localPath,
      "tempDirectory": tempDirectory
    };
    final String resultJson =
        await compute(ImageHelper.processImage, jsonEncode(data));
    final Map<String, String> result =
        Utils.asMap<String, String>(json.decode(resultJson));
    savedImage.hash = result["hash"];
    savedImage.blurHash = result["blurhash"];
    savedImage.width = double.parse(result["width"]!);
    savedImage.height = double.parse(result["height"]!);
    return;
  }

  @action
  Future<void> uploadImage({
    Map<String, dynamic> headers = const {},
  }) async {
    final File file = File(localPath);
    status.value = QueueItemStatus.ongoing;
    final int length = await file.length();
    final formData =
        FormData.fromMap({'file': await MultipartFile.fromFile(localPath)});
    final response = await dio.request(
      Controller.files.url("put/${savedImage.hash}.jpg"),
      data: formData,
      onSendProgress: (count, total) {
        progress.value = count / total;
      },
      options: Options(
        method: "PUT",
        headers: Map.from(headers)
          ..addAll({
            'content-length': length.toString(),
            'content-type': 'image/jpg',
          })
          ..addAll(Controller.tokenHeaders),
      ),
    );
    print(response.data.toString());
    status.value = QueueItemStatus.complete;
    savedImage.uploaded = true;
  }
}
