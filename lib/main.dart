import 'package:flutter/material.dart';

import 'core.dart';
import 'lyrics_panel.dart';
import 'pages.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await libStore.load().timeout(const Duration(seconds: 3));
  } catch (_) {}
  runApp(const WaveMusicApp());
}

class WaveMusicApp extends StatelessWidget {
  const WaveMusicApp({super.key});

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
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  String? _panel;

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

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    IndexedStack(
                      index: _tab,
                      children: const [
                        HomePage(),
                        SearchPage(),
                        LibraryPage(),
                      ],
                    ),
                    if (_panel == 'lyrics')
                      Positioned.fill(
                        child: LyricsPanel(
                          onClose: () => setState(() => _panel = null),
                        ),
                      ),
                    if (_panel == 'queue')
                      Positioned.fill(
                        child: QueuePanel(
                          onClose: () => setState(() => _panel = null),
                        ),
                      ),
                  ],
                ),
              ),
              PlayerDock(
                panel: _panel,
                onPanel: (p) => setState(() => _panel = _panel == p ? null : p),
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
