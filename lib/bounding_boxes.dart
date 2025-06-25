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
    return Stack(
      children: recognitions.expand((rec) {
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

        return [
          Positioned(
            left: x,
            top: y,
            width: w,
            height: h,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: distance < 1 ? Colors.red : Colors.yellow,
                  width: 3,
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
    );
  }
}