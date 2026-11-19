import 'package:flutter/material.dart';

import 'core.dart';

/// Painel de letras sincronizadas (cobre a área de conteúdo; o player do
/// YouTube continua visível embaixo).
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static const double _itemHeight = 52;

  final ScrollController _scroll = ScrollController();
  Future<Lyrics>? _future;
  String? _trackId;
  Stream<Duration>? _positions;
  int _lastIndex = -1;

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
  Widget build(BuildContext context) => Container(
        color: bg,
        child: ListenableBuilder(
          listenable: playerCtrl,
          builder: (context, _) {
            final track = playerCtrl.current;
            if (track == null) {
              return const Center(child: Text('Nada tocando'));
            }
            if (_trackId != track.id) {
              _trackId = track.id;
              _lastIndex = -1;
              _future = playerCtrl.lyricsFor(track);
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      IconButton(
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _body()),
              ],
            );
          },
        ),
      );

  Widget _body() => FutureBuilder<Lyrics>(
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
            padding: const EdgeInsets.all(20),
            child: Text(
              lyrics.plain ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.7),
            ),
          );
        },
      );

  Widget _synced(List<LyricLine> lines) {
    final yt = playerCtrl.yt;
    if (yt == null) return const SizedBox.shrink();
    _positions ??= yt.getCurrentPositionStream(
      period: const Duration(milliseconds: 500),
    );
    return StreamBuilder<Duration>(
      stream: _positions,
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
}
