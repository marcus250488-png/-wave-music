import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart'
    show YoutubePlayer;

import 'core.dart';

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

String fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:${m.padLeft(2, '0')}:$s' : '$m:$s';
}

class MenuAction {
  const MenuAction(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// ---------------------------------------------------------------------------
// Capas
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

/// Mosaico 2x2 com as primeiras capas (ou uma capa só, se tiver menos de 4).
class Mosaic extends StatelessWidget {
  const Mosaic({
    super.key,
    required this.covers,
    required this.size,
    this.radius = 10,
  });

  final List<String?> covers;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final urls = covers.where((u) => u != null && u.isNotEmpty).toList();
    if (urls.length < 4) {
      return Art(
          url: urls.isEmpty ? null : urls.first, size: size, radius: radius);
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Row(children: [
              Art(url: urls[0], size: half, radius: 0),
              Art(url: urls[1], size: half, radius: 0),
            ]),
            Row(children: [
              Art(url: urls[2], size: half, radius: 0),
              Art(url: urls[3], size: half, radius: 0),
            ]),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mensagens de estado
// ---------------------------------------------------------------------------

class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onRetry,
    this.retryLabel = 'Tentar de novo',
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;
  final String retryLabel;

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
                  onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (subtitle != null)
              Text(subtitle!,
                  style: const TextStyle(color: muted, fontSize: 12)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Itens de música
// ---------------------------------------------------------------------------

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.extra = const [],
  });

  final Track track;
  final VoidCallback onTap;
  final List<MenuAction> extra;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([playerCtrl, libStore]),
        builder: (context, _) {
          final isCurrent = playerCtrl.current?.id == track.id;
          final fav = libStore.isFavorite(track.id);
          return ListTile(
            onTap: onTap,
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => libStore.toggleFavorite(track),
                  icon: Icon(
                    fav ? Icons.favorite : Icons.favorite_border,
                    color: fav ? Colors.pinkAccent : muted,
                  ),
                ),
                IconButton(
                  onPressed: () => showTrackMenu(context, track, extra: extra),
                  icon: const Icon(Icons.more_vert, color: muted),
                ),
              ],
            ),
          );
        },
      );
}

/// Atalho compacto da grade do Início (capa + nome).
class QuickTile extends StatelessWidget {
  const QuickTile({
    super.key,
    required this.title,
    required this.covers,
    required this.onTap,
    this.icon,
  });

  final String title;
  final List<String?> covers;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasCover = covers.any((c) => c != null && c.isNotEmpty);
    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            if (!hasCover && icon != null)
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4B2BD6), Color(0xFF8E6BFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(icon, color: Colors.white),
              )
            else
              Mosaic(covers: covers, size: 56, radius: 0),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// Cartão de carrossel horizontal.
