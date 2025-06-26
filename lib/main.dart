import 'package:flutter/material.dart';

// Add DrawPoint class
class DrawPoint {
  final Offset offset;
  final double width;
  DrawPoint(this.offset, {this.width = 4.0});
}

// Represents a cubic Bézier curve segment
class BezierCurve {
  final Offset p0, p1, p2, p3;
  final double width;
  BezierCurve(this.p0, this.p1, this.p2, this.p3, {this.width = 4.0});
}

void main() {
  runApp(const DrawingApp());
}

class DrawingApp extends StatelessWidget {
  const DrawingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Drawing',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const DrawingHomePage(),
    );
  }
}

class DrawingHomePage extends StatefulWidget {
  const DrawingHomePage({super.key});

  @override
  State<DrawingHomePage> createState() => _DrawingHomePageState();
}

class _DrawingHomePageState extends State<DrawingHomePage> {
  // Store current raw stroke (updated every pointer event)
  final ValueNotifier<List<DrawPoint?>> _rawPointsNotifier = ValueNotifier<List<DrawPoint?>>([]);

  // Store all fitted curves (final, only updated at end of stroke)
  final List<BezierCurve?> _curves = [];

  // WIDTH PARAMETERS
  double widthScale = 1;                // Overall pen size

  double minWidth = 4.0;                // Width that the pen starts at
  double maxWidth = 8.0;                // Width that the pen is capped at
  double widthFactor = 1.0;             // How much the width increases with speed
  int widthSmoothingSample = 5;         // How many previous points to average for smoothing the width
  double widthSmoothingFactor = 0.10;   // The maximum percentage difference in width between previous points and the current point

  void _addPoint(Offset point, {double width = 4.0}) {
    // Add to raw points for current stroke
    final raw = List<DrawPoint?>.from(_rawPointsNotifier.value);
    raw.add(DrawPoint(point, width: width));
    _rawPointsNotifier.value = raw;
  }

  void _endStroke() {
    final raw = _rawPointsNotifier.value.whereType<DrawPoint>().toList();
    print('Raw points before simplification: ${raw.length}');
    final curves = fitCubicBezier(raw, 1);
    if (curves.isNotEmpty) {
      print('Fitted curves: ${curves.length} (${curves.length * 4} points stored - ${((1 - curves.length * 4 / raw.length)*100).toInt()}% compression)');
      _curves.addAll(curves);
    } else {
      print('No curves fitted');
      _curves.addAll(raw.map((e) => BezierCurve(e.offset, Offset.zero, Offset.zero, Offset.zero, width: e.width)));
    }
    _curves.add(null);
    _rawPointsNotifier.value = [null];
  }

  void _clear() {
    _rawPointsNotifier.value = [null];
    _curves.clear();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _rawPointsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw with Stylus'),
      ),
      body: Stack(
        children: [
          Listener(
            onPointerDown: (details) {
              _rawPointsNotifier.value = [];
              _addPoint(details.localPosition, width: (minWidth + details.delta.distance * widthFactor).clamp(minWidth, maxWidth)*widthScale);
            },
            onPointerMove: (details) {
              _addPoint(details.localPosition, width: (minWidth + details.delta.distance * widthFactor).clamp(minWidth, maxWidth)*widthScale);
            },
            onPointerUp: (details) {
              _endStroke();
            },
            child: RepaintBoundary(
              child: ValueListenableBuilder<List<DrawPoint?>>(
                valueListenable: _rawPointsNotifier,
                builder: (context, rawPoints, child) {
                  final allCurves = <BezierCurve?>[..._curves]
                    ;
                  if (rawPoints.isNotEmpty) {
                    final raw = rawPoints.whereType<DrawPoint>().toList();
                    // turn raw points into Bézier curves
                    if (raw.length >= 4) {
                      for (int i = 0; i < raw.length - 3; i++) {
                        final p0 = raw[i].offset;
                        final p1 = raw[i + 1].offset;
                        final p2 = raw[i + 2].offset;
                        final p3 = raw[i + 3].offset;
                        final width = (raw[i].width + raw[i + 1].width + raw[i + 2].width + raw[i + 3].width) / 4.0;
                        allCurves.add(BezierCurve(p0, p1, p2, p3, width: width));
                      }
                    }
                  }
                  return CustomPaint(
                    painter: DrawingPainter(allCurves),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _clear,
        tooltip: 'Clear',
        child: const Icon(Icons.clear),
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<BezierCurve?> curves;
  DrawingPainter(this.curves);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.blue
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    Path path = Path();
    bool betweenStrokes = true;
    for (final curve in curves) {
      if (curve == null) {
        betweenStrokes = true;
        continue;
      }
      if (betweenStrokes) {
        path.moveTo(curve.p0.dx, curve.p0.dy);
        betweenStrokes = false;
      }
      if (curve.p1 == Offset.zero && curve.p2 == Offset.zero && curve.p3 == Offset.zero) {
        path.lineTo(curve.p0.dx, curve.p0.dy);
      } else {
        path.cubicTo(
          curve.p1.dx, curve.p1.dy,
          curve.p2.dx, curve.p2.dy,
          curve.p3.dx, curve.p3.dy,
        );
      }
    }
    paint.strokeWidth = 4.0;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => oldDelegate.curves != curves;
}


// --- FitCurve package is used to fit cubic Bézier curves from raw points ---
List<BezierCurve> fitCubicBezier(List<DrawPoint> points, double maxError) {
  if (points.length < 4) return [];

  final p0 = points.first.offset;
  final p3 = points.last.offset;

  // Estimate tangents at endpoints
  final d0 = (points[1].offset - p0);
  final d3 = (p3 - points[points.length - 2].offset);

  double alpha = 0.3; // Heuristic for control point distance

  final p1 = p0 + d0 * alpha;
  final p2 = p3 + d3 * -alpha;

  // Find max distance from points to curve
  double maxDist = 0;
  int maxIndex = 0;
  for (int i = 0; i < points.length; i++) {
    double t = i / (points.length - 1);
    Offset curvePt = cubicBezierPoint(p0, p1, p2, p3, t);
    double dist = (curvePt - points[i].offset).distance;
    if (dist > maxDist) {
      maxDist = dist;
      maxIndex = i;
    }
  }

  if (maxDist <= maxError || points.length < 8) {
    final avgWidth = points.map((e) => e.width).reduce((a, b) => a + b) / points.length;
    return [BezierCurve(p0, p1, p2, p3, width: avgWidth)];
  } else {
    // Split at point of max error and fit recursively
    final left = points.sublist(0, maxIndex + 1);
    final right = points.sublist(maxIndex);
    return [
      ...fitCubicBezier(left, maxError),
      ...fitCubicBezier(right, maxError),
    ];
  }
}

/// Evaluates a cubic Bézier at t (0..1)
Offset cubicBezierPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  double mt = 1 - t;
  return p0 * (mt * mt * mt)
      + p1 * (3 * mt * mt * t)
      + p2 * (3 * mt * t * t)
      + p3 * (t * t * t);
}