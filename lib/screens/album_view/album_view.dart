import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ion.dart';
import 'package:intl/intl.dart';
import 'package:nimbus/core/media/media_item.dart';
import 'package:nimbus/core/media/media_repository.dart';
import 'package:nimbus/core/media/photo_repository.dart';
import 'package:nimbus/core/media/thumbnail_ref.dart';
import 'package:nimbus/models/app_album.dart';
import 'package:nimbus/models/sync_record.dart';
import 'package:nimbus/models/device_album.dart';
import 'package:nimbus/screens/album_view/media_item.dart';
import 'package:nimbus/screens/home/grid_density.dart';
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
import 'package:nimbus/widgets/toast.dart';
import 'package:nimbus/widgets/action_button.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

class AlbumViewScreen extends StatefulWidget {
  AlbumViewScreen._({
    super.key,
    this.deviceAlbum,
    this.appAlbum,
    required this.isDeviceAlbum,
    MediaRepository? mediaRepository,
    AppAlbumRepository? appAlbumRepository,
    RecentlyDeletedRepository? recentlyDeletedRepository,
    CloudSyncRepository? cloudSyncRepository,
    MockCloudSyncService? cloudSyncService,
  }) : mediaRepository = mediaRepository ?? PhotoManagerMediaRepository(),
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

  factory AlbumViewScreen.device({
    Key? key,
    required DeviceAlbum album,
    MediaRepository? mediaRepository,
    AppAlbumRepository? appAlbumRepository,
    RecentlyDeletedRepository? recentlyDeletedRepository,
    CloudSyncRepository? cloudSyncRepository,
    MockCloudSyncService? cloudSyncService,
  }) {
    return AlbumViewScreen._(
      key: key,
      deviceAlbum: album,
      isDeviceAlbum: true,
      mediaRepository: mediaRepository,
      appAlbumRepository: appAlbumRepository,
      recentlyDeletedRepository: recentlyDeletedRepository,
      cloudSyncRepository: cloudSyncRepository,
      cloudSyncService: cloudSyncService,
    );
  }

  factory AlbumViewScreen.app({
    Key? key,
    required AppAlbum album,
    MediaRepository? mediaRepository,
    AppAlbumRepository? appAlbumRepository,
    RecentlyDeletedRepository? recentlyDeletedRepository,
    CloudSyncRepository? cloudSyncRepository,
    MockCloudSyncService? cloudSyncService,
  }) {
    return AlbumViewScreen._(
      key: key,
      appAlbum: album,
      isDeviceAlbum: false,
      mediaRepository: mediaRepository,
      appAlbumRepository: appAlbumRepository,
      recentlyDeletedRepository: recentlyDeletedRepository,
      cloudSyncRepository: cloudSyncRepository,
      cloudSyncService: cloudSyncService,
    );
  }

  final DeviceAlbum? deviceAlbum;
  final AppAlbum? appAlbum;
  final bool isDeviceAlbum;
  final MediaRepository mediaRepository;
  final AppAlbumRepository appAlbumRepository;
  final RecentlyDeletedRepository recentlyDeletedRepository;
  final CloudSyncRepository cloudSyncRepository;
  final MockCloudSyncService cloudSyncService;

  @override
  State<AlbumViewScreen> createState() => _AlbumViewScreenState();
}

