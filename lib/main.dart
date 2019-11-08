import 'dart:async';
import 'dart:math';

/* TODO:

  Add Mute button
  Add Ableton Live Network Sync
  Add Network MIDI Clock / timecode

*/

import 'package:screen/screen.dart';
import 'package:flutter/material.dart';

import 'package:localstorage/localstorage.dart';

import 'package:jeffs_metronome/models.dart';

void main() {
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
              bodyColor: Colors.grey,
            ),
      ),
      title: 'Metronome',
      home: new MetronomeClass(),
    );
  }
}

class MetronomeClass extends StatefulWidget {
  @override
  createState() => new MetronomePage();
}

class MetronomePage extends State<MetronomeClass> {
  // We will use a separate metronome object
  // and Change Notifiers to reduce the number of rebuilds
  MetronomeState metronome;

  // ui variables
  double throbberWidth = 40.0;
  Key throbberKey;

  List<MetronomeSettings> playlist = [];
  int currentPlaylistItemIndex;

  final LocalStorage storage = LocalStorage('metronome');

  @override
  void initState() {
    super.initState();

    // setup metronome and metronome listeners
    metronome = MetronomeState();
    metronome.statusUpdate.addListener(refresh);
    metronome.tempoUpdate.addListener(updateSelected);
    metronome.beatListUpdate.addListener(updateSelected);

    // setup throbber settings
    throbberKey = UniqueKey();

    // setup playlist
    playlist.add(MetronomeSettings(
      tempo: metronome.tempo,
      beats: metronome.beatList,
    ));
    currentPlaylistItemIndex = 0;

    load();
  }

  void load() async {
    await storage.ready;
    var loadedplaylist = storage.getItem('playlist');
    if (loadedplaylist != null) {
      playlist = [];
      for (var item in loadedplaylist) {
        var mpi = MetronomeSettings.fromJson(item);
        if (mpi != null) playlist.add(mpi);
      }
      refresh();
    }
  }

