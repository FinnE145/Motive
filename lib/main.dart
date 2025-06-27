import "package:flutter/material.dart";
//import "dart:ui";
import "dart:math";
//import "test_raw_points.dart";  // Import test raw points for debugging

// Used to store the user-set and dev-adjusted pen settings
class PenSettings {
  // WIDTH PARAMETERS
  double widthScale = 0.25;               // Overall pen size (set by user)
  double minWidth = 4.0;                  // Width that the pen starts at
  double maxWidth = 8.0;                  // Width that the pen is capped at
  double widthFactor = 1.0;               // How much the width increases with speed
  double widthSmoothingFactor = 10.0;     // The maximum percentage difference in width between previous points and the current point
  int widthSmoothingSample = 5;           // How many previous points to average for smoothing the width

  // SMOOTHING PARAMETERS
  double curveMaxErrorSm = 1.00;            // The maximum allowed distance between the smoothed and original points
  double curveAlphaSm = 2.0;                // How far away the control points are from the endpoints (0 = straight line)
  int tangentSampleIndexSm = 2;             // How far away the second point for calculating endpoint tangents should be

  double curveMaxErrorLg = 1.00;
  double curveAlphaLg = 1.0;
  int tangentSampleIndexLg = 1;
}

// Stores a point with width information
class DrawPoint {
  final Offset offset;  // The position of the point relative to the previous point
  final double width;   // The width of the point (currently not rendered, but still correctly calculated)

  DrawPoint(this.offset, {this.width = 4.0});
}

// Represents a cubic Bezier curve with width information
class BezierCurve {
  final Offset p0, p1, p2, p3;  // Start, end and control points of the cubic Bezier curve
  final double width;           // Width of the curve segment

  BezierCurve(this.p0, this.p1, this.p2, this.p3, {this.width = 4.0});
}

// Custom painter to render the drawing
class DrawingPainter extends CustomPainter {
  final List<BezierCurve?> curves;
  DrawingPainter(this.curves);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.blue
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;   // Outline rather than fill

    Paint debugPaint = Paint()
      ..color = Colors.red
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    Path path = Path();
    bool betweenStrokes = true;
    for (final curve in curves) {
      if (curve == null) {
        betweenStrokes = true;
        continue;
      }
      if (betweenStrokes) {
        // Start a new subpath at the beginning of a new stroke
        path.moveTo(curve.p0.dx, curve.p0.dy);
        betweenStrokes = false;
      }
      if (curve.p1 == Offset.zero && curve.p2 == Offset.zero && curve.p3 == Offset.zero) {
        // If the curve is just a single point, draw a line to it
        path.lineTo(curve.p0.dx, curve.p0.dy);
      } else {
        // Draw a cubic Bezier curve using the control points
        path.cubicTo(
          curve.p1.dx, curve.p1.dy,   // Control point 1
          curve.p2.dx, curve.p2.dy,   // Control point 2
          curve.p3.dx, curve.p3.dy,   // End point
        );
      }
    }
    paint.strokeWidth = (DrawingApp.penSettings.maxWidth + DrawingApp.penSettings.minWidth) / 2 * DrawingApp.penSettings.widthScale;    // Set blanket stroke width as calculated width is currently ignored
    canvas.drawPath(path, paint);
    //canvas.drawPoints(ui.PointMode.points, curves.expand((curve) => curve?.p1 != null && curve?.p2 != null ? [curve!.p1, curve.p2] : [Offset(0, 0)]).toList(), debugPaint);
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => oldDelegate.curves != curves;
}

// Main app class
class DrawingApp extends StatelessWidget {
  const DrawingApp({super.key});
  static final PenSettings penSettings = PenSettings();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Flutter Drawing",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const DrawingHomePage(),
    );
  }
}

// Main drawing page class
class DrawingHomePage extends StatefulWidget {
  const DrawingHomePage({super.key});

  @override
  State<DrawingHomePage> createState() => _DrawingHomePageState();
}

// Handles input, calculation, and rendering of pen strokes
class _DrawingHomePageState extends State<DrawingHomePage> {
  // Stores points for the current stroke (updated every pointer event)
  //final ValueNotifier<List<DrawPoint?>> _rawPointsNotifier = ValueNotifier<List<DrawPoint?>>(testRawPoints.map((e) => DrawPoint(e)).toList());
  final ValueNotifier<List<DrawPoint?>> _rawPointsNotifier = ValueNotifier<List<DrawPoint?>>([]);

  // Stores all final fitted curves (updated at end of each stroke)
  final List<BezierCurve?> _curves = [];

  // Add to raw points for current stroke
  void _addPoint(Offset point, {double width = 4.0}) {
    final raw = List<DrawPoint?>.from(_rawPointsNotifier.value);
    raw.add(DrawPoint(point, width: width));
    _rawPointsNotifier.value = raw;
  }

