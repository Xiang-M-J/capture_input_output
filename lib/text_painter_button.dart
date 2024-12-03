import 'package:capture_input_ouput/waveform_painter.dart';
import 'package:flutter/material.dart';

class TextPainterButton extends StatefulWidget{
  final String text;
  final List<double> waveform;
  final void Function()? playfn;
  const TextPainterButton({super.key, required this.playfn, required this.text, required this.waveform});

  @override
  State<TextPainterButton> createState() => TextPainterButtonState();

}

class TextPainterButtonState extends State<TextPainterButton>{
  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        SizedBox(
          width: 0.1 * size.width,
          child: Text(widget.text),
        ),

        Container(
          margin: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            border: Border.all()
          ),
          child: CustomPaint(
            painter: WaveformPainter(widget.waveform),
            size: Size(size.width * 0.6, size.height * 0.1),
          ),
          // child: StreamAudioVisualizer(size: Size(size.width * 0.6, size.height * 0.1), audioStream: null,
          //
          // ),
        ),
        ElevatedButton(onPressed: widget.playfn, child: const Text("播放"))
      ],
    );
  }

}

class TextPainter2Button extends StatefulWidget{
  final String text;
  final List<double> waveform;
  final int offset;
  final void Function()? playfn;
  const TextPainter2Button({super.key, required this.playfn, required this.text, required this.waveform, required this.offset});

  @override
  State<TextPainter2Button> createState() => TextPainter2ButtonState();

}

class TextPainter2ButtonState extends State<TextPainter2Button>{
  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        SizedBox(
          width: 0.1 * size.width,
          child: Text(widget.text),
        ),

        Container(
          margin: const EdgeInsets.all(5),
          decoration: BoxDecoration(
              border: Border.all()
          ),
          child: CustomPaint(
            painter: WaveformPainter2(widget.waveform, widget.offset),
            size: Size(size.width * 0.6, size.height * 0.1),
          ),
          // child: StreamAudioVisualizer(size: Size(size.width * 0.6, size.height * 0.1), audioStream: null,
          //
          // ),
        ),
        ElevatedButton(onPressed: widget.playfn, child: const Text("播放"))
      ],
    );
  }

}


class TextStreamPainterButton extends StatefulWidget{
  final String text;
  final Stream<List<double>>  waveform;
  final void Function()? playfn;
  const TextStreamPainterButton({super.key, required this.playfn, required this.text, required this.waveform});

  @override
  State<TextStreamPainterButton> createState() => TextStreamPainterButtonState();

}

class TextStreamPainterButtonState extends State<TextStreamPainterButton>{
  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        SizedBox(
          width: 0.1 * size.width,
          child: Text(widget.text),
        ),

        Container(
          margin: const EdgeInsets.all(5),
          decoration: BoxDecoration(
              border: Border.all()
          ),

          child: StreamAudioVisualizer(size: Size(size.width * 0.6, size.height * 0.1), audioStream: widget.waveform,

          ),
        ),
        ElevatedButton(onPressed: widget.playfn, child: const Text("播放"))
      ],
    );
  }

}