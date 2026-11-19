import 'package:flutter/material.dart';

import 'core.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Configurações (chave do YouTube)
// ---------------------------------------------------------------------------

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _controller =
      TextEditingController(text: libStore.youtubeKey);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await libStore.setYoutubeKey(_controller.text);
    if (!mounted) return;
    showSnack(context, libStore.hasKey ? 'Chave salva' : 'Chave removida');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Chave do YouTube'), backgroundColor: bg),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'O Wave Music busca as músicas pela API oficial do YouTube. '
              'Para isso você precisa de uma chave gratuita da sua conta Google '
              '(leva uns 5 minutos):',
              style: TextStyle(color: muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            const _Step('1', 'Abra console.cloud.google.com e entre com sua conta Google.'),
            const _Step('2', 'Crie um projeto (pode ter qualquer nome).'),
            const _Step('3',
                'Em "APIs e serviços" > "Biblioteca", procure "YouTube Data API v3" e toque em Ativar.'),
            const _Step('4',
                'Em "Credenciais" > "Criar credenciais" > "Chave de API".'),
            const _Step('5', 'Copie a chave e cole no campo abaixo.'),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'Cole a chave aqui (começa com AIza...)',
                filled: true,
                fillColor: panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: _save, child: const Text('Salvar')),
            const SizedBox(height: 14),
            const Text(
              'A cota gratuita do YouTube dá mais ou menos 100 buscas por dia. '
              'A tela inicial (músicas em alta) gasta quase nada. Não compartilhe '
              'sua chave com ninguém.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: blue,
              child: Text(number,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
          ],
        ),
      );
}

class KeyCard extends StatelessWidget {
  const KeyCard({super.key});

  @override
  Widget build(BuildContext context) => StateMessage(
        icon: Icons.vpn_key_outlined,
        title: 'Falta a chave do YouTube',
        subtitle: 'Crie uma chave gratuita e cole aqui para liberar a busca '
            'de músicas de qualquer cantor.',
        onRetry: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
        ),
        retryLabel: 'Configurar agora',
      );
}

