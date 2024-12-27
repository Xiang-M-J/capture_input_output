import 'dart:math';

import 'package:flutter/material.dart';

// class StreamAudioVisualizer extends StatelessWidget {
//   final Stream<List<double>> audioStream;
//   final Size size;
//   const StreamAudioVisualizer({super.key, required this.size, required this.audioStream});
//
//   @override
//   Widget build(BuildContext context) {
//     return StreamBuilder<List<double>>(
//       stream: audioStream,
//       builder: (context, snapshot) {
//         if (snapshot.hasData) {
//           return CustomPaint(
//             size: size,
//             painter: WaveformPainter(snapshot.data!),
//           );
//         } else {
//           return const Center(child: Text('Loading audio data...'));
//         }
//       },
//     );
//   }
// }


class WaveformPainter extends CustomPainter {
  final List<double> waveform;
  final int pointSpace;
  final int frameSize;
  int maxPoints = 0;
  int framePoints = 0;
  int samplePoints = 2 * 16000;

  WaveformPainter(this.waveform, this.pointSpace, this.frameSize){
   maxPoints = samplePoints ~/ pointSpace;
   framePoints = max(frameSize ~/ pointSpace, 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();

    for(var i = 0; i < waveform.length; i += pointSpace){
      double x = i * size.width / samplePoints;
      double y = ((1 - waveform[i]) * size.height / 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class WaveformPainterXY extends CustomPainter {
  final List<double> X;
  final List<double> Y;
  // List<double> X = [];
  // List<double> Y = [];
  WaveformPainterXY(this.X, this.Y);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    for(var i = 0; i < Y.length; i ++){

      if (i == 0) {
        path.moveTo(X[i], Y[i]);
      } else {
        path.lineTo(X[i], Y[i]);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}



class WaveformPainter2 extends CustomPainter {
  final List<double> waveform;
  int offset;
  WaveformPainter2(this.waveform, this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();

    // for (int i = 0; i < waveform.length; i++) {
    //   final x = i * size.width / waveform.length;
    //   final y = ((1 - waveform[i]) * size.height / 2);
    //   if (i == 0) {
    //     path.moveTo(x, y);
    //   } else {
    //     path.lineTo(x, y);
    //   }
    // }
    //
    // canvas.drawPath(path, paint);
    if (waveform.isNotEmpty) {
      double widthPerDataPoint = size.width / waveform.length;

      // 起始位置为偏移量
      double currentX = -offset * (widthPerDataPoint / size.width);

      // 每隔32个点画一次,这样可以大大降低绘制的开销
      for (int i = 0; i < waveform.length; i+=32) {
        double x = currentX + i * (widthPerDataPoint);
        double y = ((1 - waveform[i]) * size.height / 2);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
