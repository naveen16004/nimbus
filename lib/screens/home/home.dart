import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ion.dart';
import 'package:nimbus/core/media/day_group.dart';
import 'package:nimbus/core/media/media_item.dart';
import 'package:nimbus/core/media/media_repository.dart';
import 'package:nimbus/core/media/media_type.dart';
import 'package:nimbus/core/media/photo_repository.dart';
import 'package:nimbus/core/media/thumbnail_ref.dart';
import 'package:nimbus/models/app_album.dart';
import 'package:nimbus/models/sync_record.dart';
import 'package:nimbus/screens/home/grid_density.dart';
import 'package:nimbus/screens/home/media_grouping.dart';
import 'package:nimbus/screens/home/selection_controller.dart';
import 'package:nimbus/screens/image_view/image_view.dart';
import 'package:nimbus/screens/media_viewer/media_viewer.dart';
import 'package:nimbus/screens/media_viewer/media_viewer_item.dart';
import 'package:nimbus/services/album_repository.dart';
import 'package:nimbus/services/sync_repository.dart';
import 'package:nimbus/services/hive_sync.dart';
import 'package:nimbus/services/hive_trash.dart';
import 'package:nimbus/services/mock_sync.dart';
import 'package:nimbus/services/trash_repository.dart';
import 'package:nimbus/services/prefs_album.dart';
import 'package:nimbus/theme/colors.dart';
import 'package:nimbus/widgets/sync_badge.dart';
import 'package:nimbus/widgets/top_bar.dart';
import 'package:nimbus/widgets/toast.dart';
import 'package:nimbus/widgets/action_button.dart';
import 'package:photo_manager/photo_manager.dart';

class HomeScreen extends StatefulWidget {
  HomeScreen({
    super.key,
    MediaRepository? repository,
    AppAlbumRepository? appAlbumRepository,
    RecentlyDeletedRepository? recentlyDeletedRepository,
    CloudSyncRepository? cloudSyncRepository,
    MockCloudSyncService? cloudSyncService,
    this.onSelectionModeChanged,
  }) : repository = repository ?? PhotoManagerMediaRepository(),
       appAlbumRepository =
           appAlbumRepository ?? SharedPreferencesAppAlbumRepository.instance,
       recentlyDeletedRepository =
           recentlyDeletedRepository ?? HiveRecentlyDeletedRepository.instance,
       cloudSyncRepository =
           cloudSyncRepository ?? HiveCloudSyncRepository.instance,
       cloudSyncService =
           cloudSyncService ??
           MockCloudSyncService(
             cloudSyncRepository ?? HiveCloudSyncRepository.instance,
           );

  final MediaRepository repository;
  final AppAlbumRepository appAlbumRepository;
  final RecentlyDeletedRepository recentlyDeletedRepository;
  final CloudSyncRepository cloudSyncRepository;
  final MockCloudSyncService cloudSyncService;
  final ValueChanged<bool>? onSelectionModeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final HomeSelectionController _selectionController;
  late final HomeGridDensityController _gridDensityController;

