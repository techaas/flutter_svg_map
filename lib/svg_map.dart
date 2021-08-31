// Copyright 2021, Techaas.com. All rights reserved.
//
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';

part 'japan_map_helper.dart';

class SVGMap extends StatefulWidget {
  @override
  _SVGMapState createState() => _SVGMapState();
}

class MapShape {
  MapShape(strPath, this._label, this._color) : _path = parseSvgPathData(strPath);

  /// transforms a [_path] into [_transformedPath] using given [matrix]
  void transform(Matrix4 matrix) => _transformedPath = _path.transform(matrix.storage);

  final Path _path;
  Path? _transformedPath;
  final String _label;
  final Color _color;
}

class _SVGMapState extends State<SVGMap> {
  List<MapShape>? _shapes;

  late final ValueNotifier<Offset> notifier;

  @override
  initState() {
    super.initState();

    notifier = ValueNotifier(Offset.zero);
    notifier.addListener(() {
      debugPrint("notified: ${notifier.value}");
    });

    rootBundle.load('images/Japan_template_large.svg').then((ByteData data) {
      debugPrint('load: ${data.lengthInBytes}');

      final document = new XmlDocument.parse(utf8.decode(data.buffer.asUint8List()));
      final svgRoot = document.findAllElements('svg').first;
      final strokeRoot = svgRoot.findElements('g').first;
      final prefectures = strokeRoot.children;

      List<MapShape> shapes = [];
      prefectures.forEach((node) {
        final id = node.getAttribute('id');
        if (id != null) {
          // debugPrint("xnode: ${node.getAttribute('id')}");
          final paths = node.findAllElements('path');
          paths.forEach((element) {
            final data = element.getAttribute('d');
            // debugPrint('data: $data');
            final printName = _prefecture_name[_prefecture_id[id]];
            shapes.add(MapShape(data, printName!,
                (_emergency_state.contains(_prefecture_id[id])) ? Colors.orange : Colors.white));
          });
        }
      });

      setState(() => {_shapes = shapes});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => notifier.value = e.localPosition,
      onPointerMove: (e) => notifier.value = e.localPosition,
      child: CustomPaint(
        painter: SVGMapPainter(notifier, _shapes),
        child: SizedBox.expand(),
      ),
    );
  }
}

class SVGMapPainter extends CustomPainter {
  SVGMapPainter(this._notifier, this._shapes) : super(repaint: _notifier);
  final List<MapShape>? _shapes;

  final ValueNotifier<Offset> _notifier;
  final Paint _paint = Paint();
  Size _size = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (size != _size) {
      _size = size;
      final fs = applyBoxFit(BoxFit.contain, Size(1400, 1600), size);
      final r = Alignment.center.inscribe(fs.destination, Offset.zero & size);
      final matrix = Matrix4.translationValues(r.left, r.top, 0)
        ..scale(fs.destination.width / fs.source.width);
      if (_shapes != null) {
        for (var shape in _shapes!) {
          shape.transform(matrix);
        }
      }
      print('new size: $_size');
    }

    canvas
      ..clipRect(Offset.zero & size)
      ..drawColor(Colors.blueGrey, BlendMode.src);
    var selectedMapShape;
    if (_shapes != null) {
      for (var shape in _shapes!) {
        final path = shape._transformedPath;
        final selected = path!.contains(_notifier.value);
        _paint
          ..color = selected ? Colors.teal : shape._color
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, _paint);
        selectedMapShape ??= selected ? shape : null;

        _paint
          ..color = Colors.black
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
        canvas.drawPath(path, _paint);
      }
    }
    if (selectedMapShape != null) {
      _paint
        ..color = Colors.black
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, 12)
        ..style = PaintingStyle.fill;
      canvas.drawPath(selectedMapShape._transformedPath, _paint);
      _paint.maskFilter = null;

      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        fontSize: 20,
        fontFamily: 'Roboto',
      ))
        ..pushStyle(ui.TextStyle(
          color: Colors.yellow,
        ))
        ..addText(selectedMapShape._label);
      final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: size.width));
      canvas.drawParagraph(paragraph, _notifier.value.translate(0, -32));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
