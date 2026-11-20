import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart'
    show
        PlayerState,
        YoutubePlayerController,
        YoutubePlayerParams,
        YoutubePlayerValue;

// ---------------------------------------------------------------------------
// Configuração e cores
// ---------------------------------------------------------------------------

const bg = Color(0xFF080B12);
const panel = Color(0xFF141C2B);
const tileColor = Color(0xFF1B2335);
const blue = Color(0xFF287BFF);
const muted = Color(0xFF91A0B7);
const defaultAccent = Color(0xFF172338);

/// Gêneros do "Explorar": nome na tela -> o que é buscado no YouTube.
const kGenres = <String, String>{
  'Sertanejo': 'sertanejo as melhores',
  'Funk': 'funk brasil as melhores',
  'Pagode': 'pagode as melhores',
  'MPB': 'mpb as melhores',
  'Rock nacional': 'rock nacional as melhores',
  'Rap nacional': 'rap nacional as melhores',
  'Forró': 'forró as melhores',
  'Gospel': 'gospel as melhores',
  'Pop': 'pop hits',
  'Eletrônica': 'música eletrônica hits',
  'Samba': 'samba as melhores',
  'Reggae': 'reggae as melhores',
};

/// Instâncias únicas usadas pelo app inteiro.
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
    this.artwork,
    this.channelId,
  });

  /// ID do vídeo no YouTube.
  final String id;
  final String title;
  final String artist;
  final String? artwork;
  final String? channelId;

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'].toString(),
        title: j['title'].toString(),
        artist: j['artist'].toString(),
        artwork: j['artwork']?.toString(),
        channelId: j['channelId']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artwork': artwork,
        'channelId': channelId,
      };
}

class PlaylistInfo {
  const PlaylistInfo({
    required this.id,
    required this.title,
    required this.channel,
    this.artwork,
  });

  final String id;
  final String title;
  final String channel;
  final String? artwork;

  factory PlaylistInfo.fromJson(Map<String, dynamic> j) => PlaylistInfo(
        id: j['id'].toString(),
        title: j['title'].toString(),
        channel: j['channel'].toString(),
        artwork: j['artwork']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channel': channel,
        'artwork': artwork,
      };
}

