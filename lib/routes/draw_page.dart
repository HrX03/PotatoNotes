import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:back_button_interceptor/back_button_interceptor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/internal/device_info.dart';
import 'package:potato_notes/internal/extensions.dart';
import 'package:potato_notes/internal/locales/locale_strings.g.dart';
import 'package:potato_notes/internal/logger_provider.dart';
import 'package:potato_notes/internal/note_color_palette.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/image/image_helper.dart';
import 'package:potato_notes/internal/utils.dart';
import 'package:potato_notes/widget/dialog_sheet_base.dart';
import 'package:potato_notes/widget/drawing_board.dart';
import 'package:potato_notes/widget/drawing_toolbar.dart';
import 'package:potato_notes/widget/fake_appbar.dart';

class DrawPage extends StatefulWidget {
  final Note note;
  final SavedImage? savedImage;

  const DrawPage({
    required this.note,
    this.savedImage,
  });

  @override
  _DrawPageState createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage>
    with TickerProviderStateMixin, LoggerProvider {
  BuildContext? _globalContext;
  final DrawingBoardController _controller = DrawingBoardController();
  final DrawingToolbarController _toolbarController =
      DrawingToolbarController();

  late AnimationController _appbarAc;
  late AnimationController _toolbarAc;

  final List<DrawingTool> _tools = [
    DrawingTool(
      icon: Icons.brush_outlined,
      title: LocaleStrings.drawing.toolsBrush,
      toolType: DrawTool.pen,
    ),
    DrawingTool(
      icon: MdiIcons.marker,
      title: LocaleStrings.drawing.toolsMarker,
      toolType: DrawTool.marker,
      color: NoteColorPalette.neutral().yellow.color,
      size: ToolSize.twelve,
    ),
    DrawingTool(
      icon: MdiIcons.eraserVariant,
      title: LocaleStrings.drawing.toolsEraser,
      toolType: DrawTool.eraser,
      size: ToolSize.thirtyTwo,
      allowColor: false,
    ),
  ];
  int _toolIndex = 0;

  String? _filePath;

  final GlobalKey _drawingKey = GlobalKey();
  final GlobalKey _appbarKey = GlobalKey();
  final GlobalKey _toolbarKey = GlobalKey();

  SavedImage? _savedImage;

  @override
  void initState() {
    super.initState();
    BackButtonInterceptor.add(exitPrompt);
    _appbarAc = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _toolbarAc = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _savedImage = widget.savedImage;
  }

  @override
  void dispose() {
    _appbarAc.dispose();
    _toolbarAc.dispose();
    BackButtonInterceptor.remove(exitPrompt);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _globalContext ??= context;

    final Animation<double> _curvedAppbarAc = CurvedAnimation(
      parent: _appbarAc,
      curve: decelerateEasing,
    );
    final Animation<double> _curvedToolbarAc = CurvedAnimation(
      parent: _toolbarAc,
      curve: decelerateEasing,
    );

    return Scaffold(
      appBar: FakeAppbar(
        child: AnimatedBuilder(
          animation: _appbarAc,
          builder: (context, _) {
            return FadeTransition(
              opacity: ReverseAnimation(_curvedAppbarAc),
              key: _appbarKey,
              child: AppBar(
                leading: BackButton(
                  onPressed: () => exitPrompt(true, null),
                ),
                actions: [
                  _ChangeNotifierBuilder<DrawingBoardController>(
                    changeNotifier: _controller,
                    builder: (context) {
                      return IconButton(
                        icon: const Icon(Icons.save_outlined),
                        padding: const EdgeInsets.all(0),
                        tooltip: LocaleStrings.common.save,
                        onPressed: !_controller.saved ? _saveImage : null,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
      extendBodyBehindAppBar: true,
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: GestureDetector(
          onScaleStart: _normalModePanStart,
          onScaleUpdate: _normalModePanUpdate,
          onScaleEnd: _normalModePanEnd,
          child: DrawingBoard(
            repaintKey: _drawingKey,
            controller: _controller,
            path: widget.savedImage?.path,
            color: Colors.grey[50],
          ),
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _toolbarAc,
        builder: (context, _) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: FadeTransition(
              opacity: ReverseAnimation(_curvedToolbarAc),
              key: _toolbarKey,
              child: DrawingToolbar(
                controller: _toolbarController,
                boardController: _controller,
                tools: _tools,
                toolIndex: _toolIndex,
                onIndexChanged: (value) => setState(() => _toolIndex = value),
                clearCanvas: () {
                  Utils.showModalBottomSheet(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: const RoundedRectangleBorder(),
                      elevation: 0,
                      title: Text(LocaleStrings.common.areYouSure),
                      content: const Text(
                          "This operation can't be undone. Continue?"),
                      actions: [
                        TextButton(
                          onPressed: () => context.pop(),
                          child: Text(LocaleStrings.common.cancel),
                        ),
                        TextButton(
                          onPressed: () {
                            _controller.clearCanvas();
                            context.pop();
                          },
                          child: Text(LocaleStrings.common.confirm),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _normalModePanStart(ScaleStartDetails details) {
    if (details.pointerCount > 1) return;

    _controller.saved = false;
    _toolbarController.closePanel();
    DrawObject object;

    switch (_tools[_toolIndex].toolType) {
      case DrawTool.marker:
        object = DrawObject(
          Paint()
            ..strokeCap = StrokeCap.square
            ..isAntiAlias = true
            ..color = _tools[_toolIndex].color.withOpacity(0.5)
            ..strokeWidth = _tools[_toolIndex].size
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
          [],
        );
        break;
      case DrawTool.eraser:
        object = DrawObject(
          Paint()
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true
            ..color = Colors.transparent
            ..blendMode = BlendMode.clear
            ..strokeWidth = _tools[_toolIndex].size
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
          [],
        );
        break;
      case DrawTool.pen:
      default:
        object = DrawObject(
          Paint()
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true
            ..color = _tools[_toolIndex].color
            ..strokeWidth = _tools[_toolIndex].size
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
          [],
        );
        break;
    }

    _controller.addObject(object);

    _controller.currentIndex = _controller.objects.length - 1;
    _controller.actionQueueIndex = _controller.currentIndex!;

    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset topLeft = box.localToGlobal(Offset.zero);

    final Offset point = details.focalPoint.translate(-topLeft.dx, -topLeft.dy);

    _controller.addPointToObject(_controller.currentIndex!, point);
  }

  void _normalModePanUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) return;

    final RenderBox appbarBox =
        _appbarKey.currentContext!.findRenderObject()! as RenderBox;
    Rect appbarRect =
        (appbarBox.localToGlobal(Offset.zero) & appbarBox.size).inflate(8);

    final RenderBox toolbarBox =
        _toolbarKey.currentContext!.findRenderObject()! as RenderBox;
    Rect toolbarRect =
        (toolbarBox.localToGlobal(Offset.zero) & toolbarBox.size).inflate(8);

    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset topLeft = box.localToGlobal(Offset.zero);

    appbarRect = appbarRect.shift(topLeft * -1);
    toolbarRect = toolbarRect.shift(topLeft * -1);
    final Offset point = details.focalPoint.translate(-topLeft.dx, -topLeft.dy);

    if (!_appbarAc.isAnimating) {
      if (appbarRect.contains(point)) {
        _appbarAc.forward();
      } else {
        _appbarAc.reverse();
      }
    }

    if (!_toolbarAc.isAnimating) {
      if (toolbarRect.contains(point)) {
        _toolbarAc.forward();
      } else {
        _toolbarAc.reverse();
      }
    }

    _controller.addPointToObject(_controller.currentIndex!, point);
  }

  void _normalModePanEnd(details) {
    _controller.currentIndex = null;
    _controller.backupObjects = List.from(_controller.objects);
    _appbarAc.reverse();
    _toolbarAc.reverse();
  }

  bool exitPrompt(bool _, RouteInfo? __) {
    final Uri? uri = _filePath != null ? Uri.file(_filePath!) : null;

    Future<void> _internal() async {
      if (!_controller.saved) {
        final bool? exit = await Utils.showModalBottomSheet(
          context: _globalContext!,
          builder: (context) => DialogSheetBase(
            title: Text(LocaleStrings.common.areYouSure),
            content: Text(LocaleStrings.drawing.exitPrompt),
            actions: [
              TextButton(
                onPressed: () => context.pop(),
                child: Text(LocaleStrings.common.cancel),
              ),
              TextButton(
                onPressed: () => context.pop(true),
                child: Text(LocaleStrings.common.exit),
              ),
            ],
          ),
        );

        if (exit != null) {
          Navigator.pop(_globalContext!, uri);
        }
      } else {
        Navigator.pop(_globalContext!, uri);
      }
    }

    _internal();

    return true;
  }

  Future<void> _saveImage() async {
    String drawing;
    final RenderRepaintBoundary box = _drawingKey.currentContext!
        .findRenderObject()! as RenderRepaintBoundary;

    final ui.Image image = await box.toImage();
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List pngBytes = byteData!.buffer.asUint8List();
    final DateTime now = DateTime.now();
    final String timestamp = DateFormat(
      "HH_mm_ss-MM_dd_yyyy",
      context.locale.toLanguageTag(),
    ).format(now);

    final Directory drawingsDirectory = DeviceInfo.isDesktop
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();

    drawing = "${drawingsDirectory.path}/drawing-$timestamp.png";
    if (_filePath == null) {
      _filePath = drawing;
    } else {
      drawing = _filePath!;
    }

    final File imgFile = File(drawing);
    await imgFile.writeAsBytes(pngBytes, flush: true);
    logger.d(drawing);

    if (_savedImage != null) {
      widget.note.images
          .removeWhere((savedImage) => savedImage.id == _savedImage!.id);
    }
    _savedImage = await ImageHelper.copyToCache(imgFile);

    widget.note.images.add(_savedImage!);
    helper.saveNote(widget.note.markChanged());

    _controller.saved = true;
  }
}

class _ChangeNotifierBuilder<T extends ChangeNotifier> extends StatefulWidget {
  final T changeNotifier;
  final WidgetBuilder builder;

  const _ChangeNotifierBuilder({
    required this.changeNotifier,
    required this.builder,
  });

  @override
  _ChangeNotifierBuilderState createState() => _ChangeNotifierBuilderState();
}

class _ChangeNotifierBuilderState extends State<_ChangeNotifierBuilder> {
  @override
  void initState() {
    super.initState();
    widget.changeNotifier.addListener(_update);
  }

  @override
  void dispose() {
    widget.changeNotifier.removeListener(_update);
    super.dispose();
  }

  void _update() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