  void save() async {
    storage.setItem('playlist', playlist);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void removePlaylistItemAt(int index) {
    if (index >= playlist.length || index <= 0) return;
    playlist.removeAt(index);
    if (index <= currentPlaylistItemIndex) currentPlaylistItemIndex -= 1;
    metronome.tempo = playlist[currentPlaylistItemIndex].tempo;
    metronome.beatList = playlist[currentPlaylistItemIndex].beats;
    save();

    // no metronome setters were touched, call refresh
    refresh();
  }

  void updateSelected() {
    if (currentPlaylistItemIndex < playlist.length) {
      var item = playlist[currentPlaylistItemIndex];
      item.beats = metronome.beatList;
      item.tempo = metronome.tempo;
      save();
      refresh();
    }
  }

  void saveToPlaylist() {
    var item = MetronomeSettings();
    playlist.add(item);
    item.tempo = metronome.tempo;
    item.beats = metronome.beatList.toList();
    currentPlaylistItemIndex = playlist.length - 1;
    save();

    // no metronome setters were touched, call refresh
    refresh();
  }

  void loadPlaylistItem(int index) {
    if (index >= playlist.length) return;
    currentPlaylistItemIndex = index;
    var current = playlist[index];
    metronome.tempo = current.tempo;
    metronome.beatList = current.beats;
    if (metronome.currentBeat >= metronome.beatList.length)
      metronome.currentBeat = metronome.beatList.length - 1;
    refresh();
  }

  Future<void> _editName(int index) async {
    var item = playlist[index];
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text('Edit item name'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                // Text(item.description),
                TextFormField(
                  initialValue: item.name,
                  decoration: InputDecoration(
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white, width: 2.0),
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onFieldSubmitted: (newName) {
                    item.name = newName;
                    save();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            FlatButton(
              child: Text(
                'CANCEL',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            )
          ],
        );
      },
    );
  }

  List<Widget> _makePlaylistWidgets(context) {
    var retval = <Widget>[];
    for (var index = 0; index < playlist.length; index++) {
      var item = playlist[index];
      bool selected = currentPlaylistItemIndex == index;
      Color iconColor = selected ? Colors.black : Colors.grey;
      retval.add(
        InkWell(
          key: ValueKey(item),
          onTap: () {
            loadPlaylistItem(index);
          },
          child: Container(
            height: 70.0,
            padding: EdgeInsets.all(10.0),
            color: currentPlaylistItemIndex == index
                ? metronome.isPlaying ? Colors.red[100] : Colors.green[100]
                : Colors.black,
            child: DefaultTextStyle(
              style: Theme.of(context)
                  .textTheme
                  .body1
                  .apply(color: selected ? Colors.black : null),
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: (selected && metronome.isPlaying)
                        ? Icon(Icons.pause, color: iconColor)
                        : Icon(Icons.play_arrow, color: iconColor),
                    onPressed: () {
                      var shouldPause = selected;
                      loadPlaylistItem(index);
                      if (!metronome.isPlaying)
                        metronome.start();
                      else if (metronome.isPlaying && shouldPause)
                        metronome.stop();
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
                      item.name.isNotEmpty
                          ? '${item.name.toUpperCase()}\n${item.details}'
                          : '${item.details}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, color: iconColor),
                    onPressed: () => _editName(index),
                  ),
                  if (index > 0)
                    IconButton(
                      icon: Icon(Icons.delete, color: iconColor),
                      onPressed: () => removePlaylistItemAt(index),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return retval;
  }

  void _handleReorder(oldIndex, newIndex) {
    final item = playlist.removeAt(oldIndex);

    // the current playlist is shorter than it was
    // if the item was moved downward, the insertLocation needs to be adjusted
    var insertLocation = oldIndex < newIndex ? newIndex - 1 : newIndex;

    if (oldIndex == currentPlaylistItemIndex)
      currentPlaylistItemIndex = insertLocation;
    else if (oldIndex > currentPlaylistItemIndex &&
        insertLocation <= currentPlaylistItemIndex)
      currentPlaylistItemIndex += 1;
    else if (oldIndex < currentPlaylistItemIndex &&
        insertLocation >= currentPlaylistItemIndex)
      currentPlaylistItemIndex -= 1;

    playlist.insert(insertLocation, item);
    save();
    refresh();
  }

  @override
  void dispose() {
    metronome.stop();
    metronome.removeListener(refresh);
    metronome.tempoUpdate.removeListener(updateSelected);
    metronome.beatListUpdate.removeListener(updateSelected);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    return new Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: size.width,
            height: 30.0,
            color: Colors.black,
            child: metronome.isPlaying
                ? CustomPaint(
                    key: throbberKey,
                    foregroundPainter: ThrobberPainter(
                      metronome: metronome,
                      repaint: metronome.throbberUpdate,
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
                      AnimatedBuilder(
                        animation: metronome.tempoUpdate,
                        builder: (context, _) => Text(
                          "${metronome.tempo}",
                          style: TextStyle(
                              fontSize: 40.0, fontWeight: FontWeight.w900),
                        ),
                      ),
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
                    AnimatedBuilder(
                      animation: metronome.tempoUpdate,
                      builder: (context, _) => Text(
                        (60000 ~/ metronome.tempo).toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 40.0, fontWeight: FontWeight.w900),
                      ),
                    )
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
                      AnimatedBuilder(
                        animation: metronome.beatUpdate,
                        builder: (context, _) => Text(
                          "${metronome.currentBeat + 1} / ${metronome.beatList.length}",
                          style: TextStyle(
                              fontSize: 40.0, fontWeight: FontWeight.w900),
                        ),
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
              padding: EdgeInsets.all(4.0),
              child: AnimatedBuilder(
                animation: metronome.beatListUpdate,
                builder: (context, _) => Row(
                  children: <Widget>[
                    for (int i = 0; i < metronome.beatList.length; i++)
                      Expanded(
                        child: Listener(
                          onPointerDown: (_) {
                            metronome.beatList[i] =
                                (metronome.beatList[i] + 1) %
                                    (metronome.clickCount + 1);
                            save();
                            refresh();
                          },
                          child: Column(
                            children: [
                              // current beat options
                              for (int j = metronome.clickCount - 1;
                                  j >= 0;
                                  j--)
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(5),
                                    color: metronome.beatList[i] > j
                                        ? Colors.orange
                                        : Colors.black,
                                  ),
                                  height: 20.0,
                                  margin: EdgeInsets.symmetric(
                                      vertical: 2.0, horizontal: 2.0),
                                ),
                              // current beat indicator
                              AnimatedBuilder(
                                animation: metronome.beatUpdate,
                                builder: (context, _) => Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(5),
                                    color: (metronome.currentBeat == i)
                                        ? Colors.yellow
                                        : Colors.black,
                                  ),
                                  margin: EdgeInsets.symmetric(
                                      vertical: 2.0, horizontal: 2.0),
                                  height: 10.0,
                                ),
                              )
                            ],
                          ),
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),

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
                      metronome.incTempo(inc);
                    },
                  ),
                ),
                Container(width: 8.0),
                Flexible(
                  flex: 1,
                  child: HorizontalTouchBar(
                    text: 'TAP',
                    dragThreshold: 999,
                    tapCallback: (_) => metronome.tap(),
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
                      metronome.incBeats(dragged > 0 ? 1 : -1);
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
                      metronome.beatList = [1, 1, 1, 1];
                      metronome.incBeats(0);
                    },
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              // FlatButton(
              //   onPressed: () => updateCurrentPlaylistItem(),
              //   child: Text(
              //     'UPDATE CURRENT',
              //     style: TextStyle(
              //         fontWeight: FontWeight.w900, color: Colors.grey),
              //   ),
              // ),
              RaisedButton(
                elevation: 0,
                color: Colors.grey[850],
                onPressed: () => saveToPlaylist(),
                child: Text(
                  'SAVE AS NEW PLAYLIST ITEM',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: Colors.grey),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Expanded(
            child: Container(
              color: Colors.grey[800],
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: ReorderableListView(
                padding: EdgeInsets.only(top: 8.0),
                children: _makePlaylistWidgets(context),
                onReorder: _handleReorder,
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
  MetronomeState metronome;

  Paint paintSettings;

  double r = 20;
  double realx;
  List<double> indicators = [];

  ThrobberPainter({
    Listenable repaint,
    this.metronome,
  }) : super(repaint: repaint) {
    if (paintSettings == null) {
      paintSettings = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.fill
        ..color = Colors.yellow;
    }
  }

  void computeIndicators(double width) {
    indicators.clear();
    double minx = r;
    double maxx = width - r;
    double xoff = (maxx - minx) * metronome.throbberData.pct;
    int numIndicators = 5;
    List indicatorOffsets = [];
    double blurwidth = width * .2;
    for (var i = 0; i < numIndicators; i++) {
      double indicatorOffset = max(0, xoff - blurwidth * i / numIndicators);
      indicatorOffsets.add(indicatorOffset);
    }
    if (metronome.throbberData.rightward) {
      realx = maxx - xoff;
      for (var i = 0; i < numIndicators; i++) {
        indicators.add(maxx - indicatorOffsets[i]);
      }
    } else {
      realx = minx + xoff;
      for (var i = 0; i < numIndicators; i++) {
        indicators.add(minx + indicatorOffsets[i]);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    r = size.height / 2;
    computeIndicators(size.width);
    // print(metronome.throbberData.pct);

    double maxflashpct = .5;
    if (metronome.throbberData.pct < maxflashpct) {
      double flashOpacity =
          (maxflashpct - metronome.throbberData.pct) / maxflashpct;
      if (flashOpacity > .6) flashOpacity = 1;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.yellow.withOpacity(flashOpacity),
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.black.withOpacity(1),
      );
    }

    // make circles of varying opacity
    int numcircles = indicators.length;
    for (var i = 0; i < numcircles; i++) {
      var opacity = 1 - (i / numcircles);
      paintSettings.color = paintSettings.color.withOpacity(opacity);
      // canvas.drawCircle(Offset(circles[i], r), r, paintSettings);
      canvas.drawRect(
        Rect.fromLTWH(indicators[i] - r, 0, r * 2, r * 2),
        paintSettings,
      );
    }
  }

  @override
  bool shouldRepaint(ThrobberPainter oldDelegate) {
    // since we are passing metronome as an object
    // the old delegate and the current one will always be in sync
    // return oldDelegate.metronome.throbberData.pct != metronome.throbberData.pct;
    return true;
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
          decoration: BoxDecoration(
            color: touching ? Colors.red : Colors.grey[850],
            borderRadius: BorderRadius.circular(5),
          ),
          width: double.infinity,
          height: 40,
          alignment: Alignment.topLeft,
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