class ArtistStat {
  const ArtistStat(this.name, this.channelId, this.count);
  final String name;
  final String? channelId;
  final int count;
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
// API oficial do YouTube (YouTube Data API v3)
// ---------------------------------------------------------------------------

class MissingKeyException implements Exception {
  const MissingKeyException();
  @override
  String toString() => 'Falta a chave do YouTube.';
}

class YoutubeApiException implements Exception {
  const YoutubeApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class YoutubeApi {
  static final Map<String, List<Track>> _cache = {};
  static final Map<String, List<PlaylistInfo>> _playlistCache = {};
  static final Map<String, String> _avatarCache = {};

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  static String _cleanChannel(String? raw) {
    var s = _unescape(raw ?? 'Artista');
    s = s.replaceAll(RegExp(r'\s*-\s*Topic$'), '');
    return s.trim().isEmpty ? 'Artista' : s.trim();
  }

  static String _friendlyError(int status, dynamic body) {
    String message = 'Erro $status ao falar com o YouTube.';
    String? reason;
    if (body is Map && body['error'] is Map) {
      final err = body['error'] as Map;
      if (err['message'] != null) message = err['message'].toString();
      final errors = err['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        reason = (errors.first as Map)['reason']?.toString();
      }
    }
    if (reason == 'quotaExceeded' || reason == 'rateLimitExceeded') {
      return 'A cota diária gratuita do YouTube acabou. Volta amanhã ou '
          'crie outra chave.';
    }
    if (reason == 'keyInvalid' || message.contains('API key not valid')) {
      return 'Chave inválida. Confira a chave nas configurações.';
    }
    if (reason == 'accessNotConfigured' || reason == 'forbidden') {
      return 'Ative a "YouTube Data API v3" no projeto onde você criou a chave.';
    }
    return message;
  }

  static String _hash(String s) {
    var h = 5381;
    for (final c in s.codeUnits) {
      h = ((h * 33) ^ c) & 0x7fffffff;
    }
    return h.toRadixString(36);
  }

  /// Cache em disco com validade: poupa a cota diária da API.
  static Future<List<Map<String, dynamic>>> _persisted(
    String key,
    Duration ttl,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    SharedPreferences? prefs;
    final storageKey = 'cache_${_hash(key)}';
    try {
      prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final t = m['t'] as int;
        if (DateTime.now().millisecondsSinceEpoch - t < ttl.inMilliseconds) {
          return (m['d'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
    final data = await fetch();
    try {
      await prefs?.setString(
        storageKey,
        jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'd': data}),
      );
    } catch (_) {}
    return data;
  }

  static Future<dynamic> _request(String path, Map<String, String> query) async {
    final key = libStore.youtubeKey;
    if (key.isEmpty) throw const MissingKeyException();
    final uri = Uri.https(
        'www.googleapis.com', '/youtube/v3$path', {...query, 'key': key});
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (res.statusCode != 200) {
      throw YoutubeApiException(_friendlyError(res.statusCode, body));
    }
    return body;
  }

  static String? _thumb(dynamic thumbs) {
    if (thumbs is! Map) return null;
    for (final k in const ['high', 'medium', 'default']) {
      final t = thumbs[k];
      if (t is Map && t['url'] != null) return t['url'].toString();
    }
    return null;
  }

  static List<Track> _parseTracks(dynamic body) {
    final items = body is Map ? body['items'] : null;
    if (items is! List) return <Track>[];
    final out = <Track>[];
    for (final item in items.whereType<Map>()) {
      final idRaw = item['id'];
      final id = idRaw is Map ? idRaw['videoId']?.toString() : idRaw?.toString();
      final snippet = item['snippet'];
      if (id == null || id.isEmpty || snippet is! Map) continue;
      out.add(Track(
        id: id,
        title: _unescape(snippet['title']?.toString() ?? 'Sem título'),
        artist: _cleanChannel(snippet['channelTitle']?.toString()),
        artwork: _thumb(snippet['thumbnails']),
        channelId: snippet['channelId']?.toString(),
      ));
    }
    return out;
  }

  static Future<List<Track>> _tracks(
    String path,
    Map<String, String> query, {
    Duration ttl = const Duration(hours: 12),
  }) async {
    final sorted = query.entries.map((e) => '${e.key}=${e.value}').toList()
      ..sort();
    final cacheKey = '$path?${sorted.join('&')}';
    final mem = _cache[cacheKey];
    if (mem != null) return mem;
    final maps = await _persisted(cacheKey, ttl, () async {
      final body = await _request(path, query);
      return _parseTracks(body).map((t) => t.toJson()).toList();
    });
    final tracks = maps.map(Track.fromJson).toList();
    _cache[cacheKey] = tracks;
    return tracks;
  }

  /// Músicas em alta no Brasil (custa só 1 unidade da cota diária).
  static Future<List<Track>> trendingBrazil() => _tracks(
        '/videos',
        {
          'part': 'snippet',
          'chart': 'mostPopular',
          'videoCategoryId': '10',
          'regionCode': 'BR',
          'maxResults': '25',
        },
        ttl: const Duration(hours: 3),
      );

  /// Busca músicas (categoria Música, só vídeos que podem ser incorporados).
  static Future<List<Track>> search(String query) => _tracks('/search', {
        'part': 'snippet',
        'type': 'video',
        'videoCategoryId': '10',
        'videoEmbeddable': 'true',
        'videoSyndicated': 'true',
        'regionCode': 'BR',
        'relevanceLanguage': 'pt',
        'maxResults': '25',
        'q': query,
      });

  /// Lançamentos recentes (últimas 3 semanas).
  static Future<List<Track>> latest() {
    final d = DateTime.now().toUtc().subtract(const Duration(days: 21));
    String two(int n) => n.toString().padLeft(2, '0');
    final after = '${d.year}-${two(d.month)}-${two(d.day)}T00:00:00Z';
    return _tracks('/search', {
      'part': 'snippet',
      'type': 'video',
      'videoCategoryId': '10',
      'videoEmbeddable': 'true',
      'videoSyndicated': 'true',
      'regionCode': 'BR',
      'relevanceLanguage': 'pt',
      'order': 'date',
      'publishedAfter': after,
      'maxResults': '25',
      'q': 'clipe oficial música nova lançamento',
    });
  }

  /// Playlists do YouTube (mostradas como "álbuns/playlists para você").
  static Future<List<PlaylistInfo>> searchPlaylists(String query) async {
    final cacheKey = 'playlists?$query';
    final mem = _playlistCache[cacheKey];
    if (mem != null) return mem;
    final maps = await _persisted(cacheKey, const Duration(hours: 24), () async {
      final body = await _request('/search', {
        'part': 'snippet',
        'type': 'playlist',
        'regionCode': 'BR',
        'relevanceLanguage': 'pt',
        'maxResults': '12',
        'q': query,
      });
      final items = body is Map ? body['items'] : null;
      final out = <Map<String, dynamic>>[];
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          final idRaw = item['id'];
          final id = idRaw is Map ? idRaw['playlistId']?.toString() : null;
          final snippet = item['snippet'];
          if (id == null || snippet is! Map) continue;
          out.add(PlaylistInfo(
            id: id,
            title: _unescape(snippet['title']?.toString() ?? 'Playlist'),
            channel: _cleanChannel(snippet['channelTitle']?.toString()),
            artwork: _thumb(snippet['thumbnails']),
          ).toJson());
        }
      }
      return out;
    });
    final list = maps.map(PlaylistInfo.fromJson).toList();
    _playlistCache[cacheKey] = list;
    return list;
  }

  /// Músicas de uma playlist (custa 1 unidade).
  static Future<List<Track>> playlistTracks(String playlistId) async {
    final cacheKey = 'playlistItems?$playlistId';
    final mem = _cache[cacheKey];
    if (mem != null) return mem;
    final maps = await _persisted(cacheKey, const Duration(hours: 24), () async {
      final body = await _request('/playlistItems', {
        'part': 'snippet',
        'playlistId': playlistId,
        'maxResults': '50',
      });
      final items = body is Map ? body['items'] : null;
      final out = <Map<String, dynamic>>[];
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          final snippet = item['snippet'];
          if (snippet is! Map) continue;
          final resource = snippet['resourceId'];
          final id = resource is Map ? resource['videoId']?.toString() : null;
          final title = snippet['title']?.toString() ?? '';
          if (id == null || title == 'Private video' || title == 'Deleted video') {
            continue;
          }
          out.add(Track(
            id: id,
            title: _unescape(title),
            artist: _cleanChannel(
                (snippet['videoOwnerChannelTitle'] ?? snippet['channelTitle'])
                    ?.toString()),
            artwork: _thumb(snippet['thumbnails']),
            channelId: snippet['videoOwnerChannelId']?.toString(),
          ).toJson());
        }
      }
      return out;
    });
    final tracks = maps.map(Track.fromJson).toList();
    _cache[cacheKey] = tracks;
    return tracks;
  }

