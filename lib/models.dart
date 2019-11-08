import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:screen/screen.dart';
// import 'package:audioplayers/audio_cache.dart';
import 'package:soundpool/soundpool.dart';
import 'package:flutter/widgets.dart';

class ThrobberData {
  double pct = 0;
  bool rightward = true;
}

class MetronomePlaylist {
  List<MetronomeSettings> items = [];
  int currentIndex;

  MetronomeSettings get current => items[currentIndex];
}

class MetronomeSettings {
  String name = '';
  int tempo = 120;
  List<int> beats = [1, 1, 1, 1];

  int get millis => 60000 ~/ tempo;

  String get details =>
      'BPM: $tempo • BEATS: 1/${beats.length}\n${millis}ms • .75 = ${millis * 0.75}ms';

  String get description => name.isNotEmpty ? '$name\n$details' : details;

  MetronomeSettings({this.tempo, this.beats});
  MetronomeSettings.fromJson(Map<String, dynamic> json) {
    fromMap(json);
  }

  fromMap(Map<String, dynamic> json) {
    name = json['name'] ?? '';
    tempo = json['tempo'] ?? 120;
    beats = List<int>.from(json['beats'] ?? [1, 1, 1, 1]);
  }

  Map toJson() {
    return {
      'name': name,
      'tempo': tempo,
      'beats': beats,
    };
  }
}

class MetronomeState with ChangeNotifier {
  // private state variables
  // with getters and setters for notifying on updates
  int _tempo = 100;
  List<int> _beatList = [1, 1, 1, 1]; // 1 for low, 2 for high, 0 for off
  int _currentBeat = 0;
  bool _isPlaying = false;
  bool _muted = false;

  // private variables that don't need listeners
  List<DateTime> _taps = [];
  double _lastBeat = 0;
  Timer _timer;
  int _lastThrobberUpdate = 0; // for fps limiting

  // private audio variables
  // AudioCache _player;
  List<String> _clicks = [
    'click-low.wav',
    'click-high.wav',
  ];
  List<int> soundIds = [];
  Soundpool audioPool;

  // public variables
  ThrobberData throbberData;

  // public notifiers
  ChangeNotifier statusUpdate;
  ChangeNotifier tempoUpdate;
  ChangeNotifier beatListUpdate;
  ChangeNotifier throbberUpdate;
  ValueNotifier<int> beatUpdate;

  MetronomeState() {
    throbberData = ThrobberData();
    statusUpdate = ChangeNotifier();
    tempoUpdate = ChangeNotifier();
    beatListUpdate = ChangeNotifier();
    throbberUpdate = ChangeNotifier();
    beatUpdate = ValueNotifier<int>(currentBeat);
    audioPool = Soundpool(streamType: StreamType.music, maxStreams: 4);
    prepareAudio();
  }

  // getters and setters
  int get clickCount => _clicks.length;

  int get tempo => _tempo;
  set tempo(int i) {
    _tempo = i;
    tempoUpdate.notifyListeners();
  }

  List<int> get beatList => _beatList;
  set beatList(List<int> l) {
    _beatList = l;
    beatListUpdate.notifyListeners();
  }

  int get currentBeat => _currentBeat;
  set currentBeat(int i) {
    _currentBeat = i;
    beatUpdate.value = _currentBeat;
  }

  bool get isPlaying => _isPlaying;
  set isPlaying(bool b) {
    _isPlaying = b;
    statusUpdate.notifyListeners();
  }

  bool get muted => _muted;
  set muted(bool b) {
    _muted = b;
    statusUpdate.notifyListeners();
  }

  void notifyAll() {
    statusUpdate.notifyListeners();
    tempoUpdate.notifyListeners();
    beatListUpdate.notifyListeners();
    throbberUpdate.notifyListeners();
    beatUpdate.notifyListeners();
  }

  void prepareAudio() async {
    // set up audio player with sounds
    // _player = AudioCache(prefix: 'sounds/');
    // _player.loadAll(_clicks);
    soundIds = [];
    for (var path in _clicks) {
      int id = await rootBundle
          .load('assets/sounds/$path')
          .then((ByteData soundData) => audioPool.load(soundData));
      soundIds.add(id);
    }
  }

