import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ion.dart';
import 'package:intl/intl.dart';
import 'package:nimbus/core/media/media_item.dart';
import 'package:nimbus/core/media/thumbnail_ref.dart';
import 'package:nimbus/screens/media_viewer/media_viewer_item.dart';
import 'package:nimbus/services/album_repository.dart';
import 'package:nimbus/services/hive_trash.dart';
import 'package:nimbus/services/trash_repository.dart';
import 'package:nimbus/services/prefs_album.dart';
import 'package:nimbus/widgets/toast.dart';
import 'package:photo_manager/photo_manager.dart';

class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen._({
    required this.items,
    required this.initialIndex,
    required this.isFromAppAlbum,
    required this.appAlbumId,
    required this.appAlbumRepository,
    required this.recentlyDeletedRepository,
  });

  factory MediaViewerScreen.items({
    required List<MediaViewerItem> items,
    required int initialIndex,
    bool isFromAppAlbum = false,
    String? appAlbumId,
    AppAlbumRepository? appAlbumRepository,
    RecentlyDeletedRepository? recentlyDeletedRepository,
  }) {
    final List<MediaViewerItem> normalized = items.isEmpty
        ? const <MediaViewerItem>[]
        : List<MediaViewerItem>.from(items);
    final int safeInitialIndex = normalized.isEmpty
        ? 0
        : initialIndex.clamp(0, normalized.length - 1);
    return MediaViewerScreen._(
      items: normalized,
      initialIndex: safeInitialIndex,
      isFromAppAlbum: isFromAppAlbum,
      appAlbumId: appAlbumId,
      appAlbumRepository:
          appAlbumRepository ?? SharedPreferencesAppAlbumRepository.instance,
      recentlyDeletedRepository:
          recentlyDeletedRepository ?? HiveRecentlyDeletedRepository.instance,
    );
  }

  factory MediaViewerScreen.asset({required MediaItem item}) {
    return MediaViewerScreen.items(
      items: <MediaViewerItem>[MediaViewerItem.asset(item)],
      initialIndex: 0,
    );
  }

  factory MediaViewerScreen.localFile({
    required String filePath,
    required bool isVideo,
  }) {
    return MediaViewerScreen.items(
      items: <MediaViewerItem>[
        MediaViewerItem.localFile(path: filePath, isVideo: isVideo),
      ],
      initialIndex: 0,
    );
  }

  final List<MediaViewerItem> items;
  final int initialIndex;
  final bool isFromAppAlbum;
  final String? appAlbumId;
  final AppAlbumRepository appAlbumRepository;
  final RecentlyDeletedRepository recentlyDeletedRepository;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  static const Color _favoriteColor = Color(0xFFF29AA3);

  late PageController _pageController;
  late int _currentIndex;
  late List<MediaViewerItem> _items;
  BetterPlayerController? _videoController;
  bool _isCurrentVideoPortrait = false;
  final Map<String, Future<File?>> _fileFutures = <String, Future<File?>>{};
  final Map<String, bool> _favoriteStates = <String, bool>{};

  MediaViewerItem get _currentItem => _items[_currentIndex];

  bool get _canRemoveFromAlbum {
    return widget.isFromAppAlbum && (widget.appAlbumId?.isNotEmpty ?? false);
  }

  @override
  void initState() {
    super.initState();
    _items = List<MediaViewerItem>.from(widget.items);
    _currentIndex = _items.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _initializeVideoForCurrent();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoController?.dispose(forceDispose: true);
    super.dispose();
  }

  Future<File?> _resolveFile(MediaViewerItem item) async {
    if (item.source == MediaViewerItemSource.localFile) {
      final String? path = item.localFilePath;
      if (path == null) {
        return null;
      }
      return File(path);
    }

    final MediaItem? mediaItem = item.assetItem;
    if (mediaItem == null) {
      return null;
    }

    final ThumbnailRef thumbnail = mediaItem.thumbnail;
    if (thumbnail is! AssetEntityThumbnailRef) {
      return null;
    }

    return thumbnail.asset.file;
  }

  Future<File?> _resolveFileCached(MediaViewerItem item) {
    return _fileFutures.putIfAbsent(item.id, () => _resolveFile(item));
  }

  AssetEntity? _assetEntityForItem(MediaViewerItem item) {
    final MediaItem? mediaItem = item.assetItem;
    if (mediaItem == null) {
      return null;
    }
    final ThumbnailRef thumbnail = mediaItem.thumbnail;
    if (thumbnail is AssetEntityThumbnailRef) {
      return thumbnail.asset;
    }
    return null;
  }

  Future<void> _initializeVideoForCurrent() async {
    final BetterPlayerController? previous = _videoController;
    _videoController = null;
    previous?.dispose(forceDispose: true);

    if (!mounted || _items.isEmpty) {
      return;
    }

    final MediaViewerItem item = _currentItem;
    if (!item.isVideo) {
      setState(() {
        _isCurrentVideoPortrait = false;
      });
      return;
    }

    final File? file = await _resolveFileCached(item);
    if (!mounted || file == null || !await file.exists()) {
      setState(() {});
      return;
    }

    final BetterPlayerController controller = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoPlay: true,
        fit: BoxFit.contain,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
          enableFullscreen: false,
        ),
      ),
    );
    final BetterPlayerDataSource source = BetterPlayerDataSource(
      BetterPlayerDataSourceType.file,
      file.path,
    );
    await controller.setupDataSource(source);
    final double aspectRatio =
        controller.videoPlayerController?.value.aspectRatio ?? (16 / 9);
    final bool isPortraitVideo = aspectRatio > 0 && aspectRatio < 1;
    controller.setOverriddenFit(
      isPortraitVideo ? BoxFit.cover : BoxFit.contain,
    );
    if (!mounted) {
      controller.dispose(forceDispose: true);
      return;
    }
    controller.play();

    setState(() {
      _videoController = controller;
      _isCurrentVideoPortrait = isPortraitVideo;
    });
  }

  bool _canFavorite(MediaViewerItem item) {
    return item.source == MediaViewerItemSource.asset;
  }

  bool _isFavorite(MediaViewerItem item) {
    final bool? cached = _favoriteStates[item.id];
    if (cached != null) {
      return cached;
    }
    final AssetEntity? asset = _assetEntityForItem(item);
    return asset?.isFavorite ?? false;
  }

  Future<void> _toggleFavoriteCurrent() async {
    if (_items.isEmpty) {
      return;
    }
    final MediaViewerItem item = _currentItem;
    if (!_canFavorite(item)) {
      return;
    }
    final AssetEntity? asset = _assetEntityForItem(item);
    if (asset == null) {
      return;
    }
    final bool next = !_isFavorite(item);
    if (Platform.isAndroid) {
      await PhotoManager.editor.android.favoriteAsset(
        entity: asset,
        favorite: next,
      );
    } else if (Platform.isIOS || Platform.isMacOS) {
      await PhotoManager.editor.darwin.favoriteAsset(
        entity: asset,
        favorite: next,
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _favoriteStates[item.id] = next;
    });
    AppToast.show(
      context,
      next ? 'Added to favorites' : 'Removed from favorites',
    );
  }

  Future<void> _showInfo() async {
    if (_items.isEmpty) {
      return;
    }
    final MediaViewerItem item = _currentItem;
    final File? file = await _resolveFileCached(item);
    if (!mounted) {
      return;
    }

    String sizeLabel = 'Unavailable';
    String pathLabel = 'Unavailable';
    DateTime? timestamp = item.assetItem?.createdAt;

    if (file != null && await file.exists()) {
      final FileStat stat = await file.stat();
      final double sizeMb = stat.size / (1024 * 1024);
      sizeLabel = '${sizeMb.toStringAsFixed(2)} MB';
      pathLabel = file.path;
      timestamp ??= stat.changed.toLocal();
    }

    final String dateLabel = timestamp == null
        ? 'Unavailable'
        : DateFormat('dd MMM yyyy, hh:mm a').format(timestamp.toLocal());

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Info',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Size: $sizeLabel'),
                const SizedBox(height: 8),
                Text('Date: $dateLabel'),
                const SizedBox(height: 8),
                Text(
                  'Path: $pathLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareCurrent() async {
    if (_items.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }

    AppToast.show(
      context,
      'Share is temporarily unavailable in this build.',
    );
  }

  Future<void> _removeFromAlbum() async {
    if (!_canRemoveFromAlbum || _items.isEmpty) {
      return;
    }
    final MediaViewerItem item = _currentItem;
    final Set<String> mediaIds = <String>{};
    final Set<String> localPaths = <String>{};

    if (item.source == MediaViewerItemSource.asset) {
      final String? mediaId = item.assetItem?.id;
      if (mediaId != null) {
        mediaIds.add(mediaId);
      }
    } else {
      final String? path = item.localFilePath;
      if (path != null) {
        localPaths.add(path);
        final File file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    await widget.appAlbumRepository.removeMediaFromAlbum(
      widget.appAlbumId!,
      mediaIds: mediaIds,
      localPaths: localPaths,
    );
    _removeCurrentFromState();
  }

  Future<void> _trashCurrent() async {
    if (_items.isEmpty) {
      return;
    }
    final MediaViewerItem item = _currentItem;

    try {
      if (item.source == MediaViewerItemSource.asset) {
        final AssetEntity? asset = _assetEntityForItem(item);
        if (asset != null) {
          await widget.recentlyDeletedRepository.markDeleted(<String>[
            asset.id,
          ]);
        }

        if (_canRemoveFromAlbum) {
          await widget.appAlbumRepository.removeMediaFromAlbum(
            widget.appAlbumId!,
            mediaIds: <String>{item.assetItem?.id ?? ''}..remove(''),
          );
        }
      } else {
        final String? path = item.localFilePath;
        if (path != null) {
          final File file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        }
        if (_canRemoveFromAlbum) {
          await widget.appAlbumRepository.removeMediaFromAlbum(
            widget.appAlbumId!,
            localPaths: <String>{item.localFilePath ?? ''}..remove(''),
          );
        }
      }

      _removeCurrentFromState();
    } catch (_) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'Could not move file to trash.');
    }
  }

  void _removeCurrentFromState() {
    if (_items.isEmpty) {
      return;
    }

    final String removedId = _items[_currentIndex].id;
    setState(() {
      _items.removeAt(_currentIndex);
      _favoriteStates.remove(removedId);
      if (_items.isEmpty) {
        return;
      }
      if (_currentIndex >= _items.length) {
        _currentIndex = _items.length - 1;
      }
    });

    if (_items.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }

    final PageController oldController = _pageController;
    _pageController = PageController(initialPage: _currentIndex);
    oldController.dispose();
    _initializeVideoForCurrent();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No media available',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Iconify(Ion.arrow_back, color: Colors.white, size: 22),
        ),
        title: Text(
          '${_currentIndex + 1}/${_items.length}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Info',
            onPressed: _showInfo,
            icon: const Iconify(
              Ion.information_circled,
              color: Colors.white,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Share',
            onPressed: _shareCurrent,
            icon: const Iconify(
              Ion.share_social,
              color: Colors.white,
              size: 20,
            ),
          ),
          if (_canFavorite(_currentItem))
            IconButton(
              tooltip: 'Favorite',
              onPressed: _toggleFavoriteCurrent,
              icon: Iconify(
                _isFavorite(_currentItem) ? Ion.heart : Ion.heart_outline,
                color: _isFavorite(_currentItem)
                    ? _favoriteColor
                    : Colors.white,
                size: 20,
              ),
            ),
          if (_canRemoveFromAlbum)
            IconButton(
              tooltip: 'Remove from album',
              onPressed: _removeFromAlbum,
              icon: const Iconify(
                Ion.md_remove_circle_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
          IconButton(
            tooltip: 'Trash',
            onPressed: _trashCurrent,
            icon: const Iconify(Ion.trash, color: Colors.white, size: 20),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _items.length,
        onPageChanged: (int index) {
          setState(() {
            _currentIndex = index;
          });
          _initializeVideoForCurrent();
        },
        itemBuilder: (BuildContext context, int index) {
          final MediaViewerItem item = _items[index];
          if (item.isVideo) {
            return _buildVideo(index);
          }
          return Center(child: _buildImage(item));
        },
      ),
    );
  }

  Widget _buildVideo(int index) {
    if (index != _currentIndex) {
      return const SizedBox.expand();
    }

    final BetterPlayerController? controller = _videoController;
    if (controller == null) {
      return const CircularProgressIndicator();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double aspectRatio =
            controller.videoPlayerController?.value.aspectRatio ?? (16 / 9);
        final Widget video = _isCurrentVideoPortrait
            ? Positioned.fill(child: BetterPlayer(controller: controller))
            : Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: (constraints.maxWidth / aspectRatio).clamp(
                    0.0,
                    constraints.maxHeight,
                  ),
                  child: BetterPlayer(controller: controller),
                ),
              );

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[video, _buildBottomVideoControls(controller)],
        );
      },
    );
  }

  Widget _buildBottomVideoControls(BetterPlayerController controller) {
    final dynamic videoController = controller.videoPlayerController;
    if (videoController == null) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: AnimatedBuilder(
            animation: videoController,
            builder: (BuildContext context, _) {
              final dynamic value = videoController.value;
              final Duration duration =
                  (value.duration as Duration?) ?? Duration.zero;
              final Duration position = value.position > duration
                  ? duration
                  : value.position;
              final double maxMs = duration.inMilliseconds <= 0
                  ? 1
                  : duration.inMilliseconds.toDouble();
              final bool isMuted = value.volume == 0;
              final bool isPlaying = value.isPlaying;

              return DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x7A000000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () =>
                            isPlaying ? controller.pause() : controller.play(),
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      IconButton(
                        onPressed: () => controller.setVolume(isMuted ? 1 : 0),
                        icon: Icon(
                          isMuted
                              ? Icons.volume_off_outlined
                              : Icons.volume_up_outlined,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                          ),
                          child: Slider(
                            value: position.inMilliseconds.toDouble().clamp(
                              0,
                              maxMs,
                            ),
                            min: 0,
                            max: maxMs,
                            onChanged: (double next) {
                              controller.seekTo(
                                Duration(milliseconds: next.round()),
                              );
                            },
                          ),
                        ),
                      ),
                      Text(
                        '${_formatDuration(position)} / ${_formatDuration(duration)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    final int hours = duration.inHours;
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  Widget _buildImage(MediaViewerItem item) {
    return FutureBuilder<File?>(
      future: _resolveFileCached(item),
      builder: (BuildContext context, AsyncSnapshot<File?> snapshot) {
        final File? file = snapshot.data;
        if (file == null) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CircularProgressIndicator();
          }
          return const Text(
            'Unable to load media',
            style: TextStyle(color: Colors.white70),
          );
        }

        return InteractiveViewer(child: Image.file(file));
      },
    );
  }
}