class _AlbumViewScreenState extends State<AlbumViewScreen>
    with WidgetsBindingObserver {
  late final HomeGridDensityController _gridDensityController;
  List<AlbumViewMediaItem> _items = const <AlbumViewMediaItem>[];
  Set<String> _selectedItemIds = <String>{};
  bool _isLoading = true;
  bool _isApplyingSelectionAction = false;
  bool _isCloudSyncing = false;
  int _cloudSyncTotal = 0;
  int _cloudSyncCompleted = 0;
  String? _cloudSyncPhase;
  double _cloudSyncCurrentProgress = 0;
  String? _errorMessage;
  AppAlbum? _appAlbumState;
  Map<String, CloudSyncRecord> _syncRecordsById =
      const <String, CloudSyncRecord>{};
  StreamSubscription<Map<String, CloudSyncRecord>>? _syncSubscription;
  StreamSubscription<Set<String>>? _deletedSubscription;
  final DateFormat _dayLabelFormatter = DateFormat('d MMM', 'en_US');
  final DateFormat _monthLabelFormatter = DateFormat('MMM yyyy', 'en_US');

  bool get _isSelectionMode => _selectedItemIds.isNotEmpty;

  String get _title {
    if (widget.isDeviceAlbum) {
      return widget.deviceAlbum?.name ?? 'Album';
    }
    return _appAlbumState?.name ?? widget.appAlbum?.name ?? 'Album';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
          _loadMedia();
        });
    _loadMedia();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      _loadMedia();
    }
  }

  void _handleGridDensityChanged() {
    setState(() {});
  }

  void _toggleGridDensity() {
    _gridDensityController.toggle();
  }

  void _clearSelection() {
    if (_selectedItemIds.isEmpty) {
      return;
    }
    setState(() {
      _selectedItemIds = <String>{};
    });
  }

  void _toggleItemSelection(String itemId) {
    final Set<String> next = <String>{..._selectedItemIds};
    if (next.contains(itemId)) {
      next.remove(itemId);
    } else {
      next.add(itemId);
    }
    setState(() {
      _selectedItemIds = next;
    });
  }

  Future<void> _renameAppAlbum() async {
    if (widget.isDeviceAlbum) {
      return;
    }

    final AppAlbum? album = _appAlbumState ?? widget.appAlbum;
    if (album == null) {
      return;
    }

    String draftName = album.name;
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rename Album'),
          content: TextFormField(
            autofocus: true,
            initialValue: draftName,
            textInputAction: TextInputAction.done,
            onChanged: (String value) {
              draftName = value;
            },
            onFieldSubmitted: (_) =>
                Navigator.of(context).pop(draftName.trim()),
            decoration: const InputDecoration(hintText: 'Album name'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(draftName.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (input == null || !mounted) {
      return;
    }

    final String nextName = input.trim();
    if (nextName.isEmpty) {
      AppToast.show(context, 'Album name cannot be empty.');
      return;
    }

    try {
      await widget.appAlbumRepository.renameAlbum(album.id, nextName);
      final AppAlbum? refreshed = await widget.appAlbumRepository.getById(
        album.id,
      );
      if (!mounted) {
        return;
      }
      if (refreshed != null) {
        setState(() {
          _appAlbumState = refreshed;
        });
      }
    } on DuplicateAlbumNameException {
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'Album name already exists.');
    } on FormatException {
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'Album name cannot be empty.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'Could not rename album.');
    }
  }

  Future<void> _showAppAlbumEditOptions() async {
    if (widget.isDeviceAlbum) {
      return;
    }
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Iconify(Ion.edit, size: 18),
                title: const Text('Rename Album'),
                onTap: () => Navigator.of(context).pop('rename'),
              ),
              ListTile(
                leading: const Iconify(Ion.image_outline, size: 18),
                title: const Text('Set Album Preview'),
                onTap: () => Navigator.of(context).pop('cover'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'rename') {
      await _renameAppAlbum();
      return;
    }
    if (action == 'cover') {
      await _setAlbumPreview();
    }
  }

  Future<void> _setAlbumPreview() async {
    if (widget.isDeviceAlbum) {
      return;
    }
    final String? albumId = _appAlbumState?.id ?? widget.appAlbum?.id;
    if (albumId == null) {
      return;
    }

    final List<AlbumViewMediaItem> previewCandidates = _items
        .where((AlbumViewMediaItem item) => !item.isVideo)
        .toList(growable: false);
    if (previewCandidates.isEmpty) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'No images available to set as preview.');
      return;
    }

    final AlbumViewMediaItem? selected =
        await showModalBottomSheet<AlbumViewMediaItem>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: previewCandidates.length,
                  itemBuilder: (BuildContext context, int index) {
                    final AlbumViewMediaItem item = previewCandidates[index];
                    return _AlbumViewTile(
                      item: item,
                      onTap: () => Navigator.of(context).pop(item),
                    );
                  },
                ),
              ),
            );
          },
        );

    if (selected == null || !mounted) {
      return;
    }

    if (selected.source == AlbumViewMediaSource.asset) {
      await widget.appAlbumRepository.setAlbumCover(
        albumId,
        mediaId: selected.assetItem?.id,
      );
    } else {
      await widget.appAlbumRepository.setAlbumCover(
        albumId,
        localPath: selected.localFilePath,
      );
    }
    final AppAlbum? refreshed = await widget.appAlbumRepository.getById(
      albumId,
    );
    if (!mounted) {
      return;
    }
    if (refreshed != null) {
      setState(() {
        _appAlbumState = refreshed;
      });
    }
    AppToast.show(context, 'Album preview updated');
  }

  Future<void> _loadMedia() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      List<AlbumViewMediaItem> items;
      final Set<String> deletedIds = await widget.recentlyDeletedRepository
          .listDeletedIds();
      if (widget.isDeviceAlbum) {
        final DeviceAlbum? album = widget.deviceAlbum;
        if (album == null) {
          setState(() {
            _isLoading = false;
            _items = const <AlbumViewMediaItem>[];
            _errorMessage = 'Album not found.';
          });
          return;
        }

        final MediaPermissionStatus permissionStatus = await widget
            .mediaRepository
            .requestPermission();
        if (permissionStatus == MediaPermissionStatus.denied) {
          setState(() {
            _isLoading = false;
            _items = const <AlbumViewMediaItem>[];
            _errorMessage = 'Allow gallery permission to view this album.';
          });
          return;
        }

        final List<MediaItem> albumMedia = await widget.mediaRepository
            .fetchMediaForDeviceAlbum(album.id);
        items = albumMedia
            .where((MediaItem item) => !deletedIds.contains(item.id))
            .map(AlbumViewMediaItem.asset)
            .toList(growable: false);
      } else {
        final String? albumId = widget.appAlbum?.id;
        if (albumId == null) {
          setState(() {
            _isLoading = false;
            _items = const <AlbumViewMediaItem>[];
            _errorMessage = 'Album not found.';
          });
          return;
        }

        final AppAlbum? album = await widget.appAlbumRepository.getById(
          albumId,
        );
        if (album == null) {
          setState(() {
            _isLoading = false;
            _items = const <AlbumViewMediaItem>[];
            _errorMessage = 'Album not found.';
          });
          return;
        }
        _appAlbumState = album;

        final List<MediaItem> assetMedia = await widget.mediaRepository
            .fetchMediaByIds(album.mediaIds);
        final List<AlbumViewMediaItem> merged = assetMedia
            .where((MediaItem item) => !deletedIds.contains(item.id))
            .map(AlbumViewMediaItem.asset)
            .toList(growable: true);

        for (final String localPath in album.localMediaPaths) {
          final File file = File(localPath);
          if (!await file.exists()) {
            continue;
          }
          final FileStat stat = await file.stat();
          merged.add(
            AlbumViewMediaItem.localFile(
              id: localPath,
              path: localPath,
              isVideo: _isVideoPath(localPath),
              createdAt: stat.modified.toLocal(),
            ),
          );
        }

        merged.sort(
          (AlbumViewMediaItem a, AlbumViewMediaItem b) =>
              b.createdAt.compareTo(a.createdAt),
        );
        items = merged;
      }

      final Set<String> itemIds = items
          .where((AlbumViewMediaItem item) => item.id.isNotEmpty)
          .map((AlbumViewMediaItem item) => item.id)
          .toSet();
      final Map<String, CloudSyncRecord> syncRecords = await widget
          .cloudSyncRepository
          .getForIds(itemIds);

      setState(() {
        _isLoading = false;
        _items = items;
        _syncRecordsById = <String, CloudSyncRecord>{
          ..._syncRecordsById,
          ...syncRecords,
        };
        final Set<String> validIds = items
            .map((AlbumViewMediaItem item) => item.id)
            .toSet();
        _selectedItemIds = _selectedItemIds.intersection(validIds);
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _items = const <AlbumViewMediaItem>[];
        _errorMessage = 'Could not load this album.';
      });
    }
  }

  bool _isVideoPath(String path) {
    const Set<String> videoExtensions = <String>{
      '.mp4',
      '.mov',
      '.mkv',
      '.webm',
      '.avi',
      '.3gp',
      '.m4v',
    };
    return videoExtensions.contains(p.extension(path).toLowerCase());
  }

  String _normalizePath(String path) {
    return p.normalize(path).replaceAll('\\', '/').toLowerCase();
  }

  Future<void> _removeSelectedFromAlbum() async {
    if (widget.isDeviceAlbum ||
        _selectedItemIds.isEmpty ||
        _isApplyingSelectionAction) {
      return;
    }

    final String? albumId = _appAlbumState?.id ?? widget.appAlbum?.id;
    if (albumId == null) {
      return;
    }

    setState(() {
      _isApplyingSelectionAction = true;
    });

    try {
      final List<AlbumViewMediaItem> selectedItems = _items
          .where(
            (AlbumViewMediaItem item) => _selectedItemIds.contains(item.id),
          )
          .toList(growable: false);

      final Set<String> mediaIds = <String>{};
      final Set<String> localPaths = <String>{};

      for (final AlbumViewMediaItem item in selectedItems) {
        if (item.source == AlbumViewMediaSource.asset) {
          final String? mediaId = item.assetItem?.id;
          if (mediaId != null) {
            mediaIds.add(mediaId);
          }
        } else {
          final String? localPath = item.localFilePath;
          if (localPath != null) {
            localPaths.add(localPath);
            final File file = File(localPath);
            if (await file.exists()) {
              await file.delete();
            }
          }
        }
      }

      await widget.appAlbumRepository.removeMediaFromAlbum(
        albumId,
        mediaIds: mediaIds,
        localPaths: localPaths,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _items = _items
            .where(
              (AlbumViewMediaItem item) => !_selectedItemIds.contains(item.id),
            )
            .toList(growable: false);
        _selectedItemIds = <String>{};
      });

      AppToast.show(context, '${selectedItems.length} item(s) removed');
    } catch (_) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'Could not remove selected items.');
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingSelectionAction = false;
        });
      }
    }
  }

  Future<List<AssetEntity>> _selectedAssetEntities() async {
    final List<AssetEntity> assets = <AssetEntity>[];
    for (final AlbumViewMediaItem item in _items) {
      if (!_selectedItemIds.contains(item.id) ||
          item.source != AlbumViewMediaSource.asset) {
        continue;
      }

      final MediaItem? assetItem = item.assetItem;
      if (assetItem == null) {
        continue;
      }
      final ThumbnailRef thumbnail = assetItem.thumbnail;
      if (thumbnail is AssetEntityThumbnailRef) {
        assets.add(thumbnail.asset);
      }
    }
    return assets;
  }

  Future<void> _favoriteSelected() async {
    if (_isApplyingSelectionAction || _selectedItemIds.isEmpty) {
      return;
    }

    setState(() {
      _isApplyingSelectionAction = true;
    });

    try {
      final List<AssetEntity> selectedAssets = await _selectedAssetEntities();
      if (selectedAssets.isEmpty) {
        _clearSelection();
        return;
      }

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

      _clearSelection();
      await _loadMedia();
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

  Future<void> _shareSelected() async {
    if (_isApplyingSelectionAction || _selectedItemIds.isEmpty) {
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
    if (_selectedItemIds.isEmpty || !mounted || _isCloudSyncing) {
      return;
    }

    final Set<String> selectedIds = _selectedItemIds.toSet();
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
      _clearSelection();
      AppToast.show(
        context,
        failedCount > 0
            ? 'Synced ${selectedIds.length - failedCount}/${selectedIds.length}, $failedCount failed'
            : 'Cloud sync completed for ${selectedIds.length} item(s).',
      );
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

  Future<void> _removeCloudSelected() async {
    if (_selectedItemIds.isEmpty || !mounted || _isCloudSyncing) {
      return;
    }
    final Set<String> selectedIds = _selectedItemIds.toSet();
    await widget.cloudSyncService.removeFromCloud(selectedIds);
    if (!mounted) {
      return;
    }
    _clearSelection();
    AppToast.show(context, '${selectedIds.length} item(s) marked unsynced');
  }

  Future<void> _addSelectedToAlbum() async {
    if (_isApplyingSelectionAction || _selectedItemIds.isEmpty) {
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
    if (!mounted) {
      return;
    }

    final Set<String> selectedAssetIds = <String>{};
    for (final AlbumViewMediaItem item in _items) {
      if (!_selectedItemIds.contains(item.id) ||
          item.source != AlbumViewMediaSource.asset) {
        continue;
      }
      final String? id = item.assetItem?.id;
      if (id != null) {
        selectedAssetIds.add(id);
      }
    }

    if (selectedAssetIds.isEmpty) {
      AppToast.show(context, 'Only device media can be added by reference.');
      return;
    }

    setState(() {
      _isApplyingSelectionAction = true;
    });
    try {
      await widget.appAlbumRepository.addMediaToAlbum(
        selectedAlbum.id,
        selectedAssetIds,
      );
      _clearSelection();
      if (!mounted) {
        return;
      }
      AppToast.show(
        context,
        '${selectedAssetIds.length} item(s) added to ${selectedAlbum.name}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingSelectionAction = false;
        });
      }
    }
  }

  Future<void> _trashSelected() async {
    if (_isApplyingSelectionAction || _selectedItemIds.isEmpty) {
      return;
    }

    setState(() {
      _isApplyingSelectionAction = true;
    });

    try {
      final List<AlbumViewMediaItem> selectedItems = _items
          .where(
            (AlbumViewMediaItem item) => _selectedItemIds.contains(item.id),
          )
          .toList(growable: false);

      final Set<String> localPaths = <String>{};
      final Set<String> mediaIds = <String>{};
      for (final AlbumViewMediaItem item in selectedItems) {
        if (item.source == AlbumViewMediaSource.localFile) {
          final String? path = item.localFilePath;
          if (path != null) {
            localPaths.add(path);
            final File file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          }
        } else {
          final String? id = item.assetItem?.id;
          if (id != null) {
            mediaIds.add(id);
          }
        }
      }
      if (mediaIds.isNotEmpty) {
        await widget.recentlyDeletedRepository.markDeleted(mediaIds);
      }

      if (!widget.isDeviceAlbum) {
        final String? albumId = _appAlbumState?.id ?? widget.appAlbum?.id;
        if (albumId != null) {
          await widget.appAlbumRepository.removeMediaFromAlbum(
            albumId,
            mediaIds: mediaIds,
            localPaths: localPaths,
          );
        }
      }

      _clearSelection();
      await _loadMedia();
      if (!mounted) {
        return;
      }
      AppToast.show(context, '${selectedItems.length} item(s) moved to trash');
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingSelectionAction = false;
        });
      }
    }
  }

  Future<void> _importMedia() async {
    if (widget.isDeviceAlbum) {
      return;
    }

    final AppAlbum? album = _appAlbumState ?? widget.appAlbum;
    if (album == null) {
      return;
    }

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
    );
    if (result == null) {
      return;
    }

    final List<MediaItem> allMedia = await widget.mediaRepository
        .fetchAllMedia();
    final Map<String, String> pathToMediaId = <String, String>{};
    for (final MediaItem mediaItem in allMedia) {
      final ThumbnailRef thumbnail = mediaItem.thumbnail;
      if (thumbnail is! AssetEntityThumbnailRef) {
        continue;
      }
      final File? file = await thumbnail.asset.file;
      if (file == null) {
        continue;
      }
      pathToMediaId[_normalizePath(file.path)] = mediaItem.id;
    }

    final Set<String> pickedMediaIds = <String>{};
    int skippedCount = 0;
    for (final String? sourcePath in result.paths) {
      if (sourcePath == null) {
        continue;
      }
      final String? mediaId = pathToMediaId[_normalizePath(sourcePath)];
      if (mediaId == null) {
        skippedCount += 1;
        continue;
      }
      pickedMediaIds.add(mediaId);
    }

    if (pickedMediaIds.isEmpty) {
      if (!mounted) {
        return;
      }
      AppToast.show(
        context,
        'No matching device media found to add by reference.',
      );
      return;
    }

    await widget.appAlbumRepository.addMediaToAlbum(album.id, pickedMediaIds);
    await _loadMedia();
    if (!mounted) {
      return;
    }
    AppToast.show(
      context,
      skippedCount == 0
          ? '${pickedMediaIds.length} item(s) added by reference'
          : '${pickedMediaIds.length} added by reference, $skippedCount skipped',
    );
  }

  MediaViewerItem _viewerItemFor(AlbumViewMediaItem item) {
    if (item.source == AlbumViewMediaSource.asset) {
      final MediaItem? assetItem = item.assetItem;
      if (assetItem != null) {
        return MediaViewerItem.asset(assetItem);
      }
    }
    return MediaViewerItem.localFile(
      path: item.localFilePath ?? item.id,
      isVideo: item.isVideo,
    );
  }

  Future<void> _openMediaAt(int index) async {
    final List<MediaViewerItem> viewerItems = _items
        .map(_viewerItemFor)
        .toList(growable: false);
    if (viewerItems.isEmpty) {
      return;
    }

    final MediaViewerItem tappedItem = viewerItems[index];
    if (!tappedItem.isVideo) {
      final List<MediaViewerItem> imageItems = viewerItems
          .where((MediaViewerItem item) => !item.isVideo)
          .toList(growable: false);
      final int imageIndex = imageItems.indexWhere(
        (MediaViewerItem item) => item.id == tappedItem.id,
      );
      if (imageIndex >= 0) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImageViewScreen.items(
              items: imageItems,
              initialIndex: imageIndex,
              isFromAppAlbum: !widget.isDeviceAlbum,
              appAlbumId: _appAlbumState?.id ?? widget.appAlbum?.id,
              appAlbumRepository: widget.appAlbumRepository,
              recentlyDeletedRepository: widget.recentlyDeletedRepository,
            ),
          ),
        );
        if (mounted) {
          await _loadMedia();
        }
        return;
      }
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaViewerScreen.items(
          items: viewerItems,
          initialIndex: index,
          isFromAppAlbum: !widget.isDeviceAlbum,
          appAlbumId: _appAlbumState?.id ?? widget.appAlbum?.id,
          appAlbumRepository: widget.appAlbumRepository,
          recentlyDeletedRepository: widget.recentlyDeletedRepository,
        ),
      ),
    );
    if (mounted) {
      await _loadMedia();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAppAlbum = !widget.isDeviceAlbum;
    final bool isSelectionMode = _isSelectionMode;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: isSelectionMode
              ? _clearSelection
              : () => Navigator.of(context).maybePop(),
          icon: const Iconify(Ion.arrow_back, color: Colors.white),
        ),
        title: Text(
          isSelectionMode ? '${_selectedItemIds.length} selected' : _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: isAppAlbum ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        actions: <Widget>[
          if (!isSelectionMode && isAppAlbum)
            IconButton(
              tooltip: 'Edit album',
              onPressed: _showAppAlbumEditOptions,
              icon: const Iconify(Ion.edit, color: Colors.white, size: 19),
            ),
          if (!isSelectionMode)
            IconButton(
              tooltip: _gridDensityController.density == HomeGridDensity.three
                  ? 'Switch to 5-column grid'
                  : 'Switch to 3-column grid',
              onPressed: _toggleGridDensity,
              icon: Iconify(
                _gridDensityController.density == HomeGridDensity.three
                    ? Ion.grid
                    : Ion.grid_outline,
                color: Colors.white,
                size: 19,
              ),
            ),
          if (isSelectionMode)
            TextButton(
              onPressed: _isApplyingSelectionAction ? null : _clearSelection,
              child: const Text('Cancel'),
            ),
        ],
      ),
      bottomNavigationBar: isSelectionMode
          ? _AlbumSelectionActionBar(
              key: const Key('album-selection-action-bar'),
              isBusy: _isApplyingSelectionAction || _isCloudSyncing,
              isAppAlbum: isAppAlbum,
              onFavoritePressed: _favoriteSelected,
              onAddToAlbumPressed: _addSelectedToAlbum,
              onSharePressed: _shareSelected,
              onCloudSyncPressed: _cloudSyncSelected,
              onRemoveCloudPressed: _removeCloudSelected,
              onTrashPressed: _trashSelected,
              onRemoveFromAlbumPressed: _removeSelectedFromAlbum,
            )
          : null,
      floatingActionButton: (widget.isDeviceAlbum || isSelectionMode)
          ? null
          : FloatingActionButton(
              onPressed: _importMedia,
              child: const Iconify(Ion.add),
            ),
      body: Column(
        children: <Widget>[
          if (_isCloudSyncing) _buildCloudSyncProgressHeader(context),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildCloudSyncProgressHeader(BuildContext context) {
    final double aggregate = _cloudSyncTotal == 0
        ? 0
        : (_cloudSyncCompleted + _cloudSyncCurrentProgress) / _cloudSyncTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
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
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
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
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }

    if (_items.isEmpty) {
      return const Center(child: Text('No media in this album'));
    }

    final List<_AlbumMediaGroup> groups = _groupItemsByDate(_items);
    final Map<String, int> indexById = <String, int>{};
    for (int i = 0; i < _items.length; i += 1) {
      indexById[_items[i].id] = i;
    }

    return CustomScrollView(
      slivers: <Widget>[
        for (final _AlbumMediaGroup group in groups) ...<Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Text(
                group.label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridDensityController.crossAxisCount,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int index,
              ) {
                final AlbumViewMediaItem item = group.items[index];
                final bool isSelected = _selectedItemIds.contains(item.id);
                final int? globalIndex = indexById[item.id];
                return _AlbumViewTile(
                  item: item,
                  syncRecord: _syncRecordsById[item.id],
                  isSelected: isSelected,
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleItemSelection(item.id);
                      return;
                    }
                    if (globalIndex != null) {
                      _openMediaAt(globalIndex);
                    }
                  },
                  onLongPress: () => _toggleItemSelection(item.id),
                );
              }, childCount: group.items.length),
            ),
          ),
        ],
      ],
    );
  }

  List<_AlbumMediaGroup> _groupItemsByDate(List<AlbumViewMediaItem> items) {
    final int currentYear = DateTime.now().year;
    final Map<DateTime, List<AlbumViewMediaItem>> grouped =
        <DateTime, List<AlbumViewMediaItem>>{};

    for (final AlbumViewMediaItem item in items) {
      final DateTime localDate = item.createdAt.toLocal();
      final bool shouldGroupByMonth = localDate.year < currentYear;
      final DateTime key = shouldGroupByMonth
          ? DateTime(localDate.year, localDate.month)
          : DateTime(localDate.year, localDate.month, localDate.day);
      grouped.putIfAbsent(key, () => <AlbumViewMediaItem>[]).add(item);
    }

    final List<DateTime> sortedKeys = grouped.keys.toList()
      ..sort((DateTime a, DateTime b) => b.compareTo(a));

    return sortedKeys
        .map((DateTime keyDate) {
          final List<AlbumViewMediaItem> groupItems = grouped[keyDate]!
            ..sort(
              (AlbumViewMediaItem a, AlbumViewMediaItem b) =>
                  b.createdAt.compareTo(a.createdAt),
            );
          final bool isMonthlyGroup = keyDate.year < currentYear;
          return _AlbumMediaGroup(
            key: keyDate,
            label: isMonthlyGroup
                ? _monthLabelFormatter.format(keyDate)
                : _dayLabelFormatter.format(keyDate),
            items: List<AlbumViewMediaItem>.unmodifiable(groupItems),
          );
        })
        .toList(growable: false);
  }
}

