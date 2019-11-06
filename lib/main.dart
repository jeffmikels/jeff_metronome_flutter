import 'dart:async';
import 'dart:convert';
import 'dart:math';

/* TODO:

  Add throbber and flasher for visual metronome
  Add Mute button
  Add beat selector
  Design: cool font, bpm slider

  Add Ableton Live Network Sync
  Add Network MIDI Clock / timecode

*/

import 'package:screen/screen.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audio_cache.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:localstorage/localstorage.dart';

void main() {
  // SystemChrome.setEnabledSystemUIOverlays([]);

  runApp(new MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: Theme.of(context).textTheme.apply(
              fontFamily: 'Quicksand',
            ),
      ),
      title: 'Metronome',
      home: new MetronomeClass(),
    );
  }
}

class MetronomeClass extends StatefulWidget {
  @override
  createState() => new MetronomeState();
}

class MetronomeState extends State<MetronomeClass>
    with TickerProviderStateMixin {
  // state variables
  int _tempo = 100;
  List<int> beats = [1, 1, 1, 1]; // 1 for low, 2 for high, 0 for off
  int currentBeat = 0;
  List<DateTime> taps = [];
  bool isPlaying = false;
  double lastBeat;
  double throbberPct = 0;
  bool throbberRight = true;
  double throbberWidth = 40.0;

  // Ticker ticker;
  Timer timer;
  bool timerMuted = false;
  AnimationController beatFlasher;

  // audio variables
  AudioCache player;
  AudioPlayer lowClick;
  AudioPlayer highClick;
  List<String> clicks = [
    'click-low.wav',
    'click-high.wav',
  ];

  Key throbberKey;

  // use this to keep track of how long the finger has dragged an item.
  double dragged = 0;

  List<MetronomePlaylistItem> playlist = [];
  int currentPlaylistItemIndex;

  final LocalStorage storage = LocalStorage('metronome');

  int get tempo => _tempo;
  set tempo(int newtempo) {
    _tempo = newtempo;
    playlist[currentPlaylistItemIndex].tempo = _tempo;
    refresh();
    save();
  }

  @override
  void initState() {
    super.initState();

    beatFlasher = AnimationController(
      value: 0,
      duration: Duration(milliseconds: 400),
      vsync: this,
    );

    // setup throbber settings
    throbberKey = UniqueKey();

    // setup playlist
    playlist.add(MetronomePlaylistItem(
      tempo: tempo,
      beats: beats,
    ));
    currentPlaylistItemIndex = 0;

    // set up audio player with sounds
    player = AudioCache(prefix: 'sounds/');
    player.loadAll(clicks);

    lastBeat = DateTime.now().millisecondsSinceEpoch.toDouble();

    // set timer for roughly 30 fps
    timer = Timer.periodic(Duration(milliseconds: 32), (_) => doTick());
    // ticker = createTicker((d) => doTick(d));
    // ticker.start();

    load();
  }

  void load() async {
    await storage.ready;
    var loadedplaylist = storage.getItem('playlist');
    if (loadedplaylist != null) {
      timerMuted = true;
      playlist = [];
      for (var item in loadedplaylist) {
        var mpi = MetronomePlaylistItem.fromJson(item);
        if (mpi != null) playlist.add(mpi);
      }
      timerMuted = false;
      refresh();
    }
  }

  void save() async {
    storage.setItem('playlist', playlist);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  // this function checks on every tick to see
  // if the metronome status should be updated
  void doTick() {
    // if (!isPlaying) return refresh();
    if (timerMuted || !isPlaying) return refresh();

    var now = DateTime.now().millisecondsSinceEpoch.toDouble();
    var delay = 60000 / tempo;
    var nextBeat = lastBeat + delay;

    // if we got way out of sync, don't play millions of clicks
    // just reset the nextBeat time to right now.
    if (now > nextBeat + delay) nextBeat = now;

    // one frame is 16.66 milliseconds long
    // if we are within one frame of the beat, play it now
    var diff = now - nextBeat;
    if (diff >= -8) {
      doBeat();
      print('beat error (ms): $diff :: ${diff / delay}');
      throbberPct = 0;
      lastBeat = nextBeat;
      // print(nextBeat);
    } else {
      throbberPct = 1 - (nextBeat - now) / delay;
      if (throbberPct < 0) throbberPct = 0;
      if (throbberPct > 1) throbberPct = 1;
    }

    // print(throbberPct);
    refresh();
  }

  void doBeat() {
    // flip the throbber direction on every beat
    throbberRight = !throbberRight;
    currentBeat = (currentBeat + 1) % beats.length;
    doClick(beats[currentBeat]);
  }

  void doClick(int type) {
    if (type == 0) return;
    print('click - ${clicks[type - 1]}');
    player.play(clicks[type - 1]);
    beatFlasher.reverse(from: 1);
  }

  void tap() {
    // if (isPlaying) stop();
    var now = DateTime.now();
    if (taps.isNotEmpty && now.difference(taps.last) > Duration(seconds: 1))
      taps = [];
    taps.add(now);
    doClick(2);
    computeTaps();
    refresh();
  }

  void computeTaps() {
    while (taps.length > 4) taps.removeAt(0);
    if (taps.length == 1) return;
    var avgdiff =
        taps.last.difference(taps.first).inMilliseconds / (taps.length - 1);
    print(avgdiff);
    tempo = 60000 ~/ avgdiff;
  }

  void toggle() {
    if (isPlaying)
      stop();
    else
      start();

    refresh();
  }

  void start() {
    // var delay = 60000 ~/ tempo;
    // ticker.muted = true;
    timer?.cancel();
    throbberPct = 0;
    throbberRight = true;
    currentBeat = beats.length - 1;
    lastBeat = DateTime.now().millisecondsSinceEpoch.toDouble();
    isPlaying = true;
    doBeat();
    // ticker.muted = false;
    // boost the framerate of the timer
    timer = Timer.periodic(Duration(milliseconds: 10), (_) => doTick());
    Screen.keepOn(true);
  }

  void stop() {
    timer?.cancel();
    // lower the framerate of the timer
    timer = Timer.periodic(Duration(milliseconds: 32), (_) => doTick());
    beatFlasher.value = 0;
    throbberPct = 0;
    throbberRight = true;
    currentBeat = 0;
    Screen.keepOn(false);
    isPlaying = false;
  }

  void incTempo(int inc) {
    // see the setter for additional things that happen
    // when setting the tempo
    tempo = max(40, min(tempo += inc, 300));
  }

  void incBeats(int inc) {
    if (inc < 0) {
      int newlength = beats.length + inc;
      if (newlength < 1) newlength = 1;
      beats.length = newlength;
    } else {
      for (var i = 0; i < inc; i++) beats.add(1);
    }
    playlist[currentPlaylistItemIndex].beats = beats.toList();
    refresh();
    save();
  }

  void removePlaylistItemAt(int index) {
    if (index >= playlist.length || index <= 0) return;
    playlist.removeAt(index);
    if (index <= currentPlaylistItemIndex) currentPlaylistItemIndex -= 1;
    _tempo = playlist[currentPlaylistItemIndex].tempo;
    beats = playlist[currentPlaylistItemIndex].beats;
    refresh();
    save();
  }

  void saveToPlaylist() {
    var item = MetronomePlaylistItem();
    playlist.add(item);
    item.tempo = tempo;
    item.beats = beats.toList();
    currentPlaylistItemIndex = playlist.length - 1;
    refresh();
    save();
  }

  void loadPlaylistItem(int index) {
    if (index >= playlist.length) return;
    currentPlaylistItemIndex = index;
    var current = playlist[index];
    tempo = current.tempo;
    beats = current.beats;
    if (currentBeat >= beats.length) currentBeat = beats.length - 1;
    // currentBeat = beats.length - 1;
    refresh();
  }

  @override
  void dispose() {
    stop();
    Screen.keepOn(false);
    timer?.cancel();
    // ticker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    // var throbberPos = size.width * throbberPct;
    // if (!throbberRight) throbberPos = size.width - throbberWidth - throbberPos;
    // if (throbberPos < 0) throbberPos = 0;
    // if (throbberPos > size.width - throbberWidth)
    //   throbberPos = size.width - throbberWidth;
    // print(throbberPos);
    return new Scaffold(
      //Red or green depending on the state of playing
      backgroundColor: Colors.blue,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'JEFF\'S METRONOME',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w100,
            fontSize: 30.0,
          ),
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Throbber
          Container(
            width: size.width,
            height: 30.0,
            color: isPlaying ? Colors.black : Colors.blue,
            // padding: throbberRight
            //     ? EdgeInsets.only(left: size.width * throbberPct)
            //     : EdgeInsets.only(right: size.width * throbberPct),
            // child: Stack(
            //   children: [
            //     Positioned(
            //         left: throbberPos,
            //         child: Container(
            //           width: throbberWidth,
            //           height: throbberWidth,
            //           color: Colors.yellow,
            //         )),
            //   ],
            // ),
            // child: BackgroundFlasher(
            //   color: Colors.yellow,
            //   controller: beatFlasher,
            //   child: isPlaying
            //       ? CustomPaint(
            //           key: throbberKey,
            //           foregroundPainter: ThrobberPainter(
            //             xpct: throbberPct,
            //             flipx: !throbberRight,
            //           ),
            //         )
            //       : Container(),
            // ),
            child: isPlaying
                ? CustomPaint(
                    key: throbberKey,
                    foregroundPainter: ThrobberPainter(
                      xpct: throbberPct,
                      flipx: !throbberRight,
                    ),
                  )
                : Container(),
          ),
          Container(
            padding: EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'bpm',
                        textAlign: TextAlign.left,
                      ),
                      Text(
                        "$tempo",
                        style: TextStyle(
                            fontSize: 40.0, fontWeight: FontWeight.w900),
                      )
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      'delay',
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      (60000 ~/ _tempo).toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 40.0, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        'beat',
                        textAlign: TextAlign.right,
                      ),
                      Text(
                        "${currentBeat + 1} / ${beats.length}",
                        style: TextStyle(
                            fontSize: 40.0, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // beat indicators
          Container(
            color: Colors.black,
            child: Container(
              // color: Colors.black,
              padding: EdgeInsets.all(4.0),
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < beats.length; i++)
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) {
                          beats[i] = (beats[i] + 1) % (clicks.length + 1);
                          save();
                          refresh();
                        },
                        child: Column(
                          children: [
                            // current beat options
                            for (int j = clicks.length - 1; j >= 0; j--)
                              Container(
                                height: 20.0,
                                margin: EdgeInsets.symmetric(
                                    vertical: 2.0, horizontal: 2.0),
                                color:
                                    beats[i] > j ? Colors.orange : Colors.black,
                              ),
                            // current beat indicator
                            Container(
                              color: (isPlaying && currentBeat == i)
                                  ? Colors.yellow
                                  : Colors.black,
                              margin: EdgeInsets.symmetric(
                                  vertical: 2.0, horizontal: 2.0),
                              height: 10.0,
                            ),
                          ],
                        ),
                      ),
                    )
                ],
              ),
            ),
          ),
          // debug menu bar
          // Row(
          //   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          //   children: <Widget>[
          //     TapButton(
          //       onTapDown: (_) => incBeats(1),
          //       text: '+',
          //     ),
          //     TapButton(
          //       onTapDown: (_) => incBeats(-1),
          //       text: '-',
          //     ),
          //     TapButton(
          //       onTapDown: (_) => doClick(1),
          //       text: 'high',
          //     ),
          //     TapButton(
          //       onTapDown: (_) => doClick(0),
          //       text: 'low',
          //     ),
          //     TapButton(
          //       onTapDown: (_) => tap(),
          //       text: 'tap',
          //     ),
          //     TapButton(
          //       onTapDown: (_) => toggle(),
          //       child: isPlaying ? Icon(Icons.pause) : Icon(Icons.play_arrow),
          //     ),
          //   ],
          // ),
          Container(
            margin: EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0),
            child: Row(
              children: <Widget>[
                Flexible(
                  flex: 4,
                  child: HorizontalTouchBar(
                    text: '← TEMPO →',
                    dragThreshold: 5,
                    dragCallback: (dragged) {
                      int inc = 0;
                      if (dragged > 0)
                        inc = 1;
                      else if (dragged < 0) inc = -1;
                      incTempo(inc);
                    },
                  ),
                ),
                Container(width: 8.0),
                Flexible(
                  flex: 1,
                  child: HorizontalTouchBar(
                    text: 'TAP',
                    dragThreshold: 999,
                    tapCallback: (_) => tap(),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: EdgeInsets.all(8.0),
            child: Row(
              children: <Widget>[
                Flexible(
                  flex: 4,
                  child: HorizontalTouchBar(
                    text: '← BEATS →',
                    dragThreshold: 50,
                    dragCallback: (dragged) {
                      incBeats(dragged > 0 ? 1 : -1);
                    },
                  ),
                ),
                Container(
                  width: 8.0,
                ),
                Flexible(
                  flex: 1,
                  child: HorizontalTouchBar(
                    text: '4/4',
                    dragThreshold: 999,
                    tapCallback: (_) {
                      beats = [1, 1, 1, 1];
                      incBeats(0);
                    },
                  ),
                ),
              ],
            ),
          ),
          FlatButton(
            onPressed: () => saveToPlaylist(),
            child: Text('SAVE NEW PLAYLIST ITEM',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8.0),
              // color: Colors.black,
              child: ListView.builder(
                itemCount: playlist.length,
                itemBuilder: (context, index) {
                  var item = playlist[index];
                  return InkWell(
                    onTap: () {
                      loadPlaylistItem(index);
                    },
                    child: Container(
                      height: 60.0,
                      padding: EdgeInsets.all(10.0),
                      color: currentPlaylistItemIndex == index
                          ? isPlaying ? Colors.red[100] : Colors.green[100]
                          : Colors.blue[100],
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            icon:
                                (currentPlaylistItemIndex == index && isPlaying)
                                    ? Icon(Icons.pause)
                                    : Icon(Icons.play_arrow),
                            onPressed: () {
                              var shouldPause =
                                  currentPlaylistItemIndex == index;
                              loadPlaylistItem(index);
                              if (!isPlaying)
                                start();
                              else if (isPlaying && shouldPause) stop();
                            },
                          ),
                          Container(
                            margin: EdgeInsets.only(right: 8.0),
                            child: Text(
                              '${index + 1}.',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20.0,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${item.name}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (index > 0)
                            IconButton(
                              icon: Icon(Icons.delete),
                              onPressed: () => removePlaylistItemAt(index),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TapButton extends StatelessWidget {
  final Function onTapDown;
  final String text;
  final Widget child;
  TapButton({this.onTapDown, this.text: '', this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: onTapDown,
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.all(10.0),
        child: child != null
            ? child
            : Text(
                text.toUpperCase(),
                style: TextStyle(
                  fontSize: 14.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class ThrobberPainter extends CustomPainter {
  double xpct;
  bool flipx;

  Paint paintSettings;

  double r = 20;
  double realx;
  List<double> circles = [];

  ThrobberPainter({
    Listenable repaint,
    this.xpct: 0,
    this.flipx: false,
  }) : super(repaint: repaint) {
    if (paintSettings == null) {
      paintSettings = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.fill
        ..color = Colors.yellow[100];
    }
  }

  void computeCircles(double width) {
    double minx = r;
    double maxx = width - r;
    double xoff = (maxx - minx) * xpct;
    int numcircles = 5;
    List circleoffsets = [];
    double blurwidth = width * .2;
    for (var i = 0; i < numcircles; i++) {
      double circleoffset = max(0, xoff - blurwidth * i / numcircles);
      circleoffsets.add(circleoffset);
    }
    if (flipx) {
      realx = maxx - xoff;
      for (var i = 0; i < numcircles; i++) {
        circles.add(maxx - circleoffsets[i]);
      }
    } else {
      realx = minx + xoff;
      for (var i = 0; i < numcircles; i++) {
        circles.add(minx + circleoffsets[i]);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    r = size.height / 2;
    computeCircles(size.width);

    double maxflashpct = .5;
    if (xpct < maxflashpct) {
      double flashOpacity = (maxflashpct - xpct) / maxflashpct;
      if (flashOpacity > .6) flashOpacity = 1;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.yellow.withOpacity(flashOpacity),
      );
    }

    // make circles of varying opacity
    int numcircles = circles.length;
    for (var i = 0; i < numcircles; i++) {
      var opacity = 1 - (i / numcircles);
      paintSettings.color = paintSettings.color.withOpacity(opacity);
      // canvas.drawCircle(Offset(circles[i], r), r, paintSettings);
      canvas.drawRect(
        Rect.fromLTWH(circles[i] - r, 0, r * 2, r * 2),
        paintSettings,
      );
    }
  }

  @override
  bool shouldRepaint(ThrobberPainter oldDelegate) {
    return oldDelegate.xpct != xpct;
  }
}

class HorizontalTouchBar extends StatefulWidget {
  final String text;
  final Function dragCallback;
  final Function tapCallback;
  final int dragThreshold;

  HorizontalTouchBar(
      {this.text, this.dragCallback, this.tapCallback, this.dragThreshold});

  @override
  _HorizontalTouchBarState createState() => _HorizontalTouchBarState();
}

class _HorizontalTouchBarState extends State<HorizontalTouchBar> {
  double dragged = 0;
  Offset touchloc;
  bool touching = false;

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        touching = true;
        touchloc = e.localPosition;
        print(touchloc);
        refresh();
        if (widget.tapCallback != null) widget.tapCallback(e);
      },
      onPointerUp: (e) {
        touching = false;
        dragged = 0;
        refresh();
      },
      onPointerMove: (e) {
        touching = true;
        touchloc = e.localPosition;
        dragged += e.delta.dx;
        refresh();
        if (dragged > widget.dragThreshold || dragged < -widget.dragThreshold) {
          if (widget.dragCallback != null) widget.dragCallback(dragged);
          dragged = 0;
        }
      },
      child: ClipRect(
        child: Container(
          width: double.infinity,
          height: 40,
          alignment: Alignment.topLeft,
          color: touching ? Colors.red : Colors.black,
          child: Stack(
            children: <Widget>[
              if (touching)
                Positioned(
                  left: touchloc.dx - 40,
                  top: 0,
                  child: SizedBox(
                    width: 80,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          stops: [.1, .5, .9],
                          colors: [
                            Colors.red,
                            Colors.yellow,
                            Colors.red,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Container(
                padding: EdgeInsets.all(10.0),
                width: double.infinity,
                alignment: Alignment.center,
                child: Text(
                  widget.text,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MetronomePlaylistItem {
  // String name;
  int tempo;
  List<int> beats;

  int get millis => 60000 ~/ tempo;

  String get name =>
      'BPM: $tempo • BEATS: 1/${beats.length}\n${millis}ms • .75 = ${millis * 0.75}ms';

  MetronomePlaylistItem({this.tempo, this.beats});
  MetronomePlaylistItem.fromJson(Map<String, dynamic> json) {
    fromMap(json);
  }

  fromMap(Map<String, dynamic> json) {
    tempo = json['tempo'];
    beats = List<int>.from(json['beats']);
  }

  Map toJson() => {
        'tempo': tempo,
        'beats': beats,
      };
}

class BackgroundFlasher extends StatefulWidget {
  final AnimationController controller;
  final Widget child;
  final Color color;

  BackgroundFlasher({Key key, this.controller, this.child, this.color})
      : super(key: key);

  @override
  _BackgroundFlasherState createState() => _BackgroundFlasherState();
}

class _BackgroundFlasherState extends State<BackgroundFlasher>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.color.withOpacity(widget.controller.value),
      child: widget.child,
    );
  }
}
