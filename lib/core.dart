import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Configuração e cores
// ---------------------------------------------------------------------------

const bg = Color(0xFF080B12);
const panel = Color(0xFF141C2B);
const tileColor = Color(0xFF1B2335);
const blue = Color(0xFF287BFF);
const muted = Color(0xFF91A0B7);
const defaultAccent = Color(0xFF172338);

const kAudiusBase = 'https://api.audius.co/v1';
const kAppName = 'WaveMusic';

/// Opcional: chave gratuita da Audius (audius.co/settings -> "Manage Your
/// Apps"). Sem chave o app funciona, só com limite de uso menor.
const kAudiusApiKey = '';

const kGenres = <String>[
  'Electronic',
  'Hip-Hop/Rap',
  'Pop',
  'Rock',
  'Lo-Fi',
  'R&B/Soul',
  'Jazz',
  'Latin',
  'Alternative',
  'Metal',
  'Folk',
  'Funk',
  'Reggae',
  'Ambient',
  'Trap',
  'House',
];

/// Instâncias únicas usadas pelo app inteiro (criadas só no primeiro uso,
/// depois do init do áudio em segundo plano).
final PlayerController playerCtrl = PlayerController();
final Library libStore = Library();

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.uri,
    this.artwork,
    this.durationSec,
    this.genre,
    this.isLocal = false,
  });

  final String id;
  final String title;
  final String artist;
  final String uri;
  final String? artwork;
  final int? durationSec;
  final String? genre;
  final bool isLocal;

  factory Track.fromAudius(Map<String, dynamic> j) {
    final id = j['id'].toString();
    final art = j['artwork'];
    String? artwork;
    if (art is Map) {
      artwork = (art['480x480'] ?? art['150x150'] ?? art['1000x1000'])
          ?.toString();
    }
    final user = j['user'];
    final duration = j['duration'];
    return Track(
      id: id,
      title: (j['title'] ?? 'Sem título').toString(),
      artist: user is Map ? (user['name'] ?? 'Artista').toString() : 'Artista',
      uri: '$kAudiusBase/tracks/$id/stream?app_name=$kAppName',
      artwork: artwork,
      durationSec: duration is num ? duration.toInt() : null,
      genre: j['genre']?.toString(),
    );
  }

  factory Track.local(String path, String fileName) => Track(
        id: 'local:$path',
        title: fileName.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        artist: 'Arquivo local',
        uri: Uri.file(path).toString(),
        isLocal: true,
      );

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'].toString(),
        title: j['title'].toString(),
        artist: j['artist'].toString(),
        uri: j['uri'].toString(),
        artwork: j['artwork']?.toString(),
        durationSec: j['durationSec'] is num
            ? (j['durationSec'] as num).toInt()
            : null,
        genre: j['genre']?.toString(),
        isLocal: j['isLocal'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'uri': uri,
        'artwork': artwork,
        'durationSec': durationSec,
        'genre': genre,
        'isLocal': isLocal,
      };
}

class Playlist {
  Playlist({required this.id, required this.name, List<Track>? tracks})
      : tracks = tracks ?? <Track>[];

  final String id;
  String name;
  final List<Track> tracks;

  List<String?> get covers => tracks
      .map((t) => t.artwork)
      .where((a) => a != null && a.isNotEmpty)
      .take(4)
      .toList();

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'].toString(),
        name: j['name'].toString(),
        tracks: (j['tracks'] as List)
            .whereType<Map>()
            .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };
}

// ---------------------------------------------------------------------------
// API da Audius (streaming)
// ---------------------------------------------------------------------------

class AudiusApi {
  static Map<String, String> get _headers => kAudiusApiKey.isEmpty
      ? <String, String>{}
      : <String, String>{'Authorization': 'Bearer $kAudiusApiKey'};

  static Future<List<Track>> _get(String path, Map<String, String> query) async {
    final uri = Uri.parse('$kAudiusBase$path')
        .replace(queryParameters: {...query, 'app_name': kAppName});
    final res = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('A Audius respondeu ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map ? body['data'] : null;
    if (data is! List) return <Track>[];
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['is_streamable'] != false)
        .map(Track.fromAudius)
        .toList();
  }

