import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'providers.dart';
import 'settings.dart';
import 'store.dart';
import 'subtitles.dart';
import 'util.dart';

class _Aspect {
  const _Aspect(this.label, this.ratio, this.fit);
  final String label;
  final double? ratio;
  final BoxFit fit;
}

const List<_Aspect> _aspects = [
  _Aspect('Automatski', null, BoxFit.contain),
  _Aspect('16:9', 16 / 9, BoxFit.fill),
  _Aspect('4:3', 4 / 3, BoxFit.fill),
  _Aspect('Razvuci na ekran', null, BoxFit.fill),
  _Aspect('Popuni (isječi)', null, BoxFit.cover),
];

/// Plejer: TV uživo, filmovi i epizode. Sve tipke se mogu podesiti u Postavkama.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.items,
    required this.index,
    this.fromStart = false,
  });

  final List<PlayItem> items;
  final int index;
  final bool fromStart;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final Player player = Player();
  late final VideoController controller = VideoController(player);
  final FocusNode _focus = FocusNode();
  final List<StreamSubscription<dynamic>> _subs = [];

  late int index = widget.index;
  int _prev = -1;
  int _gen = 0;
  int _retries = 0;

  String? error;
  bool loading = true;
  bool showUi = true;
  double volume = 100;
  bool muted = false;
  int aspect = 0;
  double rate = 1;
  int sleepMin = 0;
  String? toast;
  String digits = '';
  List<Programme> epg = [];

  Timer? _hide;
  Timer? _toastT;
  Timer? _digitT;
  Timer? _sleepT;
  Timer? _saveT;

  bool _resumed = false;
  late bool _fromStart = widget.fromStart;
  bool _subChosen = false;
  double _dtx = 0;
  List<SubOption>? _online;

  PlayItem get cur => widget.items[index];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    WakelockPlus.enable();

    _subs.add(player.stream.error.listen((e) {
      if (!mounted || e.isEmpty) return;
      if (cur.live && _retries < 3) {
        _retries++;
        setState(() => loading = true);
        final g = _gen;
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted && g == _gen) _play();
        });
        return;
      }
      setState(() {
        error = e;
        loading = false;
      });
    }));
    _subs.add(player.stream.buffering.listen((b) {
      if (mounted) setState(() => loading = b);
    }));
    _subs.add(player.stream.playing.listen((p) {
      if (mounted && p) {
        _retries = 0;
        if (error != null) setState(() => error = null);
      }
    }));
    _subs.add(player.stream.duration.listen(_onDuration));
    _subs.add(player.stream.tracks.listen(_onTracks));
    _subs.add(player.stream.completed.listen((c) {
      if (!mounted || !c || cur.live) return;
      final key = cur.historyKey;
      if (key != null) Store.setPos(key, 0);
      if (index < widget.items.length - 1) _step(1);
    }));

    _saveT = Timer.periodic(const Duration(seconds: 5), (_) => _saveNow());
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _saveNow();
    for (final s in _subs) {
      s.cancel();
    }
    for (final t in [_hide, _toastT, _digitT, _sleepT, _saveT]) {
      t?.cancel();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (isMobile) SystemChrome.setPreferredOrientations(const []);
    if (isDesktop) windowManager.setFullScreen(false);
    WakelockPlus.disable();
    _focus.dispose();
    player.dispose();
    super.dispose();
  }

  // ---------- reprodukcija ----------
  Future<void> _play() async {
    if (!mounted) return;
    final it = cur;
    final gen = ++_gen;
    setState(() {
      loading = true;
      error = null;
      epg = [];
      _subChosen = false;
      _resumed = false;
      _online = null;
    });
    _poke();
    final hk = it.historyKey;
    if (hk != null) Store.pushRecent(hk);
    final ef = it.epg;
    if (ef != null) {
      ef().then((l) {
        if (mounted && gen == _gen) setState(() => epg = l);
      }).catchError((Object _) {});
    }
    try {
      final r = await it.resolve();
      if (!mounted || gen != _gen) return;
      await player.open(Media(r.url, httpHeaders: r.headers));
      if (!mounted || gen != _gen) return;
      await player.setVolume(muted ? 0 : volume);
      await player.setRate(it.live ? 1 : rate);
      if (!it.live && AppSettings.I.autoSubs) _autoSubs(gen);
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        error = errMsg(e);
        loading = false;
      });
    }
  }

  void _saveNow() {
    final it = cur;
    final key = it.historyKey;
    if (it.live || key == null) return;
    final dur = player.state.duration;
    final pos = player.state.position;
    if (dur.inSeconds <= 0) return;
    final nearEnd = pos.inSeconds > dur.inSeconds - 30;
    Store.setPos(key, nearEnd ? 0 : pos.inMilliseconds);
  }

  void _onDuration(Duration d) {
    if (_resumed || d.inSeconds <= 0 || cur.live) return;
    _resumed = true;
    final key = cur.historyKey;
    if (key == null) return;
    if (_fromStart) {
      _fromStart = false;
      return;
    }
    final saved = Store.pos(key);
    if (saved > 10000 && saved < d.inMilliseconds - 30000) {
      player.seek(Duration(milliseconds: saved));
      _toast('Nastavljeno od ${fmtDur(Duration(milliseconds: saved))}');
    }
  }

  // ---------- titlovi ----------
  static const Map<String, List<String>> _langNames = {
    'bs': ['bs', 'bos', 'bosnian', 'bosanski'],
    'hr': ['hr', 'hrv', 'cro', 'croatian', 'hrvatski'],
    'sr': ['sr', 'srp', 'scc', 'srb', 'serbian', 'srpski'],
  };

  bool _isPrefLang(SubtitleTrack t) {
    final names = _langNames[AppSettings.I.subLang] ?? const <String>[];
    final l = (t.language ?? '').toLowerCase();
    final title = (t.title ?? '').toLowerCase();
    return names.contains(l) || names.any((n) => n.length > 3 && title.contains(n));
  }

  void _onTracks(Tracks t) {
    if (_subChosen || cur.live || !AppSettings.I.autoSubs) return;
    for (final s in t.subtitle) {
      if (s.id == 'auto' || s.id == 'no') continue;
      if (_isPrefLang(s)) {
        _subChosen = true;
        player.setSubtitleTrack(s);
        _toast('Titl: ${s.title ?? s.language ?? AppSettings.I.subLang.toUpperCase()}');
        return;
      }
    }
  }

  Future<List<SubOption>> _searchOnline() async {
    final it = cur;
    final r = await OpenSubs.search(
      it.subtitleQuery ?? it.title,
      year: it.year,
      season: it.season,
      episode: it.episode,
    );
    _online = r;
    return r;
  }

  Future<void> _applyOnline(SubOption o) async {
    final text = await OpenSubs.download(o);
    await player.setSubtitleTrack(SubtitleTrack.data(text, title: o.label, language: o.lang));
    _subChosen = true;
    _toast('Titl: ${o.lang.toUpperCase()}');
  }

  Future<void> _autoSubs(int gen) async {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted || gen != _gen || _subChosen) return;
    if (AppSettings.I.osKey.isEmpty) return;
    try {
      final list = await _searchOnline();
      if (!mounted || gen != _gen || _subChosen || list.isEmpty) return;
      await _applyOnline(list.first);
    } catch (_) {
      // Tihi neuspjeh; korisnik može ručno u izborniku Titlovi.
    }
  }

  // ---------- pomoćno ----------
  void _poke() {
    _hide?.cancel();
    if (!showUi) setState(() => showUi = true);
    _hide = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => showUi = false);
    });
  }

  void _toast(String t) {
    _toastT?.cancel();
    if (!mounted) return;
    setState(() => toast = t);
    _toastT = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => toast = null);
    });
  }

  void _step(int d) {
    final n = widget.items.length;
    if (n <= 1) return;
    _jump((index + d + n) % n);
  }

  void _jump(int i) {
    if (i < 0 || i >= widget.items.length || i == index) return;
    _saveNow();
    _prev = index;
    _retries = 0;
    setState(() => index = i);
    _play();
  }

  void _vol(double d) {
    volume = (volume + d).clamp(0, 100).toDouble();
    muted = false;
    player.setVolume(volume);
    _toast('Jačina ${volume.round()}%');
  }

  void _mute() {
    muted = !muted;
    player.setVolume(muted ? 0 : volume);
    _toast(muted ? 'Bez zvuka' : 'Zvuk uključen');
  }

  void _seek(int sec) {
    final dur = player.state.duration;
    var p = player.state.position + Duration(seconds: sec);
    if (p < Duration.zero) p = Duration.zero;
    if (dur > Duration.zero && p > dur) p = dur;
    player.seek(p);
    _toast('${sec > 0 ? '+' : ''}$sec s');
  }

  Future<void> _toggleFull() async {
    if (isDesktop) {
      final f = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!f);
      _toast(f ? 'Prozor' : 'Cijeli ekran');
    } else {
      setState(() => showUi = !showUi);
    }
  }

  void _cycleAspect() {
    setState(() => aspect = (aspect + 1) % _aspects.length);
    _toast('Omjer: ${_aspects[aspect].label}');
  }

  void _typeDigit(int d) {
    _digitT?.cancel();
    setState(() => digits = digits.length >= 4 ? '$d' : '$digits$d');
    _digitT = Timer(const Duration(milliseconds: 1800), () {
      final n = int.tryParse(digits);
      if (mounted) setState(() => digits = '');
      if (n == null) return;
      final i = widget.items.indexWhere((x) => x.num == n);
      if (i >= 0) {
        _jump(i);
      } else {
        _toast('Kanal $n ne postoji');
      }
    });
  }

  void _setSleep(int min) {
    _sleepT?.cancel();
    sleepMin = min;
    if (min > 0) {
      _sleepT = Timer(Duration(minutes: min), () {
        if (mounted) Navigator.maybePop(context);
      });
      _toast('Isključivanje za $min min');
    } else {
      _toast('Tajmer isključen');
    }
  }

  static final List<LogicalKeyboardKey> _digitKeys = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static final List<LogicalKeyboardKey> _numpadKeys = [
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  // ---------- tipke ----------
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final repeat = e is KeyRepeatEvent;
    final live = cur.live;
    final skip = AppSettings.I.skipSeconds;

    final di = _digitKeys.indexOf(k) >= 0 ? _digitKeys.indexOf(k) : _numpadKeys.indexOf(k);
    if (di >= 0 && live && widget.items.length > 1) {
      if (!repeat) _typeDigit(di);
      return KeyEventResult.handled;
    }

    // Stalne tipke daljinskog
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      if (!repeat) {
        if (showUi) {
          setState(() => showUi = false);
        } else {
          _poke();
        }
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.channelUp) {
      if (!repeat) _step(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.channelDown) {
      if (!repeat) _step(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      if (!repeat) {
        player.playOrPause();
        _poke();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      if (!live) _seek(skip * 3);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      if (!live) _seek(-skip * 3);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackNext) {
      if (!repeat) _step(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackPrevious) {
      if (!repeat) _step(-1);
      return KeyEventResult.handled;
    }

    final act = AppSettings.I.actionFor(k);
    if (act == null) return KeyEventResult.ignored;
    switch (act) {
      case 'volumeUp':
        _vol(5);
        break;
      case 'volumeDown':
        _vol(-5);
        break;
      case 'seekForward':
        if (live) {
          if (!repeat) _step(1);
        } else {
          _seek(skip);
          _poke();
        }
        break;
      case 'seekBack':
        if (live) {
          if (!repeat) _step(-1);
        } else {
          _seek(-skip);
          _poke();
        }
        break;
      default:
        if (repeat) return KeyEventResult.handled;
        switch (act) {
          case 'fullscreen':
            _toggleFull();
            break;
          case 'mute':
            _mute();
            break;
          case 'nextChannel':
            _step(1);
            break;
          case 'prevChannel':
            _step(-1);
            break;
          case 'lastChannel':
            if (_prev >= 0) {
              _jump(_prev);
            } else {
              _toast('Nema prethodnog kanala');
            }
            break;
          case 'playPause':
            player.playOrPause();
            _poke();
            break;
          case 'info':
            showUi ? setState(() => showUi = false) : _poke();
            break;
          case 'subtitles':
            _openTracks();
            break;
          case 'aspect':
            _cycleAspect();
            break;
          case 'back':
            Navigator.maybePop(context);
            break;
        }
    }
    return KeyEventResult.handled;
  }

  // ---------- izbornici ----------
  Future<void> _openTracks() async {
    _hide?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TracksSheet(
        player: player,
        cached: _online,
        onSearch: _searchOnline,
        onApply: _applyOnline,
      ),
    );
    if (mounted) {
      _focus.requestFocus();
      _poke();
    }
  }

  Future<void> _openProgram() async {
    _hide?.cancel();
    final now = DateTime.now();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: epg.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('Program za ovaj kanal nije dostupan.'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in epg)
                      ListTile(
                        selected: !now.isBefore(p.start) && now.isBefore(p.stop),
                        leading: Text('${hm(p.start)}\n${hm(p.stop)}', textAlign: TextAlign.center),
                        title: Text(p.title),
                        subtitle: p.desc.isEmpty
                            ? null
                            : Text(p.desc, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (mounted) {
      _focus.requestFocus();
      _poke();
    }
  }

  Future<void> _openMore() async {
    _hide?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Tajmer za isključivanje', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const [0, 15, 30, 60, 90])
                    ChoiceChip(
                      label: Text(m == 0 ? 'Isključen' : '$m min'),
                      selected: sleepMin == m,
                      onSelected: (_) {
                        _setSleep(m);
                        setS(() {});
                      },
                    ),
                ],
              ),
              if (!cur.live) ...[
                const SizedBox(height: 16),
                Text('Brzina reprodukcije', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final r in const [0.75, 1.0, 1.25, 1.5, 2.0])
                      ChoiceChip(
                        label: Text('${r}x'),
                        selected: rate == r,
                        onSelected: (_) {
                          rate = r;
                          player.setRate(r);
                          setS(() {});
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text('Omjer slike', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < _aspects.length; i++)
                    ChoiceChip(
                      label: Text(_aspects[i].label),
                      selected: aspect == i,
                      onSelected: (_) {
                        setState(() => aspect = i);
                        setS(() {});
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) {
      _focus.requestFocus();
      _poke();
    }
  }

  // ---------- prikaz ----------
  Widget _liveInfo() {
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final i = epg.indexWhere((p) => !now.isBefore(p.start) && now.isBefore(p.stop));
    final Programme? pNow = i >= 0 ? epg[i] : null;
    Programme? pNext;
    if (i >= 0) {
      if (i + 1 < epg.length) pNext = epg[i + 1];
    } else {
      for (final p in epg) {
        if (p.start.isAfter(now)) {
          pNext = p;
          break;
        }
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pNow != null) ...[
            Text('SADA  ${hm(pNow.start)}–${hm(pNow.stop)}',
                style: tt.labelSmall?.copyWith(color: Colors.white70)),
            Text(pNow.title, style: tt.titleMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: pNow.progress(now), minHeight: 4),
          ] else
            Text('Program nije dostupan', style: tt.bodyMedium?.copyWith(color: Colors.white70)),
          if (pNext != null) ...[
            const SizedBox(height: 8),
            Text('SLIJEDI  ${hm(pNext.start)}  ${pNext.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: Colors.white70)),
          ],
        ],
      ),
    );
  }

  Widget _vodBar() {
    final multi = widget.items.length > 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: player.state.position,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              final dur = player.state.duration;
              final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
              final v = pos.inMilliseconds.clamp(0, maxMs).toDouble();
              return Row(
                children: [
                  Text(fmtDur(pos), style: const TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: v,
                      max: maxMs.toDouble(),
                      onChanged: (x) {
                        player.seek(Duration(milliseconds: x.round()));
                        _poke();
                      },
                    ),
                  ),
                  Text(fmtDur(dur), style: const TextStyle(color: Colors.white)),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (multi)
                IconButton(
                  iconSize: 32,
                  color: Colors.white,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => _step(-1),
                ),
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: const Icon(Icons.replay_10),
                onPressed: () => _seek(-AppSettings.I.skipSeconds),
              ),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (context, snap) => IconButton(
                  iconSize: 48,
                  color: Colors.white,
                  icon: Icon((snap.data ?? false) ? Icons.pause_circle : Icons.play_circle),
                  onPressed: () {
                    player.playOrPause();
                    _poke();
                  },
                ),
              ),
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: const Icon(Icons.forward_10),
                onPressed: () => _seek(AppSettings.I.skipSeconds),
              ),
              if (multi)
                IconButton(
                  iconSize: 32,
                  color: Colors.white,
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => _step(1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overlay() {
    final it = cur;
    return SafeArea(
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${it.num > 0 ? '${it.num}  ' : ''}${it.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      if (it.subtitle.isNotEmpty)
                        Text(it.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                if (it.live)
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Program',
                    icon: const Icon(Icons.event_note),
                    onPressed: _openProgram,
                  ),
                IconButton(
                  color: Colors.white,
                  tooltip: 'Titlovi i audio',
                  icon: const Icon(Icons.subtitles),
                  onPressed: _openTracks,
                ),
                IconButton(
                  color: Colors.white,
                  tooltip: 'Omjer slike',
                  icon: const Icon(Icons.aspect_ratio),
                  onPressed: _cycleAspect,
                ),
                IconButton(
                  color: Colors.white,
                  tooltip: muted ? 'Uključi zvuk' : 'Utišaj',
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  onPressed: _mute,
                ),
                if (isDesktop)
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Cijeli ekran',
                    icon: const Icon(Icons.fullscreen),
                    onPressed: _toggleFull,
                  ),
                IconButton(
                  color: Colors.white,
                  tooltip: 'Više',
                  icon: const Icon(Icons.more_vert),
                  onPressed: _openMore,
                ),
              ],
            ),
          ),
          const Spacer(),
          if (it.live) _liveInfo() else _vodBar(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _aspects[aspect];
    final small = MediaQuery.sizeOf(context).shortestSide < 600;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) _vol(e.scrollDelta.dy < 0 ? 5 : -5);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showUi ? setState(() => showUi = false) : _poke(),
            onDoubleTapDown: (d) => _dtx = d.localPosition.dx,
            onDoubleTap: () {
              if (isDesktop) {
                _toggleFull();
                return;
              }
              if (cur.live) {
                player.playOrPause();
                return;
              }
              final w = MediaQuery.sizeOf(context).width;
              if (_dtx < w / 3) {
                _seek(-AppSettings.I.skipSeconds);
              } else if (_dtx > w * 2 / 3) {
                _seek(AppSettings.I.skipSeconds);
              } else {
                player.playOrPause();
              }
            },
            onVerticalDragEnd: (d) {
              if (!cur.live) return;
              final v = d.primaryVelocity ?? 0;
              if (v < -300) {
                _step(1);
              } else if (v > 300) {
                _step(-1);
              }
            },
            onVerticalDragUpdate: (d) {
              if (!cur.live) _vol(-d.delta.dy * 0.4);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fit: a.fit,
                  aspectRatio: a.ratio,
                  subtitleViewConfiguration: SubtitleViewConfiguration(
                    style: TextStyle(
                      height: 1.4,
                      fontSize: small ? 22 : 34,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      backgroundColor: const Color(0xAA000000),
                    ),
                    textAlign: TextAlign.center,
                    padding: const EdgeInsets.all(24),
                  ),
                ),
                if (loading && error == null) const Center(child: CircularProgressIndicator()),
                if (error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 44, color: Colors.white),
                          const SizedBox(height: 8),
                          Text(error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () {
                              _retries = 0;
                              _play();
                            },
                            child: const Text('Pokušaj ponovo'),
                          ),
                        ],
                      ),
                    ),
                  ),
                AnimatedOpacity(
                  opacity: showUi ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !showUi,
                    child: ExcludeFocus(child: _overlay()),
                  ),
                ),
                if (digits.isNotEmpty)
                  Positioned(
                    top: 24,
                    right: 28,
                    child: SafeArea(
                      child: Text(
                        digits,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                        ),
                      ),
                    ),
                  ),
                if (toast != null)
                  Positioned(
                    top: 90,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(200),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(toast!, style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Izbor audio zapisa i titlova (ugrađeni + online preko OpenSubtitles).
class _TracksSheet extends StatefulWidget {
  const _TracksSheet({
    required this.player,
    required this.cached,
    required this.onSearch,
    required this.onApply,
  });

  final Player player;
  final List<SubOption>? cached;
  final Future<List<SubOption>> Function() onSearch;
  final Future<void> Function(SubOption) onApply;

  @override
  State<_TracksSheet> createState() => _TracksSheetState();
}

class _TracksSheetState extends State<_TracksSheet> {
  List<SubOption>? online;
  bool busy = false;
  String? msg;

  @override
  void initState() {
    super.initState();
    online = widget.cached;
  }

  String _label(String? title, String? lang, String id) {
    final t = (title ?? '').trim();
    final l = (lang ?? '').trim();
    if (t.isNotEmpty && l.isNotEmpty) return '$t ($l)';
    if (t.isNotEmpty) return t;
    if (l.isNotEmpty) return l;
    return 'Zapis $id';
  }

  Future<void> _search() async {
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      final r = await widget.onSearch();
      if (!mounted) return;
      setState(() {
        online = r;
        busy = false;
        if (r.isEmpty) msg = 'Nema titlova za ovaj naslov (bs/hr/sr).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        msg = errMsg(e);
      });
    }
  }

  Future<void> _apply(SubOption o) async {
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      await widget.onApply(o);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        msg = errMsg(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final audio = p.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final subs = p.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final curA = p.state.track.audio.id;
    final curS = p.state.track.subtitle.id;
    final title = Theme.of(context).textTheme.titleSmall;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            if (audio.length > 1) ...[
              Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text('Audio', style: title)),
              for (final t in audio)
                ListTile(
                  dense: true,
                  title: Text(_label(t.title, t.language, t.id)),
                  trailing: curA == t.id ? const Icon(Icons.check) : null,
                  onTap: () {
                    p.setAudioTrack(t);
                    Navigator.pop(context);
                  },
                ),
            ],
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text('Titlovi', style: title)),
            ListTile(
              dense: true,
              title: const Text('Isključeno'),
              trailing: curS == 'no' ? const Icon(Icons.check) : null,
              onTap: () {
                p.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(context);
              },
            ),
            for (final t in subs)
              ListTile(
                dense: true,
                title: Text(_label(t.title, t.language, t.id)),
                trailing: curS == t.id ? const Icon(Icons.check) : null,
                onTap: () {
                  p.setSubtitleTrack(t);
                  Navigator.pop(context);
                },
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('Online titlovi (OpenSubtitles)', style: title),
            ),
            if (online == null)
              ListTile(
                dense: true,
                leading: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                title: const Text('Traži titlove (bosanski, hrvatski, srpski)'),
                onTap: busy ? null : _search,
              )
            else
              for (final o in online!.take(25))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.closed_caption_outlined),
                  title: Text(o.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: busy ? null : () => _apply(o),
                ),
            if (busy && online != null) const LinearProgressIndicator(),
            if (msg != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(msg!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