class TrackCard extends StatelessWidget {
  const TrackCard({super.key, required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        onLongPress: () => showTrackMenu(context, track),
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Art(url: track.artwork, size: 140, radius: 10),
              const SizedBox(height: 8),
              Text(track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      );
}

class TrackCarousel extends StatelessWidget {
  const TrackCarousel({super.key, required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 214,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: tracks.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => TrackCard(
            track: tracks[i],
            onTap: () => playerCtrl.playQueue(tracks, i),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Menus e diálogos
// ---------------------------------------------------------------------------

Future<void> showTrackMenu(
  BuildContext context,
  Track track, {
  List<MenuAction> extra = const [],
}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Art(url: track.artwork, size: 46),
              title: Text(track.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(track.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Adicionar a uma playlist'),
              onTap: () {
                Navigator.pop(sheetContext);
                showAddToPlaylist(context, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.skip_next),
              title: const Text('Tocar em seguida'),
              onTap: () {
                Navigator.pop(sheetContext);
                playerCtrl.playNext(track);
                showSnack(context, 'Vai tocar em seguida');
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('Adicionar à fila'),
              onTap: () {
                Navigator.pop(sheetContext);
                playerCtrl.addToQueue(track);
                showSnack(context, 'Adicionada à fila');
              },
            ),
            for (final a in extra)
              ListTile(
                leading: Icon(a.icon),
                title: Text(a.label),
                onTap: () {
                  Navigator.pop(sheetContext);
                  a.onTap();
                },
              ),
          ],
        ),
      ),
    );

Future<String?> promptPlaylistName(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Nova playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nome da playlist'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Criar'),
        ),
      ],
    ),
  );
  if (result == null || result.isEmpty) return null;
  return result;
}

Future<void> showAddToPlaylist(BuildContext context, Track track) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * .7,
          ),
          child: ListenableBuilder(
            listenable: libStore,
            builder: (_, __) => ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Adicionar a uma playlist',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: blue),
                  title: const Text('Nova playlist'),
                  onTap: () async {
                    final name = await promptPlaylistName(sheetContext);
                    if (name == null) return;
                    final p = await libStore.createPlaylist(name);
                    await libStore.addToPlaylist(p, track);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (context.mounted) {
                      showSnack(context, 'Adicionada a "${p.name}"');
                    }
                  },
                ),
                for (final p in libStore.playlists)
                  ListTile(
                    leading: Mosaic(covers: p.covers, size: 46, radius: 8),
                    title: Text(p.name),
                    subtitle: Text('${p.tracks.length} músicas',
                        style: const TextStyle(color: muted)),
                    onTap: () async {
                      await libStore.addToPlaylist(p, track);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (context.mounted) {
                        showSnack(context, 'Adicionada a "${p.name}"');
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Player (vídeo oficial do YouTube + controles). Fica sempre visível enquanto
// toca, como pedem as regras do player incorporado do YouTube.
// ---------------------------------------------------------------------------

class PlayerDock extends StatelessWidget {
  const PlayerDock({
    super.key,
    required this.openPanel,
    required this.onPanel,
  });

  /// Painel aberto no momento: 'lyrics', 'queue' ou null.
  final String? openPanel;
  final void Function(String panel) onPanel;

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([playerCtrl, libStore]),
        builder: (context, _) {
          final ctrl = playerCtrl;
          final track = ctrl.current;
          final yt = ctrl.yt;
          if (track == null || yt == null) return const SizedBox.shrink();
          final fav = libStore.isFavorite(track.id);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            color: ctrl.accent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                YoutubePlayer(controller: yt, aspectRatio: 16 / 9),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 0, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text(
                              ctrl.sleepAt != null
                                  ? '${track.artist} • desliga às ${_hhmm(ctrl.sleepAt!)}'
                                  : track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => libStore.toggleFavorite(track),
                        icon: Icon(
                          fav ? Icons.favorite : Icons.favorite_border,
                          color: fav ? Colors.pinkAccent : Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: () => ctrl.previous(),
                        icon: const Icon(Icons.skip_previous),
                      ),
                      IconButton(
                        onPressed: () => ctrl.togglePlay(),
                        icon: Icon(ctrl.playing ? Icons.pause : Icons.play_arrow,
                            size: 30),
                      ),
                      IconButton(
                        onPressed: () => ctrl.next(),
                        icon: const Icon(Icons.skip_next),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        color: panel,
                        onSelected: (value) {
                          switch (value) {
                            case 'shuffle':
                              ctrl.toggleShuffle();
                            case 'repeat':
                              ctrl.cycleRepeat();
                            case 'lyrics':
                              onPanel('lyrics');
                            case 'queue':
                              onPanel('queue');
                            case 'music':
                              launchUrl(
                                Uri.parse(
                                    'https://music.youtube.com/watch?v=${track.id}'),
                                mode: LaunchMode.externalApplication,
                              );
                            case 'sleep':
                              showSleepSheet(context);
                            case 'playlist':
                              showAddToPlaylist(context, track);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'lyrics',
                            child: Text(openPanel == 'lyrics' ? 'Fechar letra' : 'Ver letra'),
                          ),
                          PopupMenuItem(
                            value: 'queue',
                            child: Text(openPanel == 'queue' ? 'Fechar fila' : 'Ver fila'),
                          ),
                          PopupMenuItem(
                            value: 'shuffle',
                            child: Text(
                                'Aleatório: ${ctrl.shuffle ? 'ligado' : 'desligado'}'),
                          ),
                          PopupMenuItem(
                            value: 'repeat',
                            child: Text(
                                'Repetir: ${ctrl.repeat == WaveRepeat.off ? 'desligado' : ctrl.repeat == WaveRepeat.all ? 'todas' : 'uma música'}'),
                          ),
                          const PopupMenuItem(
                            value: 'sleep',
                            child: Text('Timer para dormir'),
                          ),
                          const PopupMenuItem(
                            value: 'playlist',
                            child: Text('Adicionar a uma playlist'),
                          ),
                          const PopupMenuItem(
                            value: 'music',
                            child: Text('Abrir no YouTube Music'),
                          ),
                        ],
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

// ---------------------------------------------------------------------------
// Timer para dormir
// ---------------------------------------------------------------------------

void showSleepSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: panel,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Timer para dormir',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final m in const [15, 30, 45, 60])
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text('$m minutos'),
              onTap: () {
                playerCtrl.setSleepTimer(Duration(minutes: m));
                Navigator.pop(sheetContext);
                showSnack(context, 'A música para em $m minutos');
              },
            ),
          if (playerCtrl.sleepAt != null)
            ListTile(
              leading: const Icon(Icons.timer_off_outlined),
              title: const Text('Cancelar timer'),
              onTap: () {
                playerCtrl.setSleepTimer(null);
                Navigator.pop(sheetContext);
                showSnack(context, 'Timer cancelado');
              },
            ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Cartões e carrosséis estilo "streaming"
// ---------------------------------------------------------------------------

/// Carrossel horizontal genérico.
class HList extends StatelessWidget {
  const HList({super.key, required this.height, required this.children});

  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => children[i],
        ),
      );
}

/// "Mix de ..." — capa com selo e artistas embaixo.
class MixCard extends StatelessWidget {
  const MixCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String? cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Art(url: cover, size: 150, radius: 10),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: blue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      );
}

/// "Rádio ..." — quadrado colorido.
class RadioCard extends StatelessWidget {
  const RadioCard({
    super.key,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 150,
          height: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: .55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('RÁDIO',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                      color: Colors.white70)),
              const Spacer(),
              Text(title.replaceFirst('Rádio ', ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
            ],
          ),
        ),
      );
}

/// Playlist do YouTube.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.info, required this.onTap});

  final PlaylistInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Art(url: info.artwork, size: 150, radius: 10),
              const SizedBox(height: 8),
              Text(info.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(info.channel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      );
}

/// Artista em círculo.
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({
    super.key,
    required this.name,
    required this.url,
    required this.onTap,
  });

  final String name;
  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 108,
          child: Column(
            children: [
              Art(url: url, size: 100, radius: 50),
              const SizedBox(height: 8),
              Text(name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
      );
}
