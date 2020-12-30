import 'package:flutter/material.dart';
import 'package:mobx/mobx.dart';
import 'package:potato_notes/data/model/saved_image.dart';

abstract class QueueItem {
  final String localPath;
  final SavedImage savedImage;

  QueueItem({
    @required this.localPath,
    @required this.savedImage,
  });

  @observable
  QueueItemStatus status = QueueItemStatus.PENDING;
}

enum QueueItemStatus {
  PENDING,
  ONGOING,
  COMPLETE,
}
