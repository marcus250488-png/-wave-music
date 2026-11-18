import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'core.dart';
import 'pages.dart';
import 'player_pages.dart';
import 'widgets.dart';

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
  try {
    await libStore.load().timeout(const Duration(seconds: 3));
  } catch (_) {}
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

class Shell extends StatefulWidget {
  const Shell({super.key, this.startupError});

  final Object? startupError;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    playerCtrl.onTrackStart = libStore.addHistory;
    playerCtrl.addListener(_onController);
  }

  void _onController() {
    final message = playerCtrl.error;
    if (message == null || !mounted) return;
    playerCtrl.error = null;
    showSnack(context, message);
  }

  @override
  void dispose() {
    playerCtrl.removeListener(_onController);
    super.dispose();
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const NowPlayingPage(),
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
                  children: const [
                    HomePage(),
                    SearchPage(),
                    LibraryPage(),
                  ],
                ),
              ),
              ListenableBuilder(
                listenable: playerCtrl,
                builder: (context, _) => playerCtrl.current == null
                    ? const SizedBox.shrink()
                    : MiniPlayer(onTap: _openNowPlaying),
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