  List<MediaItem> _mediaItems = const <MediaItem>[];
  List<MediaDayGroup> _groups = const <MediaDayGroup>[];
  bool _isLoading = true;
  bool _permissionDenied = false;
  bool _isApplyingSelectionAction = false;
  bool _isCloudSyncing = false;
  int _cloudSyncTotal = 0;
  int _cloudSyncCompleted = 0;
  String? _cloudSyncPhase;
  double _cloudSyncCurrentProgress = 0;
  String? _errorMessage;
  Map<String, CloudSyncRecord> _syncRecordsById =
      const <String, CloudSyncRecord>{};
  StreamSubscription<Map<String, CloudSyncRecord>>? _syncSubscription;
  StreamSubscription<Set<String>>? _deletedSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectionController = HomeSelectionController()
      ..addListener(_handleSelectionChanged);
    _gridDensityController = HomeGridDensityController()
      ..addListener(_handleGridDensityChanged);
    _syncSubscription = widget.cloudSyncRepository.watchAll().listen((
      Map<String, CloudSyncRecord> records,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncRecordsById = records;
      });
    });
    _deletedSubscription = widget.recentlyDeletedRepository
        .watchDeletedIds()
        .listen((Set<String> _) {
          _loadMedia(isRefresh: true);
        });
    _loadMedia();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.onSelectionModeChanged?.call(false);
    _selectionController
      ..removeListener(_handleSelectionChanged)
      ..dispose();
    _gridDensityController
      ..removeListener(_handleGridDensityChanged)
      ..dispose();
    _syncSubscription?.cancel();
    _deletedSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMedia(isRefresh: true);
    }
  }

  void _handleSelectionChanged() {
    widget.onSelectionModeChanged?.call(_selectionController.isSelectionMode);
    setState(() {});
  }

  void _handleGridDensityChanged() {
    setState(() {});
  }

  void _toggleGridDensity() {
    _gridDensityController.toggle();
  }

  Future<void> _loadMedia({bool isRefresh = false}) async {
    if (!mounted) {
      return;
    }

    setState(() {
      if (!isRefresh) {
        _isLoading = true;
      }
      _errorMessage = null;
    });

    try {
      final MediaPermissionStatus permissionStatus = await widget.repository
          .requestPermission();
      if (permissionStatus == MediaPermissionStatus.denied) {
        setState(() {
          _isLoading = false;
          _permissionDenied = true;
          _mediaItems = const <MediaItem>[];
          _groups = const <MediaDayGroup>[];
        });
        return;
      }

      final List<MediaItem> mediaItems = isRefresh
          ? await widget.repository.refreshMedia()
          : await widget.repository.fetchAllMedia();
      final Set<String> deletedIds = await widget.recentlyDeletedRepository
          .listDeletedIds();
      final List<MediaItem> visibleMedia = mediaItems
          .where((MediaItem item) => !deletedIds.contains(item.id))
          .toList(growable: false);
      final Map<String, CloudSyncRecord> syncRecords = await widget
          .cloudSyncRepository
          .getForIds(visibleMedia.map((MediaItem item) => item.id));
      final List<MediaItem> mergedMedia = visibleMedia
          .map(
            (MediaItem item) => item.copyWith(
              isSynced: syncRecords[item.id]?.isSynced ?? false,
            ),
          )
          .toList(growable: false);

      setState(() {
        _isLoading = false;
        _permissionDenied = false;
        _mediaItems = mergedMedia;
        _groups = groupMediaItemsByDay(mergedMedia);
        _syncRecordsById = <String, CloudSyncRecord>{
          ..._syncRecordsById,
          ...syncRecords,
        };
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _permissionDenied = false;
        _mediaItems = const <MediaItem>[];
        _groups = const <MediaDayGroup>[];
        _errorMessage = 'Could not load media from device storage.';
      });
    }
  }

  MediaViewerItem _viewerItemForHome(MediaItem item) {
    return MediaViewerItem.asset(item);
  }

  Future<void> _openHomeMediaViewer(MediaItem tappedItem) async {
    final List<MediaViewerItem> viewerItems = _mediaItems
        .map(_viewerItemForHome)
        .toList(growable: false);
    if (viewerItems.isEmpty) {
      return;
    }

    if (tappedItem.type == MediaType.image) {
      final List<MediaViewerItem> imageItems = viewerItems
          .where((MediaViewerItem item) => !item.isVideo)
          .toList(growable: false);
      final int imageIndex = imageItems.indexWhere(
        (MediaViewerItem item) => item.id == tappedItem.id,
      );
      if (imageIndex < 0) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewScreen.items(
            items: imageItems,
            initialIndex: imageIndex,
            isFromAppAlbum: false,
            recentlyDeletedRepository: widget.recentlyDeletedRepository,
          ),
        ),
      );
      if (mounted) {
        await _loadMedia(isRefresh: true);
      }
      return;
    }

    final int initialIndex = viewerItems.indexWhere(
      (MediaViewerItem item) => item.id == tappedItem.id,
    );
    if (initialIndex < 0) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaViewerScreen.items(
          items: viewerItems,
          initialIndex: initialIndex,
          recentlyDeletedRepository: widget.recentlyDeletedRepository,
        ),
      ),
    );
    if (mounted) {
      await _loadMedia(isRefresh: true);
    }
  }

  Future<void> _handleMediaTap(MediaItem item) async {
    if (_isApplyingSelectionAction) {
      return;
    }

    if (_selectionController.isSelectionMode) {
      _selectionController.toggleSelection(item.id);
      return;
    }

    await _openHomeMediaViewer(item);
  }

  void _handleMediaLongPress(MediaItem item) {
    if (_isApplyingSelectionAction) {
      return;
    }

    if (!_selectionController.isSelectionMode) {
      _selectionController.startSelection(item.id);
      return;
    }

    _selectionController.toggleSelection(item.id);
  }

  Set<String> _selectedMediaIds() {
    return _selectionController.selectedIds.toSet();
  }

  List<AssetEntity> _selectedAssetEntities() {
    final Set<String> selectedIds = _selectedMediaIds();
    if (selectedIds.isEmpty) {
      return const <AssetEntity>[];
    }

    final List<AssetEntity> assets = <AssetEntity>[];
    for (final MediaItem item in _mediaItems) {
      if (!selectedIds.contains(item.id)) {
        continue;
      }

      final ThumbnailRef thumbnail = item.thumbnail;
      if (thumbnail is AssetEntityThumbnailRef) {
        assets.add(thumbnail.asset);
      }
    }
    return assets;
  }

  Future<void> _favoriteSelected() async {
    if (_isApplyingSelectionAction) {
      return;
    }

    final List<AssetEntity> selectedAssets = _selectedAssetEntities();
    if (selectedAssets.isEmpty) {
      _selectionController.clear();
      return;
    }

    setState(() {
      _isApplyingSelectionAction = true;
    });

    try {
      for (final AssetEntity asset in selectedAssets) {
        if (Platform.isAndroid) {
          await PhotoManager.editor.android.favoriteAsset(
            entity: asset,
            favorite: true,
          );
        } else if (Platform.isIOS || Platform.isMacOS) {
          await PhotoManager.editor.darwin.favoriteAsset(
            entity: asset,
            favorite: true,
          );
        }
      }

      _selectionController.clear();
      await _loadMedia(isRefresh: true);

      if (!mounted) {
        return;
      }

      AppToast.show(context, '${selectedAssets.length} item(s) favorited');
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingSelectionAction = false;
        });
      }
    }
  }

  Future<void> _trashSelected() async {
    if (_isApplyingSelectionAction) {
      return;
    }

    final Set<String> selectedIds = _selectedMediaIds();
    if (selectedIds.isEmpty) {
      _selectionController.clear();
      return;
    }

    setState(() {
      _isApplyingSelectionAction = true;
    });

    try {
      await widget.recentlyDeletedRepository.markDeleted(selectedIds);

      _selectionController.clear();
      await _loadMedia(isRefresh: true);

      if (!mounted) {
        return;
      }

      AppToast.show(context, '${selectedIds.length} item(s) moved to trash');
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingSelectionAction = false;
        });
      }
    }
  }

  Future<void> _addSelectedToAlbum() async {
    if (_isApplyingSelectionAction) {
      return;
    }

    final Set<String> selectedIds = _selectedMediaIds();
    if (selectedIds.isEmpty) {
      return;
    }

    final List<AppAlbum> albums = await widget.appAlbumRepository.listAlbums();
    if (!mounted) {
      return;
    }

    if (albums.isEmpty) {
      AppToast.show(context, 'Create an album first from Albums tab.');
      return;
    }

    final AppAlbum? selectedAlbum = await showModalBottomSheet<AppAlbum>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          top: false,
          child: ListView.builder(
            itemCount: albums.length,
            itemBuilder: (BuildContext context, int index) {
              final AppAlbum album = albums[index];
              return ListTile(
                title: Text(album.name),
                subtitle: Text('${album.mediaIds.length} item(s)'),
                onTap: () => Navigator.of(context).pop(album),
              );
            },
          ),
        );
      },
    );

    if (selectedAlbum == null) {
      return;
    }

    setState(() {
      _isApplyingSelectionAction = true;
    });

    try {
      await widget.appAlbumRepository.addMediaToAlbum(
        selectedAlbum.id,
        selectedIds,
      );
      _selectionController.clear();
      if (!mounted) {
        return;
      }

      AppToast.show(
        context,
        '${selectedIds.length} item(s) added to ${selectedAlbum.name}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingSelectionAction = false;
        });
      }
    }
  }

  Future<void> _shareSelected() async {
    if (_isApplyingSelectionAction) {
      return;
    }

    final Set<String> selectedIds = _selectedMediaIds();
    if (selectedIds.isEmpty) {
      _selectionController.clear();
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

  Future<void> _cloudSyncSelected() async {
    if (_isApplyingSelectionAction || _isCloudSyncing) {
      return;
    }

    final Set<String> selectedIds = _selectedMediaIds();
    if (selectedIds.isEmpty) {
      return;
    }

    setState(() {
      _isCloudSyncing = true;
      _cloudSyncTotal = selectedIds.length;
      _cloudSyncCompleted = 0;
      _cloudSyncPhase = 'Preparing';
      _cloudSyncCurrentProgress = 0;
    });

    try {
      await widget.cloudSyncService.sync(
        selectedIds,
        onProgress: (CloudSyncBatchProgress progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _cloudSyncTotal = progress.total;
            _cloudSyncCompleted = progress.completed;
            _cloudSyncPhase = progress.currentPhase;
            _cloudSyncCurrentProgress = progress.currentItemProgress;
          });
        },
      );
      if (!mounted) {
        return;
      }
      _selectionController.clear();
      final Map<String, CloudSyncRecord> status = await widget
          .cloudSyncRepository
          .getForIds(selectedIds);
      if (!mounted) {
        return;
      }
      final int failedCount = status.values
          .where(
            (CloudSyncRecord record) => record.status == CloudSyncStatus.failed,
          )
          .length;
      if (failedCount > 0) {
        AppToast.show(
          context,
          'Synced ${selectedIds.length - failedCount}/${selectedIds.length}, $failedCount failed',
        );
      } else {
        AppToast.show(
          context,
          'Cloud sync completed for ${selectedIds.length} item(s).',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCloudSyncing = false;
          _cloudSyncPhase = null;
          _cloudSyncCurrentProgress = 0;
        });
      }
    }
  }

  Future<void> _removeFromCloudSelected() async {
    if (_isApplyingSelectionAction || _isCloudSyncing) {
      return;
    }
    final Set<String> selectedIds = _selectedMediaIds();
    if (selectedIds.isEmpty) {
      return;
    }
    await widget.cloudSyncService.removeFromCloud(selectedIds);
    if (!mounted) {
      return;
    }
    _selectionController.clear();
    AppToast.show(context, '${selectedIds.length} item(s) marked unsynced');
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelectionMode = _selectionController.isSelectionMode;

    return Scaffold(
      appBar: _buildAppBar(context),
      bottomNavigationBar: isSelectionMode
          ? _HomeSelectionActionBar(
              key: const Key('home-selection-action-bar'),
              isBusy: _isApplyingSelectionAction || _isCloudSyncing,
              onFavoritePressed: _favoriteSelected,
              onAddToAlbumPressed: _addSelectedToAlbum,
              onSharePressed: _shareSelected,
              onCloudSyncPressed: _cloudSyncSelected,
              onRemoveCloudPressed: _removeFromCloudSelected,
              onTrashPressed: _trashSelected,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _loadMedia(isRefresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            if (_isCloudSyncing) _buildCloudSyncProgressSliver(context),
            ..._buildBodySlivers(context),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final bool isSelectionMode = _selectionController.isSelectionMode;
    if (!isSelectionMode) {
      return AppTopBar(
        title: 'nimbus',
        onMenuPressed: _toggleGridDensity,
        leadingTooltip: _gridDensityController.density == HomeGridDensity.three
            ? 'Switch to 5-column grid'
            : 'Switch to 3-column grid',
        leadingIcon: Iconify(
          _gridDensityController.density == HomeGridDensity.three
              ? Ion.grid
              : Ion.grid_outline,
          color: AppColors.textPrimary,
          size: 22,
        ),
      );
    }

    return AppBar(
      title: Text('${_selectionController.selectedCount} selected'),
      actions: <Widget>[
        TextButton(
          key: const Key('home-cancel-selection'),
          onPressed: _isApplyingSelectionAction
              ? null
              : _selectionController.clear,
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildCloudSyncProgressSliver(BuildContext context) {
    final double aggregate = _cloudSyncTotal == 0
        ? 0
        : (_cloudSyncCompleted + _cloudSyncCurrentProgress) / _cloudSyncTotal;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Encrypting and uploading $_cloudSyncCompleted/$_cloudSyncTotal',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_cloudSyncPhase != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _cloudSyncPhase!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: aggregate.clamp(0, 1),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBodySlivers(BuildContext context) {
    if (_isLoading) {
      return const <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (_permissionDenied) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Allow gallery access to show photos and videos.',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: PhotoManager.openSetting,
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    if (_errorMessage != null) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ];
    }

    if (_groups.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'No photos or videos found on this device.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ];
    }

    int imageCount = 0;
    int videoCount = 0;
    for (final MediaItem item in _mediaItems) {
      if (item.type == MediaType.video) {
        videoCount += 1;
      } else {
        imageCount += 1;
      }
    }

    final List<Widget> slivers = <Widget>[];
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Center(
            child: Text(
              '$imageCount images, $videoCount videos',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );

    for (final MediaDayGroup group in _groups) {
      final String headerKey =
          '${group.day.year}-${group.day.month}-${group.day.day}';
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
            child: Text(
              group.dayLabel,
              key: Key('day-header-$headerKey'),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _gridDensityController.crossAxisCount,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate((BuildContext context, int i) {
              return _MediaTile(
                key: Key('media-tile-${group.items[i].id}'),
                item: group.items[i],
                syncRecord: _syncRecordsById[group.items[i].id],
                isSelected: _selectionController.isSelected(group.items[i].id),
                onTap: () => _handleMediaTap(group.items[i]),
                onLongPress: () => _handleMediaLongPress(group.items[i]),
              );
            }, childCount: group.items.length),
          ),
        ),
      );
    }

    return slivers;
  }
}

class _HomeSelectionActionBar extends StatelessWidget {
  const _HomeSelectionActionBar({
    super.key,
    required this.isBusy,
    required this.onFavoritePressed,
    required this.onAddToAlbumPressed,
    required this.onSharePressed,
    required this.onCloudSyncPressed,
    required this.onRemoveCloudPressed,
    required this.onTrashPressed,
  });

  final bool isBusy;
  final Future<void> Function() onFavoritePressed;
  final Future<void> Function() onAddToAlbumPressed;
  final Future<void> Function() onSharePressed;
  final Future<void> Function() onCloudSyncPressed;
  final Future<void> Function() onRemoveCloudPressed;
  final Future<void> Function() onTrashPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 2),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: SelectionActionButton(
                key: const Key('home-action-favorite'),
                label: 'Favorite',
                icon: Ion.heart_outline,
                enabled: !isBusy,
                onPressed: onFavoritePressed,
              ),
            ),
            Expanded(
              child: SelectionActionButton(
                key: const Key('home-action-add-to-album'),
                label: 'Add to Album',
                icon: Ion.albums_outline,
                enabled: !isBusy,
                onPressed: onAddToAlbumPressed,
              ),
            ),
            Expanded(
              child: SelectionActionButton(
                key: const Key('home-action-share'),
                label: 'Share',
                icon: Ion.share_social,
                enabled: !isBusy,
                onPressed: onSharePressed,
              ),
            ),
            Expanded(
              child: SelectionActionButton(
                key: const Key('home-action-cloud-sync'),
                label: 'Cloud Sync',
                icon: Ion.cloud_upload_outline,
                enabled: !isBusy,
                onPressed: onCloudSyncPressed,
              ),
            ),
            Expanded(
              child: SelectionActionButton(
                key: const Key('home-action-remove-cloud'),
                label: 'Remove Cloud',
                icon: Ion.cloud_offline_outline,
                enabled: !isBusy,
                onPressed: onRemoveCloudPressed,
              ),
            ),
            Expanded(
              child: SelectionActionButton(
                key: const Key('home-action-trash'),
                label: 'Trash',
                icon: Ion.trash_outline,
                enabled: !isBusy,
                onPressed: onTrashPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    super.key,
    required this.item,
    required this.syncRecord,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaItem item;
  final CloudSyncRecord? syncRecord;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _buildThumbnail(),
          if (item.type == MediaType.video)
            Center(
              child: Iconify(
                key: Key('video-indicator-${item.id}'),
                Ion.play_circle,
                color: Colors.white70,
                size: 36,
              ),
            ),
          Positioned(
            left: 6,
            bottom: 6,
            child: KeyedSubtree(
              key: Key('sync-indicator-${item.id}'),
              child: CloudSyncBadge(record: syncRecord),
            ),
          ),
          AnimatedOpacity(
            opacity: isSelected ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Container(
              color: const Color(0x66000000),
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.all(6),
              child: const Iconify(
                Ion.checkmark_circle,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    final ThumbnailRef thumbnail = item.thumbnail;
    if (thumbnail is PlaceholderThumbnailRef) {
      return ColoredBox(color: thumbnail.color);
    }

    if (thumbnail is AssetEntityThumbnailRef) {
      return FutureBuilder<Uint8List?>(
        future: thumbnail.asset.thumbnailDataWithSize(
          const ThumbnailSize.square(360),
          quality: 85,
        ),
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            );
          }
          return const ColoredBox(color: AppColors.surfaceVariant);
        },
      );
    }

    return const ColoredBox(color: AppColors.surfaceVariant);
  }
}