  static Future<List<Track>> trending({
    String? genre,
    String time = 'week',
    int limit = 30,
  }) =>
      _get('/tracks/trending', {
        'time': time,
        'limit': '$limit',
        if (genre != null) 'genre': genre,
      });

  static Future<List<Track>> search(String query) =>
      _get('/tracks/search', {'query': query, 'limit': '30'});
}

// ---------------------------------------------------------------------------
// Letras sincronizadas (LRCLIB - base aberta e gratuita)
// ---------------------------------------------------------------------------

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({this.synced = const [], this.plain});
  final List<LyricLine> synced;
  final String? plain;

  static const Lyrics empty = Lyrics();

  bool get isEmpty => synced.isEmpty && (plain == null || plain!.trim().isEmpty);
}

class LrcLib {
  static List<LyricLine> parseLrc(String raw) {
    final out = <LyricLine>[];
    final re = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    for (final line in raw.split('\n')) {
      final matches = re.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final text = line.substring(matches.last.end).trim();
      for (final m in matches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        final frac = m.group(3);
        var ms = 0;
        if (frac != null) {
          ms = int.parse(frac.padRight(3, '0').substring(0, 3));
        }
        out.add(LyricLine(
          Duration(minutes: minutes, seconds: seconds, milliseconds: ms),
          text,
        ));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  static Future<Lyrics> fetch(Track track) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': track.title,
      if (!track.isLocal) 'artist_name': track.artist,
    });
    final res = await http
        .get(uri, headers: {'User-Agent': 'WaveMusic/0.4.0'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return Lyrics.empty;
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! List) return Lyrics.empty;
    String? plain;
    for (final item in body.whereType<Map>()) {
      final syncedRaw = item['syncedLyrics'];
      if (syncedRaw is String && syncedRaw.trim().isNotEmpty) {
        final lines = parseLrc(syncedRaw);
        if (lines.isNotEmpty) {
          return Lyrics(
            synced: lines,
            plain: item['plainLyrics'] is String
                ? item['plainLyrics'] as String
                : null,
          );
        }
      }
      final plainRaw = item['plainLyrics'];
      if (plain == null && plainRaw is String && plainRaw.trim().isNotEmpty) {
        plain = plainRaw;
      }
    }
    return plain == null ? Lyrics.empty : Lyrics(plain: plain);
  }
}

// ---------------------------------------------------------------------------
// Cor dominante da capa (para o fundo do mini player e do player)
// ---------------------------------------------------------------------------

final Map<String, Color> _coverCache = {};

Future<Color?> coverColor(String? url) async {
  if (url == null || url.isEmpty) return null;
  final cached = _coverCache[url];
  if (cached != null) return cached;

  final completer = Completer<Color?>();
  final stream = NetworkImage(url).resolve(const ImageConfiguration());
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo info, bool synchronousCall) async {
      stream.removeListener(listener);
      try {
        final data =
            await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }
        final w = info.image.width;
        final h = info.image.height;
        final stepX = max(1, w ~/ 12);
        final stepY = max(1, h ~/ 12);
        double r = 0, g = 0, b = 0, n = 0;
        for (var y = 0; y < h; y += stepY) {
          for (var x = 0; x < w; x += stepX) {
            final o = (y * w + x) * 4;
            r += data.getUint8(o);
            g += data.getUint8(o + 1);
            b += data.getUint8(o + 2);
            n++;
          }
        }
        if (n == 0) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }
        final avg = Color.fromARGB(
            255, (r / n).round(), (g / n).round(), (b / n).round());
        final hsl = HSLColor.fromColor(avg);
        final color = hsl
            .withLightness(hsl.lightness.clamp(.14, .30).toDouble())
            .withSaturation(max(hsl.saturation, .35).clamp(0.0, .8).toDouble())
            .toColor();
        if (!completer.isCompleted) completer.complete(color);
      } catch (_) {
        if (!completer.isCompleted) completer.complete(null);
      }
    },
    onError: (Object error, StackTrace? stackTrace) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(null);
    },
  );
  stream.addListener(listener);
  final color = await completer.future
      .timeout(const Duration(seconds: 6), onTimeout: () => null);
  if (color != null) _coverCache[url] = color;
  return color;
}