class _AlbumMediaGroup {
  const _AlbumMediaGroup({
    required this.key,
    required this.label,
    required this.items,
  });

  final DateTime key;
  final String label;
  final List<AlbumViewMediaItem> items;
}

class _AlbumSelectionActionBar extends StatelessWidget {
  const _AlbumSelectionActionBar({
    super.key,
    required this.isBusy,
    required this.isAppAlbum,
    required this.onFavoritePressed,
    required this.onAddToAlbumPressed,
    required this.onSharePressed,
    required this.onCloudSyncPressed,
    required this.onRemoveCloudPressed,
    required this.onTrashPressed,
    required this.onRemoveFromAlbumPressed,
  });

  final bool isBusy;
  final bool isAppAlbum;
  final Future<void> Function() onFavoritePressed;
  final Future<void> Function() onAddToAlbumPressed;
  final Future<void> Function() onSharePressed;
  final Future<void> Function() onCloudSyncPressed;
  final Future<void> Function() onRemoveCloudPressed;
  final Future<void> Function() onTrashPressed;
  final Future<void> Function() onRemoveFromAlbumPressed;

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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              SelectionActionButton(
                key: const Key('album-action-favorite'),
                label: 'Favorite',
                icon: Ion.heart_outline,
                enabled: !isBusy,
                onPressed: onFavoritePressed,
                width: 86,
              ),
              SelectionActionButton(
                key: const Key('album-action-add-to-album'),
                label: 'Add to Album',
                icon: Ion.albums_outline,
                enabled: !isBusy,
                onPressed: onAddToAlbumPressed,
                width: 86,
              ),
              SelectionActionButton(
                key: const Key('album-action-share'),
                label: 'Share',
                icon: Ion.share_social,
                enabled: !isBusy,
                onPressed: onSharePressed,
                width: 78,
              ),
              SelectionActionButton(
                key: const Key('album-action-cloud-sync'),
                label: 'Cloud Sync',
                icon: Ion.cloud_upload_outline,
                enabled: !isBusy,
                onPressed: onCloudSyncPressed,
                width: 86,
              ),
              SelectionActionButton(
                key: const Key('album-action-remove-cloud'),
                label: 'Remove Cloud',
                icon: Ion.cloud_offline_outline,
                enabled: !isBusy,
                onPressed: onRemoveCloudPressed,
                width: 92,
              ),
              SelectionActionButton(
                key: const Key('album-action-trash'),
                label: 'Trash',
                icon: Ion.trash_outline,
                enabled: !isBusy,
                onPressed: onTrashPressed,
                width: 78,
              ),
              if (isAppAlbum)
                SelectionActionButton(
                  key: const Key('album-action-remove'),
                  label: 'Remove from Album',
                  icon: Ion.md_remove_circle_outline,
                  enabled: !isBusy,
                  onPressed: onRemoveFromAlbumPressed,
                  width: 110,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumViewTile extends StatelessWidget {
  const _AlbumViewTile({
    required this.item,
    this.syncRecord,
    required this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  final AlbumViewMediaItem item;
  final CloudSyncRecord? syncRecord;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('album-view-tile-${item.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _buildPreview(),
          if (item.isVideo)
            const Center(
              child: Iconify(Ion.play_circle, color: Colors.white60, size: 34),
            ),
          if (item.isVideo)
            const Positioned(
              top: 6,
              right: 6,
              child: Iconify(Ion.videocam, color: Colors.white70, size: 14),
            ),
          Positioned(
            left: 6,
            bottom: 6,
            child: CloudSyncBadge(record: syncRecord),
          ),
          AnimatedOpacity(
            opacity: isSelected ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Container(
              color: const Color(0x66000000),
              alignment: Alignment.topRight,
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

  Widget _buildPreview() {
    if (item.source == AlbumViewMediaSource.localFile) {
      final String? path = item.localFilePath;
      if (path == null) {
        return const ColoredBox(color: AppColors.surfaceVariant);
      }
      if (item.isVideo) {
        return const ColoredBox(color: AppColors.surfaceVariant);
      }
      return Image.file(File(path), fit: BoxFit.cover);
    }

    final MediaItem? assetItem = item.assetItem;
    if (assetItem == null) {
      return const ColoredBox(color: AppColors.surfaceVariant);
    }
    final ThumbnailRef thumbnail = assetItem.thumbnail;
    if (thumbnail is AssetEntityThumbnailRef) {
      return FutureBuilder<Uint8List?>(
        future: thumbnail.asset.thumbnailDataWithSize(
          const ThumbnailSize.square(400),
          quality: 82,
        ),
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          }
          return const ColoredBox(color: AppColors.surfaceVariant);
        },
      );
    }
    return const ColoredBox(color: AppColors.surfaceVariant);
  }
}
