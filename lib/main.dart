import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

const bg = Color(0xFF080B12);
const panel = Color(0xFF141C2B);
const blue = Color(0xFF287BFF);
const muted = Color(0xFF91A0B7);

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
        home: PlayerHome(startupError: startupError),
      );
}

class LocalTrack {
  const LocalTrack({required this.path, required this.name});
  final String path;
  final String name;
}

class PlayerHome extends StatefulWidget {
  const PlayerHome({super.key, this.startupError});

  final Object? startupError;

  @override
  State<PlayerHome> createState() => _PlayerHomeState();
}

class _PlayerHomeState extends State<PlayerHome> {
  final AudioPlayer _player = AudioPlayer();
  final List<LocalTrack> _tracks = [];
  int _tab = 0;
  int _current = -1;
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _addMusic() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return;

    final additions = result.files
        .where((file) => file.path != null)
        .map((file) => LocalTrack(path: file.path!, name: file.name))
        .toList();

    if (!mounted) return;
    setState(() => _tracks.addAll(additions));
    if (_current == -1 && _tracks.isNotEmpty) {
      await _playTrack(0);
    }
  }

  Future<void> _playTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    setState(() {
      _current = index;
      _loading = true;
    });
    try {
      final track = _tracks[index];
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.file(track.path),
          tag: MediaItem(
            id: track.path,
            title: track.name,
            artist: 'Arquivo local',
            album: 'Minha biblioteca',
          ),
        ),
      );
      unawaited(_player.play());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível tocar este arquivo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _next() async {
    if (_tracks.isEmpty) return;
    await _playTrack((_current + 1) % _tracks.length);
  }

  Future<void> _previous() async {
    if (_tracks.isEmpty) return;
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      await _playTrack((_current - 1 + _tracks.length) % _tracks.length);
    }
  }

  String _time(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString();
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _page()),
              if (_current >= 0) _miniPlayer(),
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
                    label: 'Biblioteca',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _page() {
    if (_tab == 1) return _searchPage();
    if (_tab == 2) return _libraryPage();
    return _homePage();
  }

  Widget _homePage() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WAVE MUSIC',
                        style: TextStyle(
                            color: blue,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                    SizedBox(height: 7),
                    Text('Sua música.',
                        style: TextStyle(
                            fontSize: 30, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              IconButton(
                onPressed: _addMusic,
                icon: const Icon(Icons.add_circle_outline, color: blue, size: 30),
                tooltip: 'Adicionar músicas',
              ),
            ],
          ),
          if (widget.startupError != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF3A1C1C),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Áudio em segundo plano não iniciou: ${widget.startupError}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          const SizedBox(height: 25),
          Container(
            padding: const EdgeInsets.all(22),
            height: 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              gradient: const LinearGradient(
                colors: [Color(0xFF17458C), Color(0xFF111827), Color(0xFF392044)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('SEU SOM, DO SEU JEITO',
                    style: TextStyle(
                        color: Colors.white70,
                        letterSpacing: 2,
                        fontSize: 10)),
                const SizedBox(height: 7),
                const Text('Sua biblioteca\nem um só lugar',
                    style: TextStyle(
                        fontSize: 24,
                        height: 1.1,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _addMusic,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Adicionar músicas'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          _heading('Sua música', 'Arquivos do dispositivo'),
          const SizedBox(height: 8),
          if (_tracks.isEmpty)
            _emptyState()
          else
            ...List.generate(_tracks.length, _trackTile),
        ],
      );

  Widget _searchPage() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Buscar',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar na sua biblioteca',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          ...List.generate(_tracks.length, _trackTile),
        ],
      );

  Widget _libraryPage() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Sua biblioteca',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _libraryRow(Icons.queue_music, 'Todas as músicas',
              '${_tracks.length} arquivos adicionados'),
          _libraryRow(Icons.folder_open, 'Arquivos locais',
              'Músicas selecionadas neste dispositivo'),
          const SizedBox(height: 15),
          ...List.generate(_tracks.length, _trackTile),
          if (_tracks.isEmpty) _emptyState(),
        ],
      );

  Widget _libraryRow(IconData icon, String title, String subtitle) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _art(48),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: muted)),
      );

  Widget _heading(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      );

  Widget _emptyState() => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          children: [
            Icon(Icons.library_music_outlined, size: 42, color: blue),
            SizedBox(height: 10),
            Text('Sua biblioteca está vazia',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Text('Adicione arquivos de áudio do seu celular para começar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted)),
          ],
        ),
      );

  Widget _trackTile(int index) {
    final track = _tracks[index];
    return ListTile(
      onTap: () => _playTrack(index),
      contentPadding: EdgeInsets.zero,
      leading: _art(52),
      title: Text(track.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: const Text('Arquivo local', style: TextStyle(color: muted)),
      trailing: Icon(
        _current == index && _player.playing
            ? Icons.equalizer
            : Icons.play_circle_outline,
        color: blue,
      ),
    );
  }

  Widget _art(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF235DA9), Color(0xFF25213D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.music_note, color: Colors.white70),
      );

  Widget _miniPlayer() {
    final track = _tracks[_current];
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF172338),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFF29436A)),
          ),
          child: Row(
            children: [
              _art(43),
              const SizedBox(width: 10),
              Expanded(
                child: Text(track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: _loading
                    ? null
                    : () => playing ? _player.pause() : _player.play(),
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                onPressed: _next,
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
        );
      },
    );
  }
}