// ---------------------------------------------------------------------------
// Biblioteca salva no aparelho
// ---------------------------------------------------------------------------

class Library extends ChangeNotifier {
  final List<Track> favorites = [];
  final List<Track> locals = [];
  final List<Playlist> playlists = [];
  final List<Track> history = [];

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _readTracks(prefs.getStringList('favorites'), favorites);
      _readTracks(prefs.getStringList('locals'), locals);
      _readTracks(prefs.getStringList('history'), history);
      final rawPlaylists = prefs.getStringList('playlists');
      if (rawPlaylists != null) {
        for (final item in rawPlaylists) {
          try {
            playlists.add(
                Playlist.fromJson(jsonDecode(item) as Map<String, dynamic>));
          } catch (_) {}
        }
      }
      notifyListeners();
    } catch (_) {
      // Sem acesso ao armazenamento: segue com a biblioteca vazia.
    }
  }

  void _readTracks(List<String>? raw, List<Track> target) {
    if (raw == null) return;
    for (final item in raw) {
      try {
        target.add(Track.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> enc(List<Track> l) =>
          l.map((t) => jsonEncode(t.toJson())).toList();
      await prefs.setStringList('favorites', enc(favorites));
      await prefs.setStringList('locals', enc(locals));
      await prefs.setStringList('history', enc(history));
      await prefs.setStringList(
          'playlists', playlists.map((p) => jsonEncode(p.toJson())).toList());
    } catch (_) {}
  }

  // Favoritas -------------------------------------------------------------

  bool isFavorite(String id) => favorites.any((t) => t.id == id);

  Future<void> toggleFavorite(Track track) async {
    if (isFavorite(track.id)) {
      favorites.removeWhere((t) => t.id == track.id);
    } else {
      favorites.insert(0, track);
    }
    notifyListeners();
    await _save();
  }

  // Arquivos locais ---------------------------------------------------------

  Future<void> addLocals(List<Track> items) async {
    for (final t in items) {
      if (!locals.any((e) => e.id == t.id)) locals.add(t);
    }
    notifyListeners();
    await _save();
  }

  Future<void> removeLocal(String id) async {
    locals.removeWhere((t) => t.id == id);
    notifyListeners();
    await _save();
  }

  // Playlists ---------------------------------------------------------------

  Playlist? playlistById(String id) {
    for (final p in playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<Playlist> createPlaylist(String name) async {
    final p = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
    );
    playlists.add(p);
    notifyListeners();
    await _save();
    return p;
  }

  Future<void> deletePlaylist(String id) async {
    playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> addToPlaylist(Playlist p, Track t) async {
    if (!p.tracks.any((e) => e.id == t.id)) p.tracks.add(t);
    notifyListeners();
    await _save();
  }

  Future<void> removeFromPlaylist(Playlist p, String trackId) async {
    p.tracks.removeWhere((t) => t.id == trackId);
    notifyListeners();
    await _save();
  }

  // Histórico ---------------------------------------------------------------

  Future<void> addHistory(Track t) async {
    history.removeWhere((e) => e.id == t.id);
    history.insert(0, t);
    if (history.length > 100) history.removeRange(100, history.length);
    notifyListeners();
    await _save();
  }

  List<Track> get recents => history.take(20).toList();

  /// Gênero mais frequente no histórico (para "Mais para você").
  String? get topGenre {
    final counts = <String, int>{};
    for (final t in history) {
      final g = t.genre;
      if (g == null || g.isEmpty) continue;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    String? best;
    var bestCount = 0;
    counts.forEach((g, c) {
      if (c > bestCount) {
        best = g;
        bestCount = c;
      }
    });
    return best;
  }
}

// ---------------------------------------------------------------------------
// Controle do player
// ---------------------------------------------------------------------------

enum WaveRepeat { off, all, one }

class PlayerController extends ChangeNotifier {
  PlayerController() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]),
    );
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
    _player.playingStream.listen((_) => notifyListeners());
  }

  final AndroidEqualizer equalizer = AndroidEqualizer();
  late final AudioPlayer _player;
  final Random _rng = Random();
  final Map<String, Lyrics> _lyricsCache = {};
  Timer? _sleepTimer;

  AudioPlayer get player => _player;

  List<Track> queue = [];
  int index = -1;
  bool shuffle = false;
  WaveRepeat repeat = WaveRepeat.off;
  bool loading = false;
  String? error;
  Color accent = defaultAccent;
  double volume = 1.0;
  DateTime? sleepAt;

  /// Chamado quando uma faixa começa a tocar (usado para o histórico).
  void Function(Track track)? onTrackStart;

  Track? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  bool get playing => _player.playing;

  Future<void> playQueue(List<Track> tracks, int start) async {
    if (tracks.isEmpty || start < 0 || start >= tracks.length) return;
    queue = List<Track>.of(tracks);
    await _load(start);
  }

  Future<void> playShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    shuffle = true;
    await playQueue(tracks, _rng.nextInt(tracks.length));
  }

  Future<void> playNext(Track track) async {
    if (queue.isEmpty || current == null) {
      await playQueue([track], 0);
      return;
    }
    queue.insert(index + 1, track);
    notifyListeners();
  }

  Future<void> addToQueue(Track track) async {
    if (queue.isEmpty || current == null) {
      await playQueue([track], 0);
      return;
    }
    queue.add(track);
    notifyListeners();
  }

  Future<void> _load(int i) async {
    if (i < 0 || i >= queue.length) return;
    index = i;
    loading = true;
    error = null;
    notifyListeners();
    final t = queue[i];
    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(t.uri),
          tag: MediaItem(
            id: t.id,
            title: t.title,
            artist: t.artist,
            artUri: t.artwork == null ? null : Uri.parse(t.artwork!),
          ),
        ),
      );
      unawaited(_player.play());
      onTrackStart?.call(t);
      coverColor(t.artwork).then((c) {
        if (current?.id == t.id) {
          accent = c ?? defaultAccent;
          notifyListeners();
        }
      });
    } catch (e) {
      error = 'Não foi possível tocar esta faixa: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _onCompleted() async {
    if (repeat == WaveRepeat.one) {
      await _player.seek(Duration.zero);
      unawaited(_player.play());
      return;
    }
    await next(auto: true);
  }

  Future<void> next({bool auto = false}) async {
    if (queue.isEmpty) return;
    int n;
    if (shuffle && queue.length > 1) {
      do {
        n = _rng.nextInt(queue.length);
      } while (n == index);
    } else {
      n = index + 1;
      if (n >= queue.length) {
        if (repeat == WaveRepeat.all || !auto) {
          n = 0;
        } else {
          await _player.pause();
          await _player.seek(Duration.zero);
          notifyListeners();
          return;
        }
      }
    }
    await _load(n);
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    await _load((index - 1 + queue.length) % queue.length);
  }

  Future<void> togglePlay() async {
    if (current == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      unawaited(_player.play());
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = WaveRepeat.values[(repeat.index + 1) % WaveRepeat.values.length];
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0).toDouble();
    await _player.setVolume(volume);
    notifyListeners();
  }

  /// Timer para dormir: pausa a música depois da duração escolhida.
  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt = null;
    if (duration != null) {
      sleepAt = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () async {
        await _player.pause();
        sleepAt = null;
        _sleepTimer = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<Lyrics> lyricsFor(Track track) async {
    final cached = _lyricsCache[track.id];
    if (cached != null) return cached;
    Lyrics result;
    try {
      result = await LrcLib.fetch(track);
    } catch (_) {
      return Lyrics.empty;
    }
    _lyricsCache[track.id] = result;
    return result;
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _player.dispose();
    super.dispose();
  }
}
