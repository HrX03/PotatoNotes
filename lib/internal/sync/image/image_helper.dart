import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:image/image.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/image/blake/stub.dart';
import 'package:potato_notes/internal/utils.dart';

import 'download_queue_item.dart';

class ImageHelper {
  static const int jpegQuality = 60;
  static const int maxHeight = 2048;
  static const int maxBlurHashHeight = 100;

  static Future<void> handleDownloads(List<Note> changedNotes) async {
    imageQueue.downloadQueue.clear();
    for (final Note note in changedNotes) {
      if (note.images.isNotEmpty) {
        for (final SavedImage image in note.images) {
          if (!image.existsLocally) {
            imageQueue.addDownload(image, note.id);
          }
        }
      }
    }
    await imageQueue.processDownloads();
  }

  static Future<SavedImage> copyToCache(File file) async {
    final SavedImage savedImage = SavedImage.empty();
    final String path =
        join(appInfo.tempDirectory.path, savedImage.id + extension(file.path));
    file.copy(path);
    savedImage.storageLocation = prefs.accessToken != null
        ? StorageLocation.sync
        : StorageLocation.local;
    final Size _size = getImageSize(file);
    savedImage.width = _size.width.toDouble();
    savedImage.height = _size.height.toDouble();
    savedImage.fileExtension = extension(file.path);

    return savedImage;
  }

  static String generateImageHash(Uint8List rawBytes) {
    final logger = Logger("ImageHelper");
    final Blake2 blake2b = Blake2();
    blake2b.update(rawBytes);
    final Uint8List rawDigest = blake2b.digest();
    final String hash =
        rawDigest.map((n) => n.toRadixString(16).toString()).join();
    logger.d(hash);
    return hash;
  }

  static Size getImageSize(File file) {
    return ImageSizeGetter.getSize(FileInput(file));
  }

  static String generateBlurHash(Image image) {
    final String hash = BlurHash.encode(image).hash;
    return hash;
  }

  static Image compressImage(Uint8List rawBytes) {
    final Image image = decodeImage(rawBytes)!;
    // Default height of compressed images
    Image resized;
    // Ensure we dont enlarge the picture since the resize algorithm makes it look ugly then
    if (image.height > maxHeight) {
      resized = copyResize(image, height: maxHeight);
    } else {
      resized = image;
    }
    return resized;
  }

  static Image compressForBlur(Image image) {
    // Default height of compressed images
    Image resized;
    // Ensure we dont enlarge the picture since the resize algorithm makes it look ugly then
    if (image.height > maxBlurHashHeight) {
      resized = copyResize(image, height: maxBlurHashHeight);
    } else {
      resized = image;
    }
    return resized;
  }

  static File saveImage(Image image, String path) {
    final File imageFile = File(path);
    imageFile.writeAsBytesSync(encodeJpg(image, quality: jpegQuality));
    return imageFile;
  }

  static DownloadQueueItem? getDownloadItem(SavedImage savedimage) {
    final int index = imageQueue.downloadQueue
        .indexWhere((e) => e.savedImage.id == savedimage.id);
    if (index == -1) {
      return null;
    } else {
      return imageQueue.downloadQueue[index];
    }
  }

  static void handleNoteDeletion(Note note) {
    for (final SavedImage image in note.images) {
      imageQueue.addDelete(image);
    }
  }

  static String processImage(String jsonParameters) {
    final logger = Logger("ImageHelper");
    final Map<String, String> parameters =
        Utils.asMap<String, String>(json.decode(jsonParameters));
    final Map<String, String> data = {};
    final Uint8List rawBytes = File(parameters["original"]!).readAsBytesSync();
    logger.d("Hashing image");
    data["hash"] = generateImageHash(rawBytes);
    logger.d("Resizing image");
    final Image compressedImage = compressImage(rawBytes);
    data["width"] = compressedImage.width.toString();
    data["height"] = compressedImage.height.toString();
    logger.d("generating blurhash");
    final String blurHash = generateBlurHash(compressForBlur(compressedImage));
    data["blurhash"] = blurHash;
    logger.d("Saving image");
    saveImage(
        compressedImage, "${parameters["tempDirectory"]}/${data["hash"]}.jpg");
    return jsonEncode(data);
  }
}