  /// Fotos dos canais/artistas (custa 1 unidade para até 50 canais).
  static Future<Map<String, String>> channelAvatars(List<String> ids) async {
    final result = <String, String>{};
    final missing = <String>[];
    for (final id in ids) {
      final cached = _avatarCache[id];
      if (cached != null) {
        result[id] = cached;
      } else {
        missing.add(id);
      }
    }
    if (missing.isNotEmpty) {
      final body = await _request('/channels', {
        'part': 'snippet',
        'id': missing.join(','),
        'maxResults': '50',
      });
      final items = body is Map ? body['items'] : null;
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          final id = item['id']?.toString();
          final snippet = item['snippet'];
          if (id == null || snippet is! Map) continue;
          final thumbs = snippet['thumbnails'];
          final url = _thumb(thumbs is Map ? {'high': thumbs['medium'] ?? thumbs['default']} : null);
          if (url != null) {
            _avatarCache[id] = url;
            result[id] = url;
          }
        }
      }
    }
    return result;
  }

  /// Limpa os caches (memória e disco). Usado no "puxar para atualizar".
  static Future<void> clearCache() async {
    _cache.clear();
    _playlistCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith('cache_')).toList()) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
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

  /// Limpa títulos do YouTube ("Artista - Música (Clipe Oficial)").
  static ({String artist, String title}) guess(Track track) {
    var title = track.title.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
    title = title.replaceAll(
      RegExp(
          r'\b(official|oficial|clipe|video|vídeo|videoclipe|áudio|audio|lyrics|letra|ao vivo|hd|4k)\b',
          caseSensitive: false),
      ' ',
    );
    var artist = track.artist;
    final parts = title.split(RegExp(r'\s[-–—|]\s'));
    if (parts.length >= 2) {
      artist = parts.first.trim();
      title = parts.sublist(1).join(' ').trim();
    }
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return (artist: artist, title: title);
  }

  static Future<List<Map>> _search(Map<String, String> query) async {
    final uri = Uri.https('lrclib.net', '/api/search', query);
    final res = await http
        .get(uri, headers: {'User-Agent': 'WaveMusic/0.6.0'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return body is List ? body.whereType<Map>().toList() : [];
  }

  static Future<Lyrics> fetch(Track track) async {
    final g = guess(track);
    var results = await _search({
      'track_name': g.title,
      'artist_name': g.artist,
    });
    if (results.isEmpty) {
      results = await _search({'q': '${g.artist} ${g.title}'});
    }
    String? plain;
    for (final item in results) {
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
// Cor dominante da capa (fundo do player)
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
  final List<Playlist> playlists = [];
  final List<Track> history = [];
  final List<String> searches = [];
  String youtubeKey = '';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      youtubeKey = prefs.getString('yt_key') ?? '';
      _readTracks(prefs.getStringList('yt_favorites'), favorites);
      _readTracks(prefs.getStringList('yt_history'), history);
      searches.addAll(prefs.getStringList('yt_searches') ?? const <String>[]);
      final rawPlaylists = prefs.getStringList('yt_playlists');
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
      await prefs.setString('yt_key', youtubeKey);
      await prefs.setStringList('yt_favorites', enc(favorites));
      await prefs.setStringList('yt_history', enc(history));
      await prefs.setStringList('yt_searches', searches);
      await prefs.setStringList('yt_playlists',
          playlists.map((p) => jsonEncode(p.toJson())).toList());
    } catch (_) {}
  }

  // Chave do YouTube ----------------------------------------------------------

  bool get hasKey => youtubeKey.isNotEmpty;

  Future<void> setYoutubeKey(String key) async {
    youtubeKey = key.trim();
    YoutubeApi.clearCache();
    notifyListeners();
    await _save();
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

  /// Artistas mais ouvidos (histórico + favoritas).
  List<ArtistStat> topArtists(int n) {
    final counts = <String, int>{};
    final channels = <String, String>{};
    for (final t in [...history, ...favorites]) {
      counts[t.artist] = (counts[t.artist] ?? 0) + 1;
      final c = t.channelId;
      if (c != null && c.isNotEmpty) channels[t.artist] = c;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(n)
        .map((e) => ArtistStat(e.key, channels[e.key], e.value))
        .toList();
  }

  // Buscas recentes -----------------------------------------------------------

  Future<void> addSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    searches.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    searches.insert(0, q);
    if (searches.length > 8) searches.removeRange(8, searches.length);
    notifyListeners();
    await _save();
  }

  Future<void> clearSearches() async {
    searches.clear();
    notifyListeners();
    await _save();
  }
}

// ---------------------------------------------------------------------------
// Controle do player (player oficial do YouTube embutido)
// ---------------------------------------------------------------------------

enum WaveRepeat { off, all, one }

class PlayerController extends ChangeNotifier {
  final Random _rng = Random();
  final Map<String, Lyrics> _lyricsCache = {};
  StreamSubscription<YoutubePlayerValue>? _sub;
  Timer? _sleepTimer;
  PlayerState _state = PlayerState.unknown;
  bool _endHandled = false;
  String? _errorHandledFor;
  int _consecutiveErrors = 0;

  /// Player do YouTube; só é criado quando a primeira música é escolhida.
  YoutubePlayerController? yt;

  List<Track> queue = [];
  int index = -1;
  bool shuffle = false;
  WaveRepeat repeat = WaveRepeat.off;
  String? error;
  Color accent = defaultAccent;
  DateTime? sleepAt;

  /// Chamado quando uma faixa começa (usado para o histórico).
  void Function(Track track)? onTrackStart;

  Track? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  bool get playing =>
      _state == PlayerState.playing || _state == PlayerState.buffering;

  Future<void> playQueue(List<Track> tracks, int start) async {
    if (tracks.isEmpty || start < 0 || start >= tracks.length) return;
    queue = List<Track>.of(tracks);
    _consecutiveErrors = 0;
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

  void _onValue(YoutubePlayerValue value) {
    final newState = value.playerState;
    final changed = newState != _state;
    _state = newState;

    if (newState == PlayerState.playing) {
      _endHandled = false;
      _consecutiveErrors = 0;
    }
    if (newState == PlayerState.ended && !_endHandled) {
      _endHandled = true;
      _onEnded();
    }
    if (value.hasError && current != null && _errorHandledFor != current!.id) {
      _errorHandledFor = current!.id;
      _onPlaybackError();
    }
    if (changed) notifyListeners();
  }

  Future<void> _onEnded() async {
    if (repeat == WaveRepeat.one) {
      await yt?.seekTo(seconds: 0, allowSeekAhead: true);
      await yt?.playVideo();
      return;
    }
    await next(auto: true);
  }

  Future<void> _onPlaybackError() async {
    _consecutiveErrors++;
    if (queue.length > 1 && _consecutiveErrors < queue.length) {
      error = 'Esta música não pode tocar fora do YouTube. Pulando...';
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await next(auto: true);
    } else {
      error = 'Esta música não pode tocar fora do YouTube.';
      notifyListeners();
    }
  }

  Future<void> _load(int i) async {
    if (i < 0 || i >= queue.length) return;
    index = i;
    error = null;
    _endHandled = false;
    final t = queue[i];
    try {
      final existing = yt;
      if (existing == null) {
        final controller = YoutubePlayerController.fromVideoId(
          videoId: t.id,
          autoPlay: true,
          params: const YoutubePlayerParams(
            showControls: true,
            showFullscreenButton: true,
          ),
        );
        yt = controller;
        _sub = controller.listen(_onValue);
      } else {
        await existing.loadVideoById(videoId: t.id);
      }
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
      notifyListeners();
    }
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
          await yt?.pauseVideo();
          notifyListeners();
          return;
        }
      }
    }
    await _load(n);
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    try {
      final seconds = await yt?.currentTime ?? 0;
      if (seconds > 3) {
        await yt?.seekTo(seconds: 0, allowSeekAhead: true);
        return;
      }
    } catch (_) {}
    await _load((index - 1 + queue.length) % queue.length);
  }

  Future<void> togglePlay() async {
    final player = yt;
    if (player == null || current == null) return;
    if (playing) {
      await player.pauseVideo();
    } else {
      await player.playVideo();
    }
  }

  Future<void> seek(Duration position) async {
    await yt?.seekTo(
        seconds: position.inMilliseconds / 1000.0, allowSeekAhead: true);
  }

  Future<void> jumpTo(int i) => _load(i);

  void removeFromQueue(int i) {
    if (i < 0 || i >= queue.length || i == index) return;
    queue.removeAt(i);
    if (i < index) index--;
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = WaveRepeat.values[(repeat.index + 1) % WaveRepeat.values.length];
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
        await yt?.pauseVideo();
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
    _sub?.cancel();
    yt?.close();
    super.dispose();
  }
}