// ---------------------------------------------------------------------------
// Início
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _chips = ['Tudo', 'Favoritas', 'Recentes'];

  int _chip = 0;
  List<Track> _trending = [];
  List<Track> _forYou = [];
  String? _forYouArtist;
  bool _loading = false;
  String? _error;
  String _lastKey = libStore.youtubeKey;

  @override
  void initState() {
    super.initState();
    libStore.addListener(_onLibrary);
    _load();
  }

  @override
  void dispose() {
    libStore.removeListener(_onLibrary);
    super.dispose();
  }

  void _onLibrary() {
    if (libStore.youtubeKey != _lastKey) {
      _lastKey = libStore.youtubeKey;
      _load();
    }
  }

  Future<void> _load() async {
    if (!libStore.hasKey) {
      setState(() {
        _trending = [];
        _forYou = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trending = await YoutubeApi.trendingBrazil();
      if (!mounted) return;
      setState(() => _trending = trending);
      final artist = libStore.topArtist;
      if (artist != null) {
        try {
          final forYou = await YoutubeApi.search(artist);
          if (!mounted) return;
          setState(() {
            _forYou = forYou;
            _forYouArtist = artist;
          });
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  List<Widget> _quickTiles() {
    final tiles = <Widget>[
      QuickTile(
        title: 'Favoritas',
        covers: libStore.favorites.take(4).map((t) => t.artwork).toList(),
        icon: Icons.favorite,
        onTap: () => _push(TrackListPage(
          title: 'Favoritas',
          getTracks: () => libStore.favorites,
        )),
      ),
    ];
    for (final p in libStore.playlists.take(3)) {
      tiles.add(QuickTile(
        title: p.name,
        covers: p.covers,
        icon: Icons.queue_music,
        onTap: () => _push(PlaylistPage(playlistId: p.id)),
      ));
    }
    final recents = libStore.recents;
    for (var i = 0; i < recents.length && tiles.length < 8; i++) {
      final t = recents[i];
      tiles.add(QuickTile(
        title: t.title,
        covers: [t.artwork],
        onTap: () => playerCtrl.playQueue(recents, i),
      ));
    }
    return tiles;
  }

  List<Track> _chipTracks() =>
      _chip == 1 ? libStore.favorites : libStore.recents;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: libStore,
        builder: (context, _) => RefreshIndicator(
          onRefresh: () async {
            YoutubeApi.clearCache();
            await _load();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_greeting,
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Chave do YouTube',
                    onPressed: () => _push(const SettingsPage()),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _chips.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ChoiceChip(
                    label: Text(_chips[i]),
                    selected: _chip == i,
                    onSelected: (_) => setState(() => _chip = i),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_chip != 0) ..._chipContent() else ..._allContent(),
            ],
          ),
        ),
      );

  List<Widget> _chipContent() {
    final list = _chipTracks();
    if (list.isEmpty) {
      return [
        StateMessage(
          icon: Icons.library_music_outlined,
          title: 'Nada por aqui ainda',
          subtitle: _chip == 1
              ? 'Toque no coração de uma música para guardar aqui.'
              : 'As músicas que você ouvir aparecem aqui.',
        ),
      ];
    }
    return List.generate(
      list.length,
      (i) => TrackTile(
        track: list[i],
        onTap: () => playerCtrl.playQueue(list, i),
      ),
    );
  }

  List<Widget> _allContent() {
    final recents = libStore.recents;
    return [
      GridView(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 56,
        ),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: _quickTiles(),
      ),
      if (!libStore.hasKey) const KeyCard(),
      if (recents.isNotEmpty) ...[
        const SectionTitle('Continue ouvindo'),
        TrackCarousel(tracks: recents),
      ],
      if (libStore.hasKey) ...[
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 50),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          StateMessage(
            icon: Icons.wifi_off,
            title: 'Não consegui carregar as músicas',
            subtitle: _error,
            onRetry: _load,
          )
        else ...[
          if (_trending.isNotEmpty) ...[
            const SectionTitle('Em alta no Brasil',
                subtitle: 'Músicas do YouTube'),
            TrackCarousel(tracks: _trending),
          ],
          if (_forYou.isNotEmpty && _forYouArtist != null) ...[
            SectionTitle('Mais de $_forYouArtist',
                subtitle: 'Com base no que você mais ouve'),
            TrackCarousel(tracks: _forYou),
          ],
        ],
      ],
    ];
  }
}

// ---------------------------------------------------------------------------
// Buscar (com explorar por gênero)
// ---------------------------------------------------------------------------

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _palette = <Color>[
    Color(0xFF1E6BD6),
    Color(0xFF8E3AC9),
    Color(0xFFC23B5A),
    Color(0xFF1C8F6B),
    Color(0xFFD9822B),
    Color(0xFF4B5AD6),
  ];

  final TextEditingController _text = TextEditingController();
  List<Track> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _genreTitle;
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<List<Track>> Function() task) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await task();
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

  Future<void> _search(String raw) async {
    final query = raw.trim();
    _genreTitle = null;
    if (query.isEmpty) {
      _requestId++;
      setState(() {
        _results = [];
        _searched = false;
        _error = null;
        _loading = false;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    await _run(() => YoutubeApi.search(query));
  }

  Future<void> _openGenre(String name, String query) async {
    FocusScope.of(context).unfocus();
    _text.clear();
    setState(() => _genreTitle = name);
    await _run(() => YoutubeApi.search(query));
  }

  void _clearGenre() {
    _requestId++;
    setState(() {
      _genreTitle = null;
      _results = [];
      _searched = false;
      _loading = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final browsing = !_searched && !_loading && _error == null;
    final genres = kGenres.entries.toList();
    return ListenableBuilder(
      listenable: libStore,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text('Buscar',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            onSubmitted: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Cantor, banda ou música',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (!libStore.hasKey)
            const KeyCard()
          else ...[
            if (_genreTitle != null)
              Row(
                children: [
                  IconButton(
                    onPressed: _clearGenre,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(_genreTitle!,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
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
                onRetry: () => _genreTitle != null
                    ? _openGenre(_genreTitle!, kGenres[_genreTitle!] ?? _genreTitle!)
                    : _search(_text.text),
              )
            else if (_searched && _results.isEmpty)
              const StateMessage(
                icon: Icons.search_off,
                title: 'Nenhum resultado',
                subtitle: 'Tente outro nome de música ou artista.',
              )
            else if (browsing) ...[
              const SectionTitle('Explorar tudo'),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: genres.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.1,
                ),
                itemBuilder: (context, i) => Material(
                  color: _palette[i % _palette.length],
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openGenre(genres[i].key, genres[i].value),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(genres[i].key,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  ),
                ),
              ),
            ] else
              ...List.generate(
                _results.length,
                (i) => TrackTile(
                  track: _results[i],
                  onTap: () => playerCtrl.playQueue(_results, i),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Biblioteca
// ---------------------------------------------------------------------------

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _section = 1;

  Future<void> _newPlaylist() async {
    final name = await promptPlaylistName(context);
    if (name == null) return;
    await libStore.createPlaylist(name);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: libStore,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Sua biblioteca',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                ),
                if (_section == 1)
                  IconButton(
                    onPressed: _newPlaylist,
                    tooltip: 'Nova playlist',
                    icon: const Icon(Icons.add_circle_outline,
                        color: blue, size: 30),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Favoritas')),
                ButtonSegment(value: 1, label: Text('Playlists')),
              ],
              selected: {_section},
              onSelectionChanged: (s) => setState(() => _section = s.first),
            ),
            const SizedBox(height: 10),
            ..._content(),
          ],
        ),
      );

  List<Widget> _content() {
    if (_section == 1) return _playlistsContent();
    final list = libStore.favorites;
    if (list.isEmpty) {
      return [
        const StateMessage(
          icon: Icons.favorite_border,
          title: 'Nenhuma favorita ainda',
          subtitle: 'Toque no coração de uma música para guardar aqui.',
        ),
      ];
    }
    return List.generate(
      list.length,
      (i) => TrackTile(
        track: list[i],
        onTap: () => playerCtrl.playQueue(list, i),
      ),
    );
  }

  List<Widget> _playlistsContent() {
    final playlists = libStore.playlists;
    if (playlists.isEmpty) {
      return [
        StateMessage(
          icon: Icons.queue_music,
          title: 'Nenhuma playlist ainda',
          subtitle: 'Crie uma e adicione músicas pelo menu ⋮ de cada faixa.',
          onRetry: _newPlaylist,
          retryLabel: 'Criar playlist',
        ),
      ];
    }
    return [
      for (final p in playlists)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Mosaic(covers: p.covers, size: 56, radius: 8),
          title: Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${p.tracks.length} músicas',
              style: const TextStyle(color: muted)),
          trailing: const Icon(Icons.chevron_right, color: muted),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PlaylistPage(playlistId: p.id),
          )),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Listas (favoritas) e playlist
// ---------------------------------------------------------------------------

class TrackListPage extends StatelessWidget {
  const TrackListPage({super.key, required this.title, required this.getTracks});

  final String title;
  final List<Track> Function() getTracks;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), backgroundColor: bg),
        body: ListenableBuilder(
          listenable: libStore,
          builder: (context, _) {
            final list = getTracks();
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: StateMessage(
                  icon: Icons.favorite_border,
                  title: 'Nada por aqui ainda',
                  subtitle: 'Toque no coração de uma música para guardar aqui.',
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => playerCtrl.playQueue(list, 0),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Tocar'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => playerCtrl.playShuffled(list),
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Aleatório'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(
                  list.length,
                  (i) => TrackTile(
                    track: list[i],
                    onTap: () => playerCtrl.playQueue(list, i),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  Future<void> _confirmDelete(BuildContext context, Playlist p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir playlist?'),
        content: Text('"${p.name}" será apagada. As músicas continuam '
            'disponíveis no app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await libStore.deletePlaylist(p.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: libStore,
        builder: (context, _) {
          final p = libStore.playlistById(playlistId);
          if (p == null) {
            return Scaffold(
              appBar: AppBar(backgroundColor: bg),
              body: const Center(child: Text('Playlist não encontrada')),
            );
          }
          return Scaffold(
            appBar: AppBar(
              backgroundColor: bg,
              title: Text(p.name),
              actions: [
                IconButton(
                  tooltip: 'Excluir playlist',
                  onPressed: () => _confirmDelete(context, p),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Center(child: Mosaic(covers: p.covers, size: 170, radius: 14)),
                const SizedBox(height: 12),
                Center(
                  child: Text('${p.tracks.length} músicas',
                      style: const TextStyle(color: muted)),
                ),
                const SizedBox(height: 12),
                if (p.tracks.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => playerCtrl.playQueue(p.tracks, 0),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Tocar'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => playerCtrl.playShuffled(p.tracks),
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Aleatório'),
                      ),
                    ],
                  )
                else
                  const StateMessage(
                    icon: Icons.queue_music,
                    title: 'Playlist vazia',
                    subtitle: 'Use o menu ⋮ de uma música para adicionar aqui.',
                  ),
                const SizedBox(height: 8),
                ...List.generate(
                  p.tracks.length,
                  (i) => TrackTile(
                    track: p.tracks[i],
                    onTap: () => playerCtrl.playQueue(p.tracks, i),
                    extra: [
                      MenuAction(
                        'Remover da playlist',
                        Icons.remove_circle_outline,
                        () => libStore.removeFromPlaylist(p, p.tracks[i].id),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}
