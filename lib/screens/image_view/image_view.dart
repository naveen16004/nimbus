import 'dart:io';

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

class ImageViewScreen extends StatefulWidget {
  const ImageViewScreen._({
    required this.items,
    required this.initialIndex,
    required this.isFromAppAlbum,
    required this.appAlbumId,
    required this.appAlbumRepository,
    required this.recentlyDeletedRepository,
  });

  factory ImageViewScreen.items({
    required List<MediaViewerItem> items,
    required int initialIndex,
    bool isFromAppAlbum = false,
    String? appAlbumId,
    AppAlbumRepository? appAlbumRepository,
    RecentlyDeletedRepository? recentlyDeletedRepository,
  }) {
    final List<MediaViewerItem> imageItems = items
        .where((MediaViewerItem item) => !item.isVideo)
        .toList(growable: false);
    final int safeInitialIndex = imageItems.isEmpty
        ? 0
        : initialIndex.clamp(0, imageItems.length - 1);
    return ImageViewScreen._(
      items: imageItems,
      initialIndex: safeInitialIndex,
      isFromAppAlbum: isFromAppAlbum,
      appAlbumId: appAlbumId,
      appAlbumRepository:
          appAlbumRepository ?? SharedPreferencesAppAlbumRepository.instance,
      recentlyDeletedRepository:
          recentlyDeletedRepository ?? HiveRecentlyDeletedRepository.instance,
    );
  }

  factory ImageViewScreen.asset({required MediaItem item}) {
    return ImageViewScreen.items(
      items: <MediaViewerItem>[MediaViewerItem.asset(item)],
      initialIndex: 0,
    );
  }

  factory ImageViewScreen.localFile({
    required String filePath,
    bool isFromAppAlbum = false,
    String? appAlbumId,
    AppAlbumRepository? appAlbumRepository,
    RecentlyDeletedRepository? recentlyDeletedRepository,
  }) {
    return ImageViewScreen.items(
      items: <MediaViewerItem>[
        MediaViewerItem.localFile(path: filePath, isVideo: false),
      ],
      initialIndex: 0,
      isFromAppAlbum: isFromAppAlbum,
      appAlbumId: appAlbumId,
      appAlbumRepository: appAlbumRepository,
      recentlyDeletedRepository: recentlyDeletedRepository,
    );
  }

  final List<MediaViewerItem> items;
  final int initialIndex;
  final bool isFromAppAlbum;
  final String? appAlbumId;
  final AppAlbumRepository appAlbumRepository;
  final RecentlyDeletedRepository recentlyDeletedRepository;

  @override
  State<ImageViewScreen> createState() => _ImageViewScreenState();
}

class _ImageViewScreenState extends State<ImageViewScreen> {
  static const int _initialLoopMultiplier = 10000;
  static const Color _favoriteColor = Color(0xFFF29AA3);

  late List<MediaViewerItem> _items;
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<String, Future<File?>> _fileFutures = <String, Future<File?>>{};
  final Map<String, bool> _favoriteStates = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _items = List<MediaViewerItem>.from(widget.items);
    if (_items.isNotEmpty) {
      _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    }
    _pageController = _buildController(_currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  PageController _buildController(int logicalIndex) {
    if (_items.length <= 1) {
      return PageController(initialPage: 0);
    }
    return PageController(
      initialPage: (_items.length * _initialLoopMultiplier) + logicalIndex,
    );
  }

  int _logicalIndexForVirtual(int virtualIndex) {
    if (_items.isEmpty) {
      return 0;
    }
    return virtualIndex % _items.length;
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

  MediaViewerItem? get _currentItem {
    if (_items.isEmpty) {
      return null;
    }
    if (_currentIndex < 0 || _currentIndex >= _items.length) {
      return null;
    }
    return _items[_currentIndex];
  }

  bool get _canRemoveFromAlbum {
    return widget.isFromAppAlbum && (widget.appAlbumId?.isNotEmpty ?? false);
  }

  Future<void> _showInfo() async {
    final MediaViewerItem? item = _currentItem;
    if (item == null) {
      return;
    }

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
    if (_currentItem == null) {
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

  bool _canFavorite(MediaViewerItem? item) {
    return item != null && item.source == MediaViewerItemSource.asset;
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
    final MediaViewerItem? item = _currentItem;
    if (!_canFavorite(item)) {
      return;
    }
    final AssetEntity? asset = _assetEntityForItem(item!);
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

  Future<void> _removeFromAlbum() async {
    if (!_canRemoveFromAlbum) {
      return;
    }

    final MediaViewerItem? item = _currentItem;
    if (item == null) {
      return;
    }

    final String albumId = widget.appAlbumId!;
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
      albumId,
      mediaIds: mediaIds,
      localPaths: localPaths,
    );
    _removeCurrentFromState();
  }

  Future<void> _trashCurrent() async {
    final MediaViewerItem? item = _currentItem;
    if (item == null) {
      return;
    }

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

    setState(() {
      final String removedId = _items[_currentIndex].id;
      _items.removeAt(_currentIndex);
      _favoriteStates.remove(removedId);
      if (_items.isEmpty) {
        return;
      }
      if (_currentIndex >= _items.length) {
        _currentIndex = 0;
      }
    });

    if (_items.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }

    final PageController oldController = _pageController;
    _pageController = _buildController(_currentIndex);
    oldController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No images available',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 0,
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
                _isFavorite(_currentItem!) ? Ion.heart : Ion.heart_outline,
                color: _isFavorite(_currentItem!)
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
        itemBuilder: (BuildContext context, int virtualIndex) {
          final int index = _logicalIndexForVirtual(virtualIndex);
          final MediaViewerItem item = _items[index];
          return Center(
            child: FutureBuilder<File?>(
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
            ),
          );
        },
        onPageChanged: (int virtualIndex) {
          setState(() {
            _currentIndex = _logicalIndexForVirtual(virtualIndex);
          });
        },
      ),
    );
  }
}
