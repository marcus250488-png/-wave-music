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
// Início (estilo streaming: mixes, rádios, artistas, playlists, lançamentos)
// ---------------------------------------------------------------------------

class _MixData {
  const _MixData(this.title, this.subtitle, this.cover, this.tracks);
  final String title;
  final String subtitle;
  final String? cover;
  final List<Track> tracks;
}

class _RadioData {
  const _RadioData(this.title, this.color, this.tracks);
  final String title;
  final Color color;
  final List<Track> tracks;
}

class _ArtistView {
  const _ArtistView(this.name, this.avatar);
  final String name;
  final String? avatar;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _chips = ['Tudo', 'Favoritas', 'Recentes'];
  static const _palette = <Color>[
    Color(0xFF8E3AC9),
    Color(0xFF1C8F6B),
    Color(0xFFC23B5A),
    Color(0xFFD9822B),
  ];

  int _chip = 0;
  List<Track> _trending = [];
  List<_MixData> _mixes = [];
  List<_RadioData> _radios = [];
  List<PlaylistInfo> _playlists = [];
  List<_ArtistView> _artists = [];
  List<Track> _latest = [];
  bool _loading = false;
  String? _error;
  int _loadId = 0;
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

  String _names(List<Track> tracks) {
    final names = <String>[];
    for (final t in tracks) {
      if (!names.contains(t.artist)) names.add(t.artist);
      if (names.length == 3) break;
    }
    return '${names.join(', ')} e mais';
  }

  Future<void> _step(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  Future<void> _load() async {
    final id = ++_loadId;
    if (!libStore.hasKey) {
      setState(() {
        _trending = [];
        _mixes = [];
        _radios = [];
        _playlists = [];
        _artists = [];
        _latest = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _mixes = [];
      _radios = [];
      _playlists = [];
      _artists = [];
      _latest = [];
    });
    try {
      final trending = await YoutubeApi.trendingBrazil();
      if (!mounted || id != _loadId) return;
      setState(() {
        _trending = trending;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _loadId) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
      return;
    }
    await _loadExtras(id);
  }

  Future<void> _loadExtras(int id) async {
    bool alive() => mounted && id == _loadId;
    final artists = libStore.topArtists(8);

    // Mixes
    await _step(() async {
      final seeds = <MapEntry<String, String>>[];
      for (final a in artists.take(2)) {
        seeds.add(MapEntry('Mix de ${a.name}', a.name));
      }
      if (seeds.isEmpty) {
        seeds.add(MapEntry('Mix Sertanejo', kGenres['Sertanejo']!));
        seeds.add(MapEntry('Mix Funk', kGenres['Funk']!));
      }
      for (final seed in seeds) {
        final tracks = await YoutubeApi.search(seed.value);
        if (!alive()) return;
        if (tracks.isEmpty) continue;
        setState(() => _mixes.add(
            _MixData(seed.key, _names(tracks), tracks.first.artwork, tracks)));
      }
    });
    if (!alive()) return;

    // Rádios (gêneros que mudam a cada dia)
    await _step(() async {
      final keys = kGenres.keys.toList();
      final day = DateTime.now().difference(DateTime(2026)).inDays;
      final picks = <String>{keys[day % keys.length], keys[(day + 5) % keys.length]};
      var i = 0;
      for (final g in picks) {
        final tracks = await YoutubeApi.search(kGenres[g]!);
        if (!alive()) return;
        if (tracks.isEmpty) continue;
        final color = _palette[i % _palette.length];
        i++;
        setState(() => _radios.add(_RadioData('Rádio $g', color, tracks)));
      }
    });
    if (!alive()) return;

    // Artistas favoritos
    await _step(() async {
      final withChannel = artists.where((a) => a.channelId != null).toList();
      if (withChannel.isEmpty) return;
      final avatars = await YoutubeApi.channelAvatars(
          withChannel.map((a) => a.channelId!).toList());
      if (!alive()) return;
      setState(() => _artists = [
            for (final a in withChannel) _ArtistView(a.name, avatars[a.channelId]),
          ]);
    });
    if (!alive()) return;

    // Playlists para você
    await _step(() async {
      final q = artists.isNotEmpty
          ? '${artists.first.name} as melhores'
          : 'sertanejo as melhores playlist';
      final list = await YoutubeApi.searchPlaylists(q);
      if (!alive()) return;
      setState(() => _playlists = list);
    });
    if (!alive()) return;

    // Novos lançamentos
    await _step(() async {
      final list = await YoutubeApi.latest();
      if (!alive()) return;
      setState(() => _latest = list);
    });
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
            await YoutubeApi.clearCache();
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
          if (_mixes.isNotEmpty) ...[
            const SectionTitle('Seus mixes mais ouvidos'),
            HList(
              height: 204,
              children: [
                for (final m in _mixes)
                  MixCard(
                    title: m.title,
                    subtitle: m.subtitle,
                    cover: m.cover,
                    onTap: () => playerCtrl.playQueue(m.tracks, 0),
                  ),
              ],
            ),
          ],
          if (_trending.isNotEmpty) ...[
            const SectionTitle('Em alta no Brasil',
                subtitle: 'Músicas do YouTube'),
            TrackCarousel(tracks: _trending),
          ],
          if (_radios.isNotEmpty) ...[
            const SectionTitle('Estações recomendadas'),
            HList(
              height: 150,
              children: [
                for (final r in _radios)
                  RadioCard(
                    title: r.title,
                    color: r.color,
                    onTap: () => playerCtrl.playShuffled(r.tracks),
                  ),
              ],
            ),
          ],
          if (_artists.isNotEmpty) ...[
            const SectionTitle('Seus artistas favoritos'),
            HList(
              height: 156,
              children: [
                for (final a in _artists)
                  ArtistAvatar(
                    name: a.name,
                    url: a.avatar,
                    onTap: () => _push(CollectionPage(
                      title: a.name,
                      subtitle: 'Músicas mais populares',
                      imageUrl: a.avatar,
                      round: true,
                      loader: () => YoutubeApi.search(a.name),
                    )),
                  ),
              ],
            ),
          ],
          if (_playlists.isNotEmpty) ...[
            const SectionTitle('Playlists para você'),
            HList(
              height: 222,
              children: [
                for (final pl in _playlists)
                  PlaylistCard(
                    info: pl,
                    onTap: () => _push(CollectionPage(
                      title: pl.title,
                      subtitle: pl.channel,
                      imageUrl: pl.artwork,
                      loader: () => YoutubeApi.playlistTracks(pl.id),
                    )),
                  ),
              ],
            ),
          ],
          if (_latest.isNotEmpty) ...[
            const SectionTitle('Novos lançamentos',
                subtitle: 'Das últimas semanas'),
            TrackCarousel(tracks: _latest),
          ],
        ],
      ],
    ];
  }
}

