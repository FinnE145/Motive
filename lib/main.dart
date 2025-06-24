import 'package:flutter/material.dart';

// Add DrawPoint class
class DrawPoint {
  final Offset offset;
  final double width;
  DrawPoint(this.offset, {this.width = 4.0});
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
  final ValueNotifier<List<DrawPoint?>> _pointsNotifier = ValueNotifier<List<DrawPoint?>>([]);

  // WIDTH PARAMETERS
  double widthScale = 1;            // Overall pen size

  double minWidth = 2.0;            // Width that the pen starts at
  double maxWidth = 8.0;            // Width that the pen is capped at
  double widthFactor = 0.5;         // How much the width increases with speed
  int widthSmoothingSample = 1;     // How many previous points to average for smoothing the width
  double widthSmoothingFactor = 0.25;  // The maximum percentagedifference in width between previous points and the current point

  double skippedDistance = 0;



  void _addPoint(Offset point, {double width = 4.0}) {
    final points = List<DrawPoint?>.from(_pointsNotifier.value);
    if (points.length > widthSmoothingSample) {
      final prevPointsAvg = points.reversed.whereType<DrawPoint>().take(widthSmoothingSample).map((p) => p.width).reduce((a, b) => a + b)/widthSmoothingSample;
      if ((width - prevPointsAvg).abs() / prevPointsAvg > widthSmoothingFactor) {
        width = prevPointsAvg * (1 + widthSmoothingFactor * (width > prevPointsAvg ? 1 : -1));
      }
    }
    points.add(DrawPoint(point, width: width));
    _pointsNotifier.value = points;
  }

  void _endStroke() {
    final points = List<DrawPoint?>.from(_pointsNotifier.value)..add(null);
    _pointsNotifier.value = points;
  }

  void _clear() {
    _pointsNotifier.value = [];
  }

  @override
  void dispose() {
    _pointsNotifier.dispose();
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
              skippedDistance += details.delta.distanceSquared;
              if (skippedDistance < 2.56) {
                return;
              }
              skippedDistance = 0;
              _addPoint(details.localPosition, width: (minWidth + details.delta.distance * widthFactor).clamp(minWidth, maxWidth)*widthScale);
            },
            onPointerMove: (details) {
              skippedDistance += details.delta.distanceSquared;
              if (skippedDistance < 2.56) {
                return;
              }
              skippedDistance = 0;
              _addPoint(details.localPosition, width: (minWidth + details.delta.distance * widthFactor).clamp(minWidth, maxWidth)*widthScale);
            },
            onPointerUp: (details) {
              _endStroke();
            },
            child: RepaintBoundary(
              child: ValueListenableBuilder<List<DrawPoint?>>(
                valueListenable: _pointsNotifier,
                builder: (context, points, child) {
                  return CustomPaint(
                    painter: DrawingPainter(points),
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

// Update DrawingPainter to use DrawPoint
class DrawingPainter extends CustomPainter {
  final List<DrawPoint?> points;
  DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        paint.strokeWidth = points[i]!.width;
        canvas.drawLine(points[i]!.offset, points[i + 1]!.offset, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => oldDelegate.points != points;
}
