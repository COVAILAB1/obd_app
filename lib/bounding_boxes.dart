import 'package:flutter/material.dart';

class BoundingBoxes extends StatelessWidget {
  final List<dynamic> recognitions;
  final double previewH;
  final double previewW;
  final double screenH;
  final double screenW;
  final double Function(double) calculateDistance;
  final Future<void> Function(String, String) logEvent;

  const BoundingBoxes({
    Key? key,
    required this.recognitions,
    required this.previewH,
    required this.previewW,
    required this.screenH,
    required this.screenW,
    required this.calculateDistance,
    required this.logEvent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Check if any object is within collision distance
    bool hasCollisionWarning = recognitions.any((rec) {
      double w = rec["rect"]["w"] * screenW;
      double distance = calculateDistance(w);
      return distance <= 1.5;
    });

    return Stack(
      children: [
        // Existing bounding boxes
        ...recognitions.expand((rec) {
          var x = rec["rect"]["x"] * screenW;
          var y = rec["rect"]["y"] * screenH;
          double w = rec["rect"]["w"] * screenW;
          double h = rec["rect"]["h"] * screenH;

          double distance = calculateDistance(w);
          String distanceText = distance < 1
              ? "${(distance * 100).toStringAsFixed(2)} cm"
              : "${distance.toStringAsFixed(2)} m";

          double centerX = x + w / 2;
          double centerY = y + h / 2;

          // Determine box color based on distance
          Color boxColor;
          if (distance <= 1.5) {
            boxColor = Colors.red;
          } else if (distance <= 3.0) {
            boxColor = Colors.orange;
          } else {
            boxColor = Colors.yellow;
          }

          return [
            Positioned(
              left: x,
              top: y,
              width: w,
              height: h,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: boxColor,
                    width: distance <= 1.5 ? 4 : 3,
                  ),
                ),
              ),
            ),
            Positioned(
              left: centerX - 50,
              top: centerY - 20,
              child: Container(
                padding: const EdgeInsets.all(4),
                color: Colors.black.withOpacity(0.7),
                child: Text(
                  "${rec["detectedClass"]} ${(rec["confidenceInClass"] * 100).toStringAsFixed(0)}%\n"
                      "Distance: $distanceText",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ];
        }).toList(),

        // Collision warning overlay
        if (hasCollisionWarning)
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "⚠️ COLLISION WARNING ⚠️",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Additional pulsing warning indicator
        if (hasCollisionWarning)
          Positioned(
            top: 120,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Object too close - Keep safe distance!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}