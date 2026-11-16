import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Configuração
// ---------------------------------------------------------------------------

const bg = Color(0xFF080B12);
const panel = Color(0xFF141C2B);
const blue = Color(0xFF287BFF);
const muted = Color(0xFF91A0B7);

const kAudiusBase = 'https://api.audius.co/v1';
const kAppName = 'WaveMusic';

/// Opcional: chave gratuita da Audius (audius.co/settings -> "Manage Your
/// Apps"). Sem chave o app funciona, só com limite de uso menor.
const kAudiusApiKey = '';

const kGenres = <String>[
  'Todos',
  'Electronic',
  'Hip-Hop/Rap',
  'Pop',
  'Rock',
  'Lo-Fi',
  'R&B/Soul',
  'Jazz',
  'Latin',
];

// ---------------------------------------------------------------------------
// Início do app
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.wavemusic.audio',
      androidNotificationChannelName: 'Wave Music',
      androidNotificationOngoing: true,
    ).timeout(const Duration(seconds: 6));
    final session = await AudioSession.instance;
    await session
        .configure(const AudioSessionConfiguration.music())
        .timeout(const Duration(seconds: 4));
  } catch (error) {
    // Nunca deixa o app preso na tela preta: abre a interface mesmo se o
    // áudio em segundo plano falhar, e mostra o motivo na tela.
    startupError = error;
  }
  runApp(WaveMusicApp(startupError: startupError));
}

class WaveMusicApp extends StatelessWidget {
  const WaveMusicApp({super.key, this.startupError});

  final Object? startupError;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Wave Music',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: blue,
            brightness: Brightness.dark,
            surface: panel,
          ),
          useMaterial3: true,
        ),
        home: Shell(startupError: startupError),
      );
}

// ---------------------------------------------------------------------------
// Modelo
// ---------------------------------------------------------------------------

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.uri,
    this.artwork,
    this.durationSec,
    this.isLocal = false,
  });

  final String id;
  final String title;
  final String artist;
  final String uri;
  final String? artwork;
  final int? durationSec;
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
        isLocal: j['isLocal'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'uri': uri,
        'artwork': artwork,
        'durationSec': durationSec,
        'isLocal': isLocal,
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

  static Future<List<Track>> trending({String? genre}) =>
      _get('/tracks/trending', {
        'time': 'week',
        'limit': '30',
        if (genre != null) 'genre': genre,
      });

  static Future<List<Track>> search(String query) =>
      _get('/tracks/search', {'query': query, 'limit': '30'});
}

// ---------------------------------------------------------------------------
// Biblioteca salva no aparelho (favoritas + arquivos locais)
// ---------------------------------------------------------------------------

class Library extends ChangeNotifier {
  final List<Track> favorites = [];
  final List<Track> locals = [];

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _read(prefs.getStringList('favorites'), favorites);
      _read(prefs.getStringList('locals'), locals);
      notifyListeners();
    } catch (_) {
      // Sem permissão de leitura: segue com a biblioteca vazia.
    }
  }

  void _read(List<String>? raw, List<Track> target) {
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
      await prefs.setStringList(
          'favorites', favorites.map((t) => jsonEncode(t.toJson())).toList());
      await prefs.setStringList(
          'locals', locals.map((t) => jsonEncode(t.toJson())).toList());
    } catch (_) {}
  }

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
}

// ---------------------------------------------------------------------------
// Controle do player
// ---------------------------------------------------------------------------

enum RepeatMode { off, all, one }

class PlayerController extends ChangeNotifier {
  PlayerController() {
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
    _player.playingStream.listen((_) => notifyListeners());
  }

  final AudioPlayer _player = AudioPlayer();
  final Random _rng = Random();

  AudioPlayer get player => _player;

  List<Track> queue = [];
  int index = -1;
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;
  bool loading = false;
  String? error;

  Track? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  bool get playing => _player.playing;

  Future<void> playQueue(List<Track> tracks, int start) async {
    if (tracks.isEmpty || start < 0 || start >= tracks.length) return;
    queue = List<Track>.of(tracks);
    await _load(start);
  }

  Future<void> _load(int i) async {
    if (i < 0 || i >= queue.length) return;
    index = i;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final t = queue[i];
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
    } catch (e) {
      error = 'Não foi possível tocar esta faixa: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _onCompleted() async {
    if (repeat == RepeatMode.one) {
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
        if (repeat == RepeatMode.all || !auto) {
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
    repeat = RepeatMode.values[(repeat.index + 1) % RepeatMode.values.length];
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Estrutura principal
// ---------------------------------------------------------------------------

class Shell extends StatefulWidget {
  const Shell({super.key, this.startupError});

  final Object? startupError;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final PlayerController ctrl = PlayerController();
  final Library lib = Library();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    lib.load();
    ctrl.addListener(_onController);
  }

  void _onController() {
    final message = ctrl.error;
    if (message == null || !mounted) return;
    ctrl.error = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    ctrl.removeListener(_onController);
    ctrl.dispose();
    lib.dispose();
    super.dispose();
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => NowPlayingPage(ctrl: ctrl, lib: lib),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (widget.startupError != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A1C1C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Áudio em segundo plano não iniciou: ${widget.startupError}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    HomePage(ctrl: ctrl, lib: lib),
                    SearchPage(ctrl: ctrl, lib: lib),
                    LibraryPage(ctrl: ctrl, lib: lib),
                  ],
                ),
              ),
              ListenableBuilder(
                listenable: ctrl,
                builder: (context, _) => ctrl.current == null
                    ? const SizedBox.shrink()
                    : MiniPlayer(ctrl: ctrl, onTap: _openNowPlaying),
              ),
              NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (value) => setState(() => _tab = value),
                backgroundColor: bg,
                indicatorColor: blue.withValues(alpha: .2),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Início',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search),
                    label: 'Buscar',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music),
                    label: 'Biblioteca',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Widgets comuns
// ---------------------------------------------------------------------------

class Art extends StatelessWidget {
  const Art({super.key, this.url, required this.size, this.radius = 14});

  final String? url;
  final double size;
  final double radius;

  Widget _placeholder() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            colors: [Color(0xFF235DA9), Color(0xFF25213D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(Icons.music_note, color: Colors.white70, size: size * .4),
      );

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return _placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(),
      ),
    );
  }
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.ctrl,
    required this.lib,
    required this.onTap,
    this.onLongPress,
  });

  final Track track;
  final PlayerController ctrl;
  final Library lib;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([ctrl, lib]),
        builder: (context, _) {
          final isCurrent = ctrl.current?.id == track.id;
          final fav = lib.isFavorite(track.id);
          return ListTile(
            onTap: onTap,
            onLongPress: onLongPress,
            contentPadding: EdgeInsets.zero,
            leading: Art(url: track.artwork, size: 52),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isCurrent ? blue : null,
              ),
            ),
            subtitle: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted),
            ),
            trailing: IconButton(
              onPressed: () => lib.toggleFavorite(track),
              icon: Icon(
                fav ? Icons.favorite : Icons.favorite_border,
                color: fav ? Colors.pinkAccent : muted,
              ),
            ),
          );
        },
      );
}

class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, size: 42, color: blue),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted)),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                  onPressed: onRetry, child: const Text('Tentar de novo')),
            ],
          ],
        ),
      );
}

String fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:${m.padLeft(2, '0')}:$s' : '$m:$s';
}

// ---------------------------------------------------------------------------
// Início (em alta na Audius)
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.ctrl, required this.lib});

  final PlayerController ctrl;
  final Library lib;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _genre = 'Todos';
  List<Track> _tracks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await AudiusApi.trending(genre: _genre == 'Todos' ? null : _genre);
      if (!mounted) return;
      setState(() => _tracks = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          children: [
            const Text('WAVE MUSIC',
                style: TextStyle(
                    color: blue,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
            const SizedBox(height: 7),
            const Text('Em alta agora',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const Text('Streaming pela Audius',
                style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 16),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kGenres.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ChoiceChip(
                  label: Text(kGenres[i]),
                  selected: _genre == kGenres[i],
                  onSelected: (_) {
                    setState(() => _genre = kGenres[i]);
                    _load();
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              StateMessage(
                icon: Icons.wifi_off,
                title: 'Não consegui carregar as músicas',
                subtitle: _error,
                onRetry: _load,
              )
            else if (_tracks.isEmpty)
              const StateMessage(
                icon: Icons.library_music_outlined,
                title: 'Nada encontrado nesse gênero',
              )
            else
              ...List.generate(
                _tracks.length,
                (i) => TrackTile(
                  track: _tracks[i],
                  ctrl: widget.ctrl,
                  lib: widget.lib,
                  onTap: () => widget.ctrl.playQueue(_tracks, i),
                ),
              ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Buscar
// ---------------------------------------------------------------------------

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.ctrl, required this.lib});

  final PlayerController ctrl;
  final Library lib;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _text = TextEditingController();
  Timer? _debounce;
  List<Track> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _error = null;
        _loading = false;
      });
      return;
    }
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AudiusApi.search(query);
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = result;
        _searched = true;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text('Buscar',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            onChanged: _onChanged,
            onSubmitted: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Músicas e artistas na Audius',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            StateMessage(
              icon: Icons.wifi_off,
              title: 'Erro na busca',
              subtitle: _error,
              onRetry: () => _search(_text.text),
            )
          else if (_searched && _results.isEmpty)
            const StateMessage(
              icon: Icons.search_off,
              title: 'Nenhum resultado',
              subtitle: 'Tente outro nome de música ou artista.',
            )
          else if (!_searched)
            const StateMessage(
              icon: Icons.travel_explore,
              title: 'Procure qualquer música',
              subtitle: 'Digite o nome da música ou do artista.',
            )
          else
            ...List.generate(
              _results.length,
              (i) => TrackTile(
                track: _results[i],
                ctrl: widget.ctrl,
                lib: widget.lib,
                onTap: () => widget.ctrl.playQueue(_results, i),
              ),
            ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Biblioteca (favoritas + arquivos do celular)
// ---------------------------------------------------------------------------

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.ctrl, required this.lib});

  final PlayerController ctrl;
  final Library lib;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _section = 0;

  Future<void> _addLocal() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result == null) return;
      final items = result.files
          .where((f) => f.path != null)
          .map((f) => Track.local(f.path!, f.name))
          .toList();
      await widget.lib.addLocals(items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não consegui abrir os arquivos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.lib,
        builder: (context, _) {
          final list =
              _section == 0 ? widget.lib.favorites : widget.lib.locals;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Sua biblioteca',
                        style: TextStyle(
                            fontSize: 29, fontWeight: FontWeight.w800)),
                  ),
                  if (_section == 1)
                    IconButton(
                      onPressed: _addLocal,
                      tooltip: 'Adicionar músicas do celular',
                      icon: const Icon(Icons.add_circle_outline,
                          color: blue, size: 30),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.favorite),
                    label: Text('Favoritas'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.folder_open),
                    label: Text('Do celular'),
                  ),
                ],
                selected: {_section},
                onSelectionChanged: (s) => setState(() => _section = s.first),
              ),
              const SizedBox(height: 10),
              if (list.isEmpty)
                StateMessage(
                  icon: _section == 0
                      ? Icons.favorite_border
                      : Icons.folder_open,
                  title: _section == 0
                      ? 'Nenhuma favorita ainda'
                      : 'Nenhum arquivo adicionado',
                  subtitle: _section == 0
                      ? 'Toque no coração de uma música para guardar aqui.'
                      : 'Use o botão + para escolher músicas do celular.',
                )
              else
                ...List.generate(
                  list.length,
                  (i) => TrackTile(
                    track: list[i],
                    ctrl: widget.ctrl,
                    lib: widget.lib,
                    onTap: () => widget.ctrl.playQueue(list, i),
                    onLongPress: _section == 1
                        ? () => widget.lib.removeLocal(list[i].id)
                        : null,
                  ),
                ),
              if (_section == 1 && list.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Segure uma música para remover da lista.',
                      style: TextStyle(color: muted, fontSize: 11)),
                ),
            ],
          );
        },
      );
}

