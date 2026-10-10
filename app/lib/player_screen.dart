import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'models.dart';
import 'providers.dart';

/// Pun ekran plejera. Daljinski: gore/dolje ili CH+/CH- mijenjaju kanal,
/// OK prikazuje info, play/pause staje/pušta. Na telefonu: dodir i prevlačenje gore/dolje.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.source,
    required this.channels,
    required this.index,
  });

  final Source source;
  final List<Channel> channels;
  final int index;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final Player player = Player();
  late final VideoController controller = VideoController(player);
  final List<StreamSubscription<dynamic>> _subs = [];
  late int index = widget.index;
  String? error;
  bool loading = true;
  bool showUi = true;
  Timer? _hide;

  Channel get channel => widget.channels[index];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _subs.add(player.stream.error.listen((e) {
      if (mounted && e.isNotEmpty) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }));
    _subs.add(player.stream.buffering.listen((b) {
      if (mounted) setState(() => loading = b);
    }));
    _subs.add(player.stream.playing.listen((p) {
      if (mounted && p) setState(() => error = null);
    }));
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hide?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    player.dispose();
    super.dispose();
  }

  void _poke() {
    _hide?.cancel();
    if (!showUi) setState(() => showUi = true);
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => showUi = false);
    });
  }

  Future<void> _play() async {
    if (!mounted) return;
    final c = channel;
    setState(() {
      loading = true;
      error = null;
    });
    _poke();
    try {
      final r = await Repo.resolve(widget.source, c);
      if (!mounted || !identical(c, channel)) return;
      await player.open(Media(r.url, httpHeaders: r.headers));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = errMsg(e);
        loading = false;
      });
    }
  }

  void _step(int d) {
    final n = widget.channels.length;
    if (n == 0) return;
    setState(() => index = (index + d + n) % n);
    _play();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.channelDown) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.channelUp) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      showUi ? setState(() => showUi = false) : _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.mediaPlayPause) {
      player.playOrPause();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _overlay() {
    final c = channel;
    return SafeArea(
      child: Column(
        children: [
          DecoratedBox(
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
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Text(
                    '${c.num > 0 ? '${c.num}. ' : ''}${c.name}  ·  ${c.group}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => _step(-1),
                ),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: player.state.playing,
                  builder: (context, snap) => IconButton(
                    iconSize: 44,
                    icon: Icon((snap.data ?? false) ? Icons.pause : Icons.play_arrow),
                    onPressed: () {
                      player.playOrPause();
                      _poke();
                    },
                  ),
                ),
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => _step(1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showUi ? setState(() => showUi = false) : _poke(),
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -300) {
              _step(1);
            } else if (v > 300) {
              _step(-1);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: controller, controls: NoVideoControls),
              if (loading && error == null)
                const Center(child: CircularProgressIndicator()),
              if (error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 40),
                        const SizedBox(height: 8),
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _play, child: const Text('Pokušaj ponovo')),
                      ],
                    ),
                  ),
                ),
              AnimatedOpacity(
                opacity: showUi ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(ignoring: !showUi, child: _overlay()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
