import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'core.dart';
import 'player_pages.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Início
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _chips = ['Tudo', 'Favoritas', 'Do celular', 'Recentes'];

  int _chip = 0;
  List<Track> _trending = [];
  List<Track> _forYou = [];
  String _forYouGenre = 'Electronic';
  bool _hasTopGenre = false;
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
      final top = libStore.topGenre;
      final genre = top ?? 'Electronic';
      final results = await Future.wait([
        AudiusApi.trending(limit: 20),
        AudiusApi.trending(genre: genre, time: 'month', limit: 20),
      ]);
      if (!mounted) return;
      setState(() {
        _trending = results[0];
        _forYou = results[1];
        _forYouGenre = genre;
        _hasTopGenre = top != null;
      });
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

  List<Track> _chipTracks() {
    switch (_chip) {
      case 1:
        return libStore.favorites;
      case 2:
        return libStore.locals;
      default:
        return libStore.recents;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: libStore,
        builder: (context, _) => RefreshIndicator(
          onRefresh: _load,
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
                    tooltip: 'Modo moto',
                    onPressed: () => _push(const MotoModePage()),
                    icon: const Icon(Icons.two_wheeler, color: blue, size: 28),
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
              : _chip == 2
                  ? 'Adicione músicas do celular na aba Biblioteca.'
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
      if (recents.isNotEmpty) ...[
        const SectionTitle('Continue ouvindo'),
        TrackCarousel(tracks: recents),
      ],
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
          const SectionTitle('Em alta agora', subtitle: 'Streaming pela Audius'),
          TrackCarousel(tracks: _trending),
        ],
        if (_forYou.isNotEmpty) ...[
          SectionTitle(
            _hasTopGenre
                ? 'Mais de $_forYouGenre para você'
                : 'Descubra: $_forYouGenre',
            subtitle: _hasTopGenre
                ? 'Com base no que você mais ouve'
                : 'Ouça mais e eu aprendo o seu gosto',
          ),
          TrackCarousel(tracks: _forYou),
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
  Timer? _debounce;
  List<Track> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _genreTitle;
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
    await _run(() => AudiusApi.search(query));
  }

  Future<void> _openGenre(String genre) async {
    FocusScope.of(context).unfocus();
    _text.clear();
    setState(() => _genreTitle = genre);
    await _run(() => AudiusApi.trending(genre: genre, time: 'month', limit: 30));
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
    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Text('Buscar',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        TextField(
          controller: _text,
          onChanged: _onChanged,
          onSubmitted: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'O que você quer ouvir?',
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
        if (_genreTitle != null)
          Row(
            children: [
              IconButton(
                onPressed: _clearGenre,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text('Em alta em $_genreTitle',
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
                ? _openGenre(_genreTitle!)
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
            itemCount: kGenres.length,
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
                onTap: () => _openGenre(kGenres[i]),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(kGenres[i],
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
      await libStore.addLocals(items);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Não consegui abrir os arquivos: $e');
    }
  }

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
                if (_section == 2)
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
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Favoritas')),
                ButtonSegment(value: 1, label: Text('Playlists')),
                ButtonSegment(value: 2, label: Text('Do celular')),
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
    final list = _section == 0 ? libStore.favorites : libStore.locals;
    if (list.isEmpty) {
      return [
        StateMessage(
          icon: _section == 0 ? Icons.favorite_border : Icons.folder_open,
          title: _section == 0
              ? 'Nenhuma favorita ainda'
              : 'Nenhum arquivo adicionado',
          subtitle: _section == 0
              ? 'Toque no coração de uma música para guardar aqui.'
              : 'Use o botão + para escolher músicas do celular.',
        ),
      ];
    }
    return List.generate(
      list.length,
      (i) => TrackTile(
        track: list[i],
        onTap: () => playerCtrl.playQueue(list, i),
        extra: _section == 2
            ? [
                MenuAction(
                  'Remover da lista',
                  Icons.delete_outline,
                  () => libStore.removeLocal(list[i].id),
                ),
              ]
            : const [],
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