// ---------------------------------------------------------------------------
// Mini player
// ---------------------------------------------------------------------------

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.ctrl, required this.onTap});

  final PlayerController ctrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track = ctrl.current;
    if (track == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF172338),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFF29436A)),
        ),
        child: Row(
          children: [
            Art(url: track.artwork, size: 43, radius: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12)),
                ],
              ),
            ),
            if (ctrl.loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else
              IconButton(
                onPressed: ctrl.togglePlay,
                icon: Icon(ctrl.playing ? Icons.pause : Icons.play_arrow),
              ),
            IconButton(
              onPressed: () => ctrl.next(),
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tela do player completo
// ---------------------------------------------------------------------------

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key, required this.ctrl, required this.lib});

  final PlayerController ctrl;
  final Library lib;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([ctrl, lib]),
            builder: (context, _) {
              final track = ctrl.current;
              if (track == null) {
                return const Center(child: Text('Nada tocando'));
              }
              final fav = lib.isFavorite(track.id);
              final screen = MediaQuery.of(context).size;
              final side = min(min(screen.width - 56, 360.0), screen.height * .36);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                        ),
                        const Expanded(
                          child: Text('TOCANDO AGORA',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: muted,
                                  letterSpacing: 2,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const Spacer(),
                    Art(url: track.artwork, size: side, radius: 24),
                    const Spacer(),
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
                                  style: const TextStyle(color: muted)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => lib.toggleFavorite(track),
                          icon: Icon(
                            fav ? Icons.favorite : Icons.favorite_border,
                            color: fav ? Colors.pinkAccent : muted,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ProgressBar(ctrl: ctrl, fallbackSeconds: track.durationSec),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: ctrl.toggleShuffle,
                          icon: Icon(Icons.shuffle,
                              color: ctrl.shuffle ? blue : muted),
                        ),
                        IconButton(
                          onPressed: ctrl.previous,
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
                            ctrl.repeat == RepeatMode.one
                                ? Icons.repeat_one
                                : Icons.repeat,
                            color: ctrl.repeat == RepeatMode.off
                                ? muted
                                : blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      track.isLocal
                          ? 'Arquivo do seu celular'
                          : 'Streaming por Audius • crédito aos artistas',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class ProgressBar extends StatefulWidget {
  const ProgressBar({super.key, required this.ctrl, this.fallbackSeconds});

  final PlayerController ctrl;
  final int? fallbackSeconds;

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = widget.ctrl.player;
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final total = player.duration ??
            Duration(seconds: widget.fallbackSeconds ?? 0);
        final totalMs = total.inMilliseconds.toDouble();
        final posMs = min(position.inMilliseconds.toDouble(), totalMs);
        final value = _drag ?? posMs;
        return Column(
          children: [
            Slider(
              value: totalMs <= 0 ? 0 : value.clamp(0, totalMs).toDouble(),
              max: totalMs <= 0 ? 1 : totalMs,
              onChanged: totalMs <= 0
                  ? null
                  : (v) => setState(() => _drag = v),
              onChangeEnd: totalMs <= 0
                  ? null
                  : (v) async {
                      await widget.ctrl
                          .seek(Duration(milliseconds: v.round()));
                      if (mounted) setState(() => _drag = null);
                    },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(fmt(Duration(milliseconds: value.round())),
                      style: const TextStyle(color: muted, fontSize: 12)),
                  Text(fmt(total),
                      style: const TextStyle(color: muted, fontSize: 12)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