// ---------------------------------------------------------------------------
// Página de coleção (playlist do YouTube ou artista)
// ---------------------------------------------------------------------------

class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    required this.title,
    required this.loader,
    this.subtitle,
    this.imageUrl,
    this.round = false,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final bool round;
  final Future<List<Track>> Function() loader;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late Future<List<Track>> _future = widget.loader();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: bg),
        body: FutureBuilder<List<Track>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: StateMessage(
                  icon: Icons.wifi_off,
                  title: 'Não consegui carregar',
                  subtitle: '${snapshot.error}',
                  onRetry: () => setState(() => _future = widget.loader()),
                ),
              );
            }
            final tracks = snapshot.data ?? <Track>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Center(
                  child: Art(
                    url: widget.imageUrl ??
                        (tracks.isEmpty ? null : tracks.first.artwork),
                    size: 170,
                    radius: widget.round ? 85 : 14,
                  ),
                ),
                const SizedBox(height: 14),
                Text(widget.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                if (widget.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(widget.subtitle!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: muted)),
                  ),
                const SizedBox(height: 14),
                if (tracks.isEmpty)
                  const StateMessage(
                    icon: Icons.music_off,
                    title: 'Nenhuma música encontrada',
                  )
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => playerCtrl.playQueue(tracks, 0),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Tocar'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => playerCtrl.playShuffled(tracks),
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Aleatório'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(
                    tracks.length,
                    (i) => TrackTile(
                      track: tracks[i],
                      onTap: () => playerCtrl.playQueue(tracks, i),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );
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
    if (_error == null) libStore.addSearch(query);
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
              if (libStore.searches.isNotEmpty) ...[
                Row(
                  children: [
                    const Expanded(child: SectionTitle('Buscas recentes')),
                    TextButton(
                      onPressed: libStore.clearSearches,
                      child: const Text('Limpar'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final q in libStore.searches)
                      ActionChip(
                        avatar: const Icon(Icons.history, size: 18),
                        label: Text(q),
                        onPressed: () {
                          _text.text = q;
                          _search(q);
                        },
                      ),
                  ],
                ),
              ],
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