  void setTempo(int i) {
    tempo = i;
    tempoUpdate.notifyListeners();
  }

  void setBeats(List<int> l) {
    beatList = l;
    beatListUpdate.notifyListeners();
  }

  // instead of Timer.periodic, we use this
  // to run as fast as possible
  void doLoop() {
    // if (isPlaying) Timer.run(doLoop);
    _timer = Timer(Duration(microseconds: 500), doLoop);
    doTick();
  }

  // this function checks on every tick to see
  // if the metronome status should be updated
  void doTick() {
    if (muted || !isPlaying) return;

    var now = DateTime.now().millisecondsSinceEpoch.toDouble();
    var delay = 60000 / tempo;
    var nextBeat = _lastBeat + delay;

    // if we got way out of sync, don't play millions of clicks
    // just reset the nextBeat time to right now.
    if (now > nextBeat + delay) nextBeat = now;

    // one frame is 16.66 milliseconds long
    // if we are within one frame of the beat, play it now
    var diff = now - nextBeat;
    if (diff >= 0) {
      doBeat();
      print('beat error (ms): $diff :: ${diff / delay}');
      // reset the throbber pct and flip direction on every beat
      throbberData.pct = 0;
      throbberData.rightward = !throbberData.rightward;
      _lastBeat = nextBeat;
    } else {
      throbberData.pct = 1 - (nextBeat - now) / delay;
      if (throbberData.pct < 0) throbberData.pct = 0;
      if (throbberData.pct > 1) throbberData.pct = 1;
    }

    if (now - _lastThrobberUpdate > 16) {
      throbberUpdate.notifyListeners();
      _lastThrobberUpdate = now.toInt();
    }
  }

  void doBeat() {
    currentBeat = (currentBeat + 1) % beatList.length;
    playClick(beatList[currentBeat]);
  }

  void playClick(int clickType) {
    if (clickType == 0) return; // a clickType of 0 means "off"
    print('click - ${_clicks[clickType - 1]}');
    // _player.play(_clicks[clickType - 1]);
    audioPool.play(soundIds[clickType - 1]);
  }

  void tap() {
    var now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last) > Duration(seconds: 1))
      _taps = [];
    _taps.add(now);
    playClick(2);
    computeTaps();
  }

  void computeTaps() {
    while (_taps.length > 4) _taps.removeAt(0);
    if (_taps.length == 1) return;
    var avgdiff =
        _taps.last.difference(_taps.first).inMilliseconds / (_taps.length - 1);
    print(avgdiff);
    tempo = 60000 ~/ avgdiff;
  }

  void toggle() {
    if (isPlaying)
      stop();
    else
      start();
  }

  void start() {
    _timer?.cancel();
    throbberData.pct = 0;
    throbberData.rightward = true;
    throbberUpdate.notifyListeners();

    _lastBeat = DateTime.now().millisecondsSinceEpoch.toDouble();
    currentBeat = beatList.length - 1;
    isPlaying = true;
    doBeat();

    Screen.keepOn(true);
    statusUpdate.notifyListeners();

    // we want a high resolution metronome
    _timer = Timer.periodic(Duration(microseconds: 100), (_) => doTick());
    // doLoop();
  }

  void stop() {
    _timer?.cancel();
    throbberData.pct = 0;
    throbberData.rightward = true;
    throbberUpdate.notifyListeners();

    currentBeat = 0;
    isPlaying = false;
    Screen.keepOn(false);
    statusUpdate.notifyListeners();
  }

  void incTempo(int inc) {
    // see the setter for additional things that happen
    // when setting the tempo
    tempo = max(40, min(tempo + inc, 300));
  }

  void incBeats(int inc) {
    var newBeatList = beatList.toList();
    if (inc < 0) {
      int newlength = newBeatList.length + inc;
      if (newlength < 1) newlength = 1;
      newBeatList.length = newlength;
    } else {
      for (var i = 0; i < inc; i++) newBeatList.add(1);
    }
    beatList = newBeatList;
  }
}
