import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'core.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Player completo
// ---------------------------------------------------------------------------

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  bool _showLyrics = false;
  bool _volumeHint = false;
  Timer? _hintTimer;

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  void _onVolumeDrag(DragUpdateDetails d) {
    playerCtrl.setVolume(playerCtrl.volume - d.delta.dy / 250);
    setState(() => _volumeHint = true);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _volumeHint = false);
    });
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([playerCtrl, libStore]),
          builder: (context, _) {
            final ctrl = playerCtrl;
            final track = ctrl.current;
            if (track == null) {
              return const Center(child: Text('Nada tocando'));
            }
            final fav = libStore.isFavorite(track.id);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ctrl.accent, bg],
                  stops: const [0.0, .85],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.keyboard_arrow_down,
                                size: 32),
                          ),
                          const Expanded(
                            child: Text('TOCANDO AGORA',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white70,
                                    letterSpacing: 2,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      Expanded(
                        child: _showLyrics
                            ? LyricsView(track: track)
                            : LayoutBuilder(
                                builder: (context, box) {
                                  final side = min(
                                          min(box.maxWidth, box.maxHeight),
                                          360.0)
                                      .toDouble();
                                  return Center(
                                    child: GestureDetector(
                                      onVerticalDragUpdate: _onVolumeDrag,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Art(
                                              url: track.artwork,
                                              size: side,
                                              radius: 22),
                                          if (_volumeHint)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 10),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                              child: Text(
                                                'Volume ${(ctrl.volume * 100).round()}%',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(track.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text(track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white70)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => libStore.toggleFavorite(track),
                            icon: Icon(
                              fav ? Icons.favorite : Icons.favorite_border,
                              color: fav ? Colors.pinkAccent : Colors.white70,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ProgressBar(fallbackSeconds: track.durationSec),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: ctrl.toggleShuffle,
                            icon: Icon(Icons.shuffle,
                                color: ctrl.shuffle ? blue : Colors.white70),
                          ),
                          IconButton(
                            onPressed: () => ctrl.previous(),
                            iconSize: 38,
                            icon: const Icon(Icons.skip_previous),
                          ),
                          ctrl.loading
                              ? const SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: Padding(
                                    padding: EdgeInsets.all(20),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 3),
                                  ),
                                )
                              : IconButton.filled(
                                  onPressed: ctrl.togglePlay,
                                  iconSize: 42,
                                  style: IconButton.styleFrom(
                                    backgroundColor: blue,
                                    foregroundColor: Colors.white,
                                    fixedSize: const Size(72, 72),
                                  ),
                                  icon: Icon(ctrl.playing
                                      ? Icons.pause
                                      : Icons.play_arrow),
                                ),
                          IconButton(
                            onPressed: () => ctrl.next(),
                            iconSize: 38,
                            icon: const Icon(Icons.skip_next),
                          ),
                          IconButton(
                            onPressed: ctrl.cycleRepeat,
                            icon: Icon(
                              ctrl.repeat == WaveRepeat.one
                                  ? Icons.repeat_one
                                  : Icons.repeat,
                              color: ctrl.repeat == WaveRepeat.off
                                  ? Colors.white70
                                  : blue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            tooltip: 'Letra',
                            onPressed: () =>
                                setState(() => _showLyrics = !_showLyrics),
                            icon: Icon(Icons.lyrics_outlined,
                                color: _showLyrics ? blue : Colors.white70),
                          ),
                          IconButton(
                            tooltip: 'Timer para dormir',
                            onPressed: () => showSleepSheet(context),
                            icon: Icon(Icons.bedtime_outlined,
                                color: ctrl.sleepAt != null
                                    ? blue
                                    : Colors.white70),
                          ),
                          IconButton(
                            tooltip: 'Equalizador',
                            onPressed: () => showEqualizerSheet(context),
                            icon: const Icon(Icons.equalizer,
                                color: Colors.white70),
                          ),
                          IconButton(
                            tooltip: 'Adicionar a uma playlist',
                            onPressed: () => showAddToPlaylist(context, track),
                            icon: const Icon(Icons.playlist_add,
                                color: Colors.white70),
                          ),
                          IconButton(
                            tooltip: 'Modo moto',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => const MotoModePage()),
                            ),
                            icon: const Icon(Icons.two_wheeler,
                                color: Colors.white70),
                          ),
                        ],
                      ),
                      Text(
                        ctrl.sleepAt != null
                            ? 'Desliga às ${_hhmm(ctrl.sleepAt!)}'
                            : (track.isLocal
                                ? 'Arquivo do seu celular'
                                : 'Streaming por Audius • crédito aos artistas'),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}

// ---------------------------------------------------------------------------
// Letras sincronizadas
// ---------------------------------------------------------------------------

class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.track});

  final Track track;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const double _itemHeight = 52;

  final ScrollController _scroll = ScrollController();
  late Future<Lyrics> _future;
  int _lastIndex = -1;

  @override
  void initState() {
    super.initState();
    _future = playerCtrl.lyricsFor(widget.track);
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _lastIndex = -1;
      _future = playerCtrl.lyricsFor(widget.track);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _indexFor(List<LyricLine> lines, Duration pos) {
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Lyrics>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final lyrics = snapshot.data ?? Lyrics.empty;
          if (lyrics.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Letra não encontrada para esta música.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }
          if (lyrics.synced.isNotEmpty) return _synced(lyrics.synced);
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              lyrics.plain ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.7),
            ),
          );
        },
      );

  Widget _synced(List<LyricLine> lines) => StreamBuilder<Duration>(
        stream: playerCtrl.player.positionStream,
        builder: (context, snapshot) {
          final idx = _indexFor(lines, snapshot.data ?? Duration.zero);
          if (idx != _lastIndex) {
            _lastIndex = idx;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_scroll.hasClients) return;
              final target = (idx * _itemHeight) -
                  (_scroll.position.viewportDimension / 2) +
                  _itemHeight / 2;
              _scroll.animateTo(
                target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
              );
            });
          }
          return ListView.builder(
            controller: _scroll,
            itemExtent: _itemHeight,
            itemCount: lines.length,
            itemBuilder: (context, i) {
              final current = i == idx;
              return GestureDetector(
                onTap: () => playerCtrl.seek(lines[i].time),
                child: Center(
                  child: Text(
                    lines[i].text.isEmpty ? '♪' : lines[i].text,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: current ? 20 : 16,
                      fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                      color: current ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
}

// ---------------------------------------------------------------------------
// Timer para dormir
// ---------------------------------------------------------------------------

void showSleepSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: panel,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Timer para dormir',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final m in const [15, 30, 45, 60])
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text('$m minutos'),
              onTap: () {
                playerCtrl.setSleepTimer(Duration(minutes: m));
                Navigator.pop(sheetContext);
                showSnack(context, 'A música para em $m minutos');
              },
            ),
          if (playerCtrl.sleepAt != null)
            ListTile(
              leading: const Icon(Icons.timer_off_outlined),
              title: const Text('Cancelar timer'),
              onTap: () {
                playerCtrl.setSleepTimer(null);
                Navigator.pop(sheetContext);
                showSnack(context, 'Timer cancelado');
              },
            ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Equalizador (Android)
// ---------------------------------------------------------------------------

void showEqualizerSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: panel,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const EqualizerSheet(),
  );
}

class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key});

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  AndroidEqualizerParameters? _params;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final params = await playerCtrl.equalizer.parameters
          .timeout(const Duration(seconds: 5));
      final enabled = playerCtrl.equalizer.enabled;
      if (!mounted) return;
      setState(() {
        _params = params;
        _enabled = enabled;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Equalizador indisponível neste aparelho: $e');
    }
  }

  String _label(double f) => f >= 1000
      ? '${(f / 1000).toStringAsFixed(f % 1000 == 0 ? 0 : 1)} kHz'
      : '${f.round()} Hz';

  void _preset(String kind) {
    final params = _params;
    if (params == null) return;
    final bands = params.bands;
    final n = bands.length;
    for (var i = 0; i < n; i++) {
      final pos = n <= 1 ? 0.0 : i / (n - 1);
      var gain = 0.0;
      if (kind == 'bass') gain = params.maxDecibels * 0.6 * (1 - pos);
      if (kind == 'treble') gain = params.maxDecibels * 0.6 * pos;
      bands[i].setGain(gain);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final params = _params;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Equalizador',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                Switch(
                  value: _enabled,
                  onChanged: params == null
                      ? null
                      : (v) async {
                          await playerCtrl.equalizer.setEnabled(v);
                          if (mounted) setState(() => _enabled = v);
                        },
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted)),
              )
            else if (params == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else ...[
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                      label: const Text('Zerar'),
                      onPressed: () => _preset('flat')),
                  ActionChip(
                      label: const Text('Graves'),
                      onPressed: () => _preset('bass')),
                  ActionChip(
                      label: const Text('Agudos'),
                      onPressed: () => _preset('treble')),
                ],
              ),
              const SizedBox(height: 6),
              for (final band in params.bands)
                Row(
                  children: [
                    SizedBox(
                      width: 66,
                      child: Text(_label(band.centerFrequency),
                          style: const TextStyle(color: muted, fontSize: 12)),
                    ),
                    Expanded(
                      child: Slider(
                        value: band.gain
                            .clamp(params.minDecibels, params.maxDecibels)
                            .toDouble(),
                        min: params.minDecibels,
                        max: params.maxDecibels,
                        onChanged: _enabled
                            ? (v) {
                                band.setGain(v);
                                setState(() {});
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modo moto: botões enormes, contraste alto, feito para usar de luva
// ---------------------------------------------------------------------------

class MotoModePage extends StatelessWidget {
  const MotoModePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: playerCtrl,
            builder: (context, _) {
              final ctrl = playerCtrl;
              final track = ctrl.current;
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 30),
                        ),
                        const Expanded(
                          child: Text('MODO MOTO',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  letterSpacing: 3,
                                  fontWeight: FontWeight.w800,
                                  color: blue)),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track?.title ?? 'Nada tocando',
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 30, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              track?.artist ?? 'Escolha uma música',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 20, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _BigButton(
                            icon: Icons.skip_previous,
                            onTap: () => ctrl.previous(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _BigButton(
                            icon: ctrl.playing ? Icons.pause : Icons.play_arrow,
                            color: blue,
                            onTap: () => ctrl.togglePlay(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BigButton(
                            icon: Icons.skip_next,
                            onTap: () => ctrl.next(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _BigButton(
                            icon: Icons.volume_down,
                            height: 90,
                            onTap: () => ctrl.setVolume(ctrl.volume - .1),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            '${(ctrl.volume * 100).round()}%',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ),
                        Expanded(
                          child: _BigButton(
                            icon: Icons.volume_up,
                            height: 90,
                            onTap: () => ctrl.setVolume(ctrl.volume + .1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.onTap,
    this.color = tileColor,
    this.height = 120,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Center(child: Icon(icon, size: 60, color: Colors.white)),
          ),
        ),
      );
}
