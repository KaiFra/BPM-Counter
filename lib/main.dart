import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(BPM());

class BPM extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    return MaterialApp(
      title: 'BPM Counter',
      home: BPMCounter(title: 'BPM Counter'),
    );
  }
}

class BPMCounter extends StatefulWidget {
  BPMCounter({Key key, this.title}) : super(key: key);
  final String title;
  @override
  _BPMCounter createState() => _BPMCounter();
}

class _BPMCounter extends State<BPMCounter> {
  int _n = 0;
  int _m = 0;
  int _bpm = 0;
  int _bpmoldmax = 0;
  int _bpmmax = 0;
  //int _sec = 0;
  Stopwatch s = new Stopwatch();

  void _increment() {
    setState(() {
      if (!s.isRunning) {
        s.start();
      } else {
        _bpm = _n ~/ (s.elapsedMicroseconds / 60000000); //Todo
        //_sec = s.elapsedMilliseconds ~/ 1000;
      }
      if (_bpmmax < _bpm) {
        _bpmmax = _bpm;
      }
      _n++;
    });
  }

  void _reset() {
    setState(() {
      _m = _n;
      _n = 0;
      _bpmoldmax = _bpmmax;
      _bpm = 0;
      _bpmmax = 0;
      s.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('BPM Counter'),
        backgroundColor: Color.fromRGBO(92, 184, 92, 1),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Container(
                width: 40,
                child: Text(
                  '$_n',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.right,
                ),
              ),
              Container(
                width: 200,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    Container(
                      width: 100,
                      child: Text(
                        '$_bpm',
                        style: TextStyle(color: Colors.white, fontSize: 40),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Container(
                      width: 100,
                      child: Text(
                        ' BPM',
                        style: TextStyle(color: Colors.white, fontSize: 40),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                child: Text(
                  '$_m',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Container(
                width: 40,
                child: Text(
                  '$_bpmmax',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 200,
              ),
              Container(
                width: 40,
                child: Text(
                  '$_bpmoldmax',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(
            width: double.infinity,
          ),
          RawMaterialButton(
            onPressed: _increment,
            splashColor: Colors.black,
            child: Container(
              child: CustomPaint(painter: DrawCircle()),
            ),
            shape: new CircleBorder(),
            elevation: 2.0,
            fillColor: Color.fromRGBO(92, 184, 92, 0.1),
            padding: const EdgeInsets.all(135.0),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _reset,
        child: Text('Reset'),
        backgroundColor: Colors.black,
        //Color.fromRGBO(92, 184, 92, 1),
      ),
    );
  }
}

class DrawCircle extends CustomPainter {
  Paint _paint;

  DrawCircle() {
    _paint = Paint()
      ..color = Color.fromRGBO(92, 184, 92, 0.2)
      ..strokeWidth = 10.0
      ..style = PaintingStyle.fill;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(0.0, 0.0), 120.0, _paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