  // Fits the final raw points into curves and adds them to the list
  void _endStroke() {
    final raw = _rawPointsNotifier.value.whereType<DrawPoint>().toList();
    print("Raw points before simplification: ${raw.length}");
    double angleLengthIndex = averageAngle(raw) / pow(totalDistance(raw), 2) * 1000000;
    print("Angle-Length Index: $angleLengthIndex");
    //print(raw.map((e) => e.offset).toList());
    bool useSmallSettings = angleLengthIndex > 30;
    print("Using ${useSmallSettings ? "small" : "large"} settings");
    final curves = fitCubicBezier(raw, useSmallSettings);
    if (curves.isNotEmpty) {
      print("Fitted curves: ${curves.length} (${curves.length * 4} points stored - ${((1 - curves.length * 4 / raw.length)*100).toInt()}% compression)");
      _curves.addAll(curves);
    } else {
      // Create a curve with a single point if no curves were fitted (all other values are ignored in rendering)
      print("No curves fitted");
      _curves.addAll(raw.map((e) => BezierCurve(e.offset, Offset.zero, Offset.zero, Offset.zero, width: e.width)));
    }
    // Add a null curve to indicate the end of the stroke
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
        title: const Text("Draw with Stylus"),
      ),
      body: Stack(
        children: [
          Listener(
            onPointerDown: (details) {
              _addPoint(details.localPosition, width: (DrawingApp.penSettings.minWidth + details.delta.distance * DrawingApp.penSettings.widthFactor).clamp(DrawingApp.penSettings.minWidth, DrawingApp.penSettings.maxWidth) * DrawingApp.penSettings.widthScale);
            },
            onPointerMove: (details) {
              _addPoint(details.localPosition, width: (DrawingApp.penSettings.minWidth + details.delta.distance * DrawingApp.penSettings.widthFactor).clamp(DrawingApp.penSettings.minWidth, DrawingApp.penSettings.maxWidth) * DrawingApp.penSettings.widthScale);
            },
            onPointerUp: (details) {
              _endStroke();
            },
            child: RepaintBoundary(
              child: ValueListenableBuilder<List<DrawPoint?>>(
                valueListenable: _rawPointsNotifier,
                builder: (context, rawPoints, child) {
                  final allCurves = <BezierCurve?>[..._curves];
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
        tooltip: "Clear",
        child: const Icon(Icons.clear),
      ),
    );
  }
}

// Fits a list of points into cubic Bézier curves with a maximum error tolerance
List<BezierCurve> fitCubicBezier(List<DrawPoint> points, bool useSmallSettings) {
  // If there are not enough points, return an empty list
  if (points.length < 4) return [];

  final startPoint = points.first.offset;
  final endPoint = points.last.offset;

  double maxError = DrawingApp.penSettings.curveMaxErrorLg;
  double alpha = DrawingApp.penSettings.curveAlphaLg;
  int tangentSampleIndex = DrawingApp.penSettings.tangentSampleIndexLg;

  if (useSmallSettings) {
    maxError = DrawingApp.penSettings.curveMaxErrorSm;
    alpha = DrawingApp.penSettings.curveAlphaSm;
    tangentSampleIndex = DrawingApp.penSettings.tangentSampleIndexSm;
  }


  int startIndex = tangentSampleIndex;
  int endIndex = points.length - tangentSampleIndex - 1;

  if (tangentSampleIndex > points.length - 1) {
    startIndex = points.length - 2;         // The other point used to determine the start tangent is the 2nd to last point
    endIndex = 1;                           // The other point used to determine the end tangent is the 2nd point
  }

  // Estimate tangents at endpoints
  final startTangent = points[startIndex].offset - startPoint;
  final endTangent = endPoint - points[endIndex].offset;

  // Calculate control points by extending the tangents by [alpha]
  final p1 = startPoint + startTangent * alpha;
  final p2 = endPoint + endTangent * -alpha;

  // Find max distance from all points to the curve
  double maxDist = 0;
  int maxIndex = 0;
  for (int i = 0; i < points.length; i++) {
    double t = i / (points.length - 1);
    Offset curvePt = cubicBezierPoint(startPoint, p1, p2, endPoint, t);
    double dist = (curvePt - points[i].offset).distance;
    if (dist > maxDist) {
      maxDist = dist;
      maxIndex = i;
    }
  }

  if (maxDist <= maxError || points.length < 8) {
    // If the furthest distance is within the allowed error, return a single curve
    final avgWidth = points.map((e) => e.width).reduce((a, b) => a + b) / points.length;
    return [BezierCurve(startPoint, p1, p2, endPoint, width: avgWidth)];
  } else {
    // Otherwise, split at point of max error and fit recursively
    final left = points.sublist(0, maxIndex + 1);
    final right = points.sublist(maxIndex);
    return [
      ...fitCubicBezier(left, useSmallSettings),
      ...fitCubicBezier(right, useSmallSettings),
    ];
  }
}

/// Evaluates a cubic Bézier at t (0 < t < 1)
Offset cubicBezierPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  double mt = 1 - t;
  return p0 * (mt * mt * mt)
      + p1 * (3 * mt * mt * t)
      + p2 * (3 * mt * t * t)
      + p3 * (t * t * t);
}

double averageAngle(List<DrawPoint> points) {
  if (points.length < 3) return 0;

  double totalAngle = 0;
  int count = 0;

  for (int i = 1; i < points.length - 1; i++) {
    final prev = points[i - 1].offset;
    final curr = points[i].offset;
    final next = points[i + 1].offset;

    final v1 = (curr - prev);
    final v2 = (next - curr);

    if (v1.distance == 0 || v2.distance == 0) continue;
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final theta = acos((dot / (v1.distance * v2.distance)).clamp(-1.0, 1.0)).abs();

    totalAngle += theta;
    count++;
  }

  return count == 0 ? 0 : totalAngle / count;
}

double totalDistance(List<DrawPoint> points) {
  if (points.length < 2) return 0;

  double total = 0;
  for (int i = 1; i < points.length; i++) {
    total += (points[i].offset - points[i - 1].offset).distance;
  }
  return total;
}

void main() {
  runApp(const DrawingApp());
}