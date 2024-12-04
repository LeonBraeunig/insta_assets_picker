// ignore_for_file: implementation_imports

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:insta_assets_picker/insta_assets_picker.dart';
import 'package:insta_assets_picker/src/insta_assets_crop_controller.dart';
import 'package:insta_assets_picker/src/widget/crop_viewer.dart';
import 'package:provider/provider.dart';

import 'package:wechat_picker_library/wechat_picker_library.dart';

/// Die reduzierte Höhe der Crop-View bleibt konstant
const _kReducedCropViewHeight = kToolbarHeight;

/// Die Position der Crop-View bleibt konstant, wenn erweitert
const _kExtendedCropViewPosition = 0.0;

const _kIndicatorSize = 20.0;
const _kPathSelectorRowHeight = 50.0;
const _kActionsPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 8);

typedef InstaPickerActionsBuilder = List<Widget> Function(
  BuildContext context,
  ThemeData? pickerTheme,
  double height,
  VoidCallback unselectAll,
);

class InstaAssetPickerBuilder extends DefaultAssetPickerBuilderDelegate {
  InstaAssetPickerBuilder({
    required super.initialPermission,
    required super.provider,
    required this.onCompleted,
    required InstaAssetPickerConfig config,
    super.keepScrollOffset,
    super.locale,
  })  : _cropController =
            InstaAssetsCropController(keepScrollOffset, config.cropDelegate),
        title = config.title,
        closeOnComplete = config.closeOnComplete,
        skipCropOnComplete = config.skipCropOnComplete,
        actionsBuilder = config.actionsBuilder,
        super(
          gridCount: config.gridCount,
          pickerTheme: config.pickerTheme,
          specialItemPosition:
              config.specialItemPosition ?? SpecialItemPosition.none,
          specialItemBuilder: config.specialItemBuilder,
          loadingIndicatorBuilder: config.loadingIndicatorBuilder,
          selectPredicate: config.selectPredicate,
          limitedPermissionOverlayPredicate:
              config.limitedPermissionOverlayPredicate,
          themeColor: config.themeColor,
          textDelegate: config.textDelegate,
          gridThumbnailSize: config.gridThumbnailSize,
          previewThumbnailSize: config.previewThumbnailSize,
          pathNameBuilder: config.pathNameBuilder,
          shouldRevertGrid: false,
        );

  /// Der Texttitel in der Picker [AppBar].
  final String? title;

  /// Callback, der aufgerufen wird, wenn die Asset-Auswahl bestätigt wird.
  /// Es wird ein [Stream] mit Exportdetails [InstaAssetsExportDetails] als Argument übergeben.
  final Function(Stream<InstaAssetsExportDetails>) onCompleted;

  /// Das [Widget], das oben in der Assets-Grid-Ansicht angezeigt wird.
  /// Standard ist der Button zum Abwählen aller Assets.
  final InstaPickerActionsBuilder? actionsBuilder;

  /// Sollte der Picker geschlossen werden, wenn die Auswahl bestätigt wird
  ///
  /// Standardmäßig `false`, ähnlich wie bei Instagram
  final bool closeOnComplete;

  /// Sollte der Picker automatisch zuschneiden, wenn die Auswahl bestätigt wird
  ///
  /// Standardmäßig `false`.
  final bool skipCropOnComplete;

  // LOKALE PARAMETER

  /// Letzte Position des Grid-View-Scroll-Controllers speichern
  double _lastScrollOffset = 0.0;
  double _lastEndScrollOffset = 0.0;

  /// Scroll-Offset-Position zum Springen nach der Erweiterung der Crop-View
  double? _scrollTargetOffset;

  final ValueNotifier<double> _cropViewPosition = ValueNotifier<double>(0);
  final _cropViewerKey = GlobalKey<CropViewerState>();

  /// Controller, der den Zustand der Asset-Crop-Werte und der Exportation verwaltet
  final InstaAssetsCropController _cropController;

  /// Ob der Picker gemountet ist. Auf `false` setzen, wenn disposed.
  bool _mounted = true;

  @override
  void dispose() {
    _mounted = false;
    if (!keepScrollOffset) {
      _cropController.dispose();
      _cropViewPosition.dispose();
    }
    super.dispose();
  }

  /// Wird aufgerufen, wenn die Bestätigungs-[TextButton] angetippt wird
  void onConfirm(BuildContext context) {
    if (closeOnComplete) {
      Navigator.of(context).pop(provider.selectedAssets);
    }
    _cropViewerKey.currentState?.saveCurrentCropChanges();
    onCompleted(
      _cropController.exportCropFiles(
        provider.selectedAssets,
        skipCrop: skipCropOnComplete,
      ),
    );
  }

  /// Die responsive Höhe der Crop-View bleibt konstant
  double cropViewHeight(BuildContext context) => math.min(
        MediaQuery.of(context).size.width,
        MediaQuery.of(context).size.height * 0.5,
      );

  /// Gibt die Thumbnail-Position im Scroll-View zurück
  double indexPosition(BuildContext context, int index) {
    final row = (index / gridCount).floor();
    final size =
        (MediaQuery.of(context).size.width - itemSpacing * (gridCount - 1)) /
            gridCount;
    return row * size + (row * itemSpacing);
  }

  /// Crop-View immer erweitert halten (keine Animation)
  void _expandCropView([double? lockOffset]) {
    _scrollTargetOffset = lockOffset;
    _cropViewPosition.value = _kExtendedCropViewPosition;
  }

  /// Alle ausgewählten Assets abwählen
  void unSelectAll() {
    provider.selectedAssets = [];
    _cropController.clear();
  }

  /// Initialisiere [previewAsset] mit [p.selectedAssets], falls nicht leer,
  /// sonst das erste Element des Albums
  Future<void> _initializePreviewAsset(
    DefaultAssetPickerProvider p,
    bool shouldDisplayAssets,
  ) async {
    if (!_mounted || _cropController.previewAsset.value != null) return;

    if (p.selectedAssets.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_mounted) {
          _cropController.previewAsset.value = p.selectedAssets.last;
        }
      });
    }

    // Wenn Asset-Liste verfügbar und kein Asset ausgewählt ist,
    // zeige das erste Element der Liste
    if (shouldDisplayAssets && p.selectedAssets.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final list =
            await p.currentPath?.path.getAssetListRange(start: 0, end: 1);
        if (_mounted && (list?.isNotEmpty ?? false)) {
          _cropController.previewAsset.value = list!.first;
        }
      });
    }
  }

  /// Wird aufgerufen, wenn das Asset-Thumbnail angetippt wird
  @override
  Future<void> viewAsset(
    BuildContext context,
    int? index,
    AssetEntity currentAsset,
  ) async {
    if (index == null) {
      return;
    }
    if (_cropController.isCropViewReady.value != true) {
      return;
    }
    // Wenn es das Preview-Asset ist, wähle es ab
    if (provider.selectedAssets.isNotEmpty &&
        _cropController.previewAsset.value == currentAsset) {
      selectAsset(context, currentAsset, index, true);
      _cropController.previewAsset.value = provider.selectedAssets.isEmpty
          ? currentAsset
          : provider.selectedAssets.last;
      return;
    }

    _cropController.previewAsset.value = currentAsset;
    selectAsset(context, currentAsset, index, false);
  }

  /// Wird aufgerufen, wenn ein Asset ausgewählt wird
  @override
  Future<void> selectAsset(
    BuildContext context,
    AssetEntity asset,
    int index,
    bool selected,
  ) async {
    if (_cropController.isCropViewReady.value != true) {
      return;
    }

    final thumbnailPosition = indexPosition(context, index);
    final prevCount = provider.selectedAssets.length;
    await super.selectAsset(context, asset, index, selected);

    // Aktualisiere das Preview-Asset mit dem ausgewählten Asset
    final selectedAssets = provider.selectedAssets;
    if (prevCount < selectedAssets.length) {
      _cropController.previewAsset.value = asset;
    } else if (selected &&
        asset == _cropController.previewAsset.value &&
        selectedAssets.isNotEmpty) {
      _cropController.previewAsset.value = selectedAssets.last;
    }

    _expandCropView(thumbnailPosition);
  }

  /// Handle scroll on grid view to hide/expand the crop view
  /// **Diese Methode wird entfernt, um die Animation zu deaktivieren**
  /*
  bool _handleScroll(
    BuildContext context,
    ScrollNotification notification,
    double position,
    double reducedPosition,
  ) {
    final isScrollUp = gridScrollController.position.userScrollDirection ==
        ScrollDirection.reverse;
    final isScrollDown = gridScrollController.position.userScrollDirection ==
        ScrollDirection.forward;

    if (notification is ScrollEndNotification) {
      _lastEndScrollOffset = gridScrollController.offset;
      // reduce crop view
      if (position > reducedPosition && position < _kExtendedCropViewPosition) {
        _cropViewPosition.value = reducedPosition;
        return true;
      }
    }

    // expand crop view
    if (isScrollDown &&
        gridScrollController.offset <= 0 &&
        position < _kExtendedCropViewPosition) {
      // if scroll at edge, compute position based on scroll
      if (_lastScrollOffset > gridScrollController.offset) {
        _cropViewPosition.value -=
            (_lastScrollOffset.abs() - gridScrollController.offset.abs()) * 6;
      } else {
        // otherwise just expand it
        _expandCropView();
      }
    } else if (isScrollUp &&
        (gridScrollController.offset - _lastEndScrollOffset) *
                _kScrollMultiplier >
            cropViewHeight(context) - position &&
        position > reducedPosition) {
      // reduce crop view
      _cropViewPosition.value = cropViewHeight(context) -
          (gridScrollController.offset - _lastEndScrollOffset) *
              _kScrollMultiplier;
    }

    _lastScrollOffset = gridScrollController.offset;

    return true;
  }
  */

  /// Gibt einen Loader-[Widget] zurück, der in der Crop-View und statt des Bestätigungsbuttons angezeigt wird
  Widget _buildLoader(BuildContext context, double radius) {
    if (super.loadingIndicatorBuilder != null) {
      return super.loadingIndicatorBuilder!(context, provider.isAssetsEmpty);
    }
    return PlatformProgressIndicator(
      radius: radius,
      size: radius * 2,
      color: theme.iconTheme.color,
    );
  }

  /// Gibt den [TextButton] zurück, der die Albumliste öffnet
  @override
  Widget pathEntitySelector(BuildContext context) {
    Widget selector(BuildContext context) {
      return TextButton(
        style: TextButton.styleFrom(
          foregroundColor: theme.splashColor,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(4),
        ),
        onPressed: () {
          Feedback.forTap(context);
          isSwitchingPath.value = !isSwitchingPath.value;
        },
        child:
            Selector<DefaultAssetPickerProvider, PathWrapper<AssetPathEntity>?>(
          selector: (_, DefaultAssetPickerProvider p) => p.currentPath,
          builder: (_, PathWrapper<AssetPathEntity>? p, Widget? w) => Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (p != null)
                Flexible(
                  child: Text(
                    isPermissionLimited && p.path.isAll
                        ? textDelegate.accessiblePathName
                        : pathNameBuilder?.call(p.path) ?? p.path.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              w!,
            ],
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: isSwitchingPath,
            builder: (_, bool isSwitchingPath, Widget? w) => Transform.rotate(
              angle: isSwitchingPath ? math.pi : 0,
              child: w,
            ),
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: theme.iconTheme.color,
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider<DefaultAssetPickerProvider>.value(
      value: provider,
      builder: (BuildContext c, _) => selector(c),
    );
  }

  /// Gibt die Liste der Aktionen zurück, die oben in der Assets-Grid-Ansicht angezeigt werden
  Widget _buildActions(BuildContext context) {
    final double height = _kPathSelectorRowHeight - _kActionsPadding.vertical;
    final ThemeData? theme = pickerTheme?.copyWith(
      buttonTheme: const ButtonThemeData(padding: EdgeInsets.all(8)),
    );

    return SizedBox(
      height: _kPathSelectorRowHeight,
      width: MediaQuery.of(context).size.width,
      child: Padding(
        // Verringere das linke Padding, weil der Pfad-Selector-Button ein Padding hat
        padding: _kActionsPadding.copyWith(left: _kActionsPadding.left - 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            pathEntitySelector(context),
            actionsBuilder != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actionsBuilder!(
                      context,
                      theme,
                      height,
                      unSelectAll,
                    ),
                  )
                : InstaPickerCircleIconButton.unselectAll(
                    onTap: unSelectAll,
                    theme: theme,
                    size: height,
                  ),
          ],
        ),
      ),
    );
  }

  /// Gibt den oberen rechten Bestätigungs-[TextButton] zurück
  /// Ruft [onConfirm] auf
  @override
  Widget confirmButton(BuildContext context) {
    final Widget button = ValueListenableBuilder<bool>(
      valueListenable: _cropController.isCropViewReady,
      builder: (_, isLoaded, __) => Consumer<DefaultAssetPickerProvider>(
        builder: (_, DefaultAssetPickerProvider p, __) {
          return TextButton(
            style: pickerTheme?.textButtonTheme.style ??
                TextButton.styleFrom(
                  foregroundColor: themeColor,
                  disabledForegroundColor: theme.dividerColor,
                ),
            onPressed: isLoaded && p.isSelectedNotEmpty
                ? () => onConfirm(context)
                : null,
            child: isLoaded
                ? Text(
                    p.isSelectedNotEmpty && !isSingleAssetMode
                        ? '${textDelegate.confirm}'
                            ' (${p.selectedAssets.length}/${p.maxAssets})'
                        : textDelegate.confirm,
                  )
                : _buildLoader(context, 10),
          );
        },
      ),
    );
    return ChangeNotifierProvider<DefaultAssetPickerProvider>.value(
      value: provider,
      builder: (_, __) => button,
    );
  }

  /// Gibt die meisten Widgets des Layouts zurück, die App Bar, die Crop-View und die Grid-View
  @override
  Widget androidLayout(BuildContext context) {
    // Höhe der AppBar + CropView + Pfad-Selector-Zeile
    final topWidgetHeight = cropViewHeight(context) +
        kToolbarHeight +
        _kPathSelectorRowHeight +
        MediaQuery.of(context).padding.top;

    return ChangeNotifierProvider<DefaultAssetPickerProvider>.value(
      value: provider,
      builder: (context, _) => ValueListenableBuilder<double>(
          valueListenable: _cropViewPosition,
          builder: (context, position, child) {
            // Die obere Position, wenn die Crop-View reduziert ist
            final topReducedPosition = -(cropViewHeight(context) -
                _kReducedCropViewHeight +
                kToolbarHeight);
            // Position auf eine konstante erweiterte Position setzen
            position = _kExtendedCropViewPosition;
            // Höhe der Crop-View bleibt konstant
            final cropViewVisibleHeight = _kReducedCropViewHeight;
            // Opazität basierend auf einer konstanten Position festlegen
            final opacity = 1.0;

            final animationDuration = Duration.zero; // Keine Animation

            double gridHeight = MediaQuery.of(context).size.height -
                kToolbarHeight -
                _kReducedCropViewHeight;
            // Wenn keine Assets angezeigt werden, die genaue Höhe berechnen, um den Loader anzuzeigen
            if (!provider.hasAssetsToDisplay) {
              gridHeight -= cropViewHeight(context) - -_cropViewPosition.value;
            }
            final topPadding = topWidgetHeight + position;
            if (gridScrollController.hasClients &&
                _scrollTargetOffset != null) {
              gridScrollController.jumpTo(_scrollTargetOffset!);
            }
            _scrollTargetOffset = null;

            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: topPadding),
                  child: SizedBox(
                    height: gridHeight,
                    width: MediaQuery.of(context).size.width,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        // Scroll-Handling deaktivieren, da wir die Animation entfernen
                        // _handleScroll(context, notification, position, topReducedPosition);
                        return false;
                      },
                      child: _buildGrid(context),
                    ),
                  ),
                ),
                Positioned(
                  top: position,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    height: topWidgetHeight,
                    child: AssetPickerAppBarWrapper(
                      appBar: AssetPickerAppBar(
                        backgroundColor: theme.appBarTheme.backgroundColor,
                        title: title != null
                            ? Text(
                                title!,
                                style: theme.appBarTheme.titleTextStyle,
                              )
                            : null,
                        leading: backButton(context),
                        actions: <Widget>[confirmButton(context)],
                      ),
                      body: DecoratedBox(
                        decoration: BoxDecoration(
                          color: pickerTheme?.canvasColor,
                        ),
                        child: Column(
                          children: [
                            Listener(
                              onPointerDown: (_) {
                                _expandCropView();
                                // Scroll-Event stoppen
                                if (gridScrollController.hasClients) {
                                  gridScrollController
                                      .jumpTo(gridScrollController.offset);
                                }
                              },
                              child: CropViewer(
                                key: _cropViewerKey,
                                controller: _cropController,
                                textDelegate: textDelegate,
                                provider: provider,
                                opacity: opacity,
                                height: _kReducedCropViewHeight,
                                // Feste Höhe
                                // Center the loader in the visible viewport of the crop view
                                loaderWidget: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: SizedBox(
                                    height: cropViewVisibleHeight,
                                    child: Center(
                                      child: _buildLoader(context, 16),
                                    ),
                                  ),
                                ),
                                theme: pickerTheme,
                              ),
                            ),
                            _buildActions(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                pathEntityListBackdrop(context),
                _buildListAlbums(context),
              ],
            );
          }),
    );
  }

  /// Da das Layout auf allen Plattformen gleich ist, wird einfach [androidLayout] aufgerufen
  @override
  Widget appleOSLayout(BuildContext context) => androidLayout(context);

  /// Gibt die [ListView] zurück, die die Alben enthält
  Widget _buildListAlbums(context) {
    return Consumer<DefaultAssetPickerProvider>(
        builder: (BuildContext context, provider, __) {
      if (isAppleOS(context)) return pathEntityListWidget(context);

      // ANMERKUNG: Position auf Android fixieren, ziemlich hacky und könnte optimiert werden
      return ValueListenableBuilder<bool>(
        valueListenable: isSwitchingPath,
        builder: (_, bool isSwitchingPath, Widget? child) =>
            Transform.translate(
          offset: isSwitchingPath
              ? Offset(0, kToolbarHeight + MediaQuery.of(context).padding.top)
              : Offset.zero,
          child: Stack(
            children: [pathEntityListWidget(context)],
          ),
        ),
      );
    });
  }

  /// Gibt die [GridView] zurück, die die Assets anzeigt
  Widget _buildGrid(BuildContext context) {
    return Consumer<DefaultAssetPickerProvider>(
      builder: (BuildContext context, DefaultAssetPickerProvider p, __) {
        final bool shouldDisplayAssets =
            p.hasAssetsToDisplay || shouldBuildSpecialItem;
        _initializePreviewAsset(p, shouldDisplayAssets);

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: shouldDisplayAssets
              ? MediaQuery(
                  // Fix: https://github.com/fluttercandies/flutter_wechat_assets_picker/issues/395
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: -kToolbarHeight),
                  ),
                  child: RepaintBoundary(child: assetsGridBuilder(context)),
                )
              : loadingIndicator(context),
        );
      },
    );
  }

  /// Um ausgewählte Assets-Indikator und Preview-Asset-Overlay anzuzeigen
  @override
  Widget selectIndicator(BuildContext context, int index, AssetEntity asset) {
    final selectedAssets = provider.selectedAssets;
    final Duration duration = switchingPathDuration * 0.75;

    final int indexSelected = selectedAssets.indexOf(asset);
    final bool isSelected = indexSelected != -1;

    final Widget innerSelector = Container(
      // Entferne die Animation
      width: _kIndicatorSize,
      height: _kIndicatorSize,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.unselectedWidgetColor, width: 1),
        color: isSelected
            ? themeColor
            : theme.unselectedWidgetColor.withOpacity(.2),
        shape: BoxShape.circle,
      ),
      child: isSelected
          ? Text((indexSelected + 1).toString())
          : const SizedBox.shrink(),
    );

    return ValueListenableBuilder<AssetEntity?>(
      valueListenable: _cropController.previewAsset,
      builder: (context, previewAsset, child) {
        final bool isPreview = asset == _cropController.previewAsset.value;

        return Positioned.fill(
          child: GestureDetector(
            onTap: isPreviewEnabled
                ? () => viewAsset(context, index, asset)
                : null,
            child: Container(
              padding: const EdgeInsets.all(4),
              color: isPreview
                  ? theme.unselectedWidgetColor.withOpacity(.5)
                  : theme.colorScheme.surface.withOpacity(.1),
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: isSelected && !isSingleAssetMode
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            selectAsset(context, asset, index, isSelected),
                        child: innerSelector,
                      )
                    : innerSelector,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget selectedBackdrop(BuildContext context, int index, AssetEntity asset) =>
      const SizedBox.shrink();

  /// Deaktiviere den "Item Banned Indicator" im Single Mode (#26), sodass
  /// das neu ausgewählte Asset das alte ersetzt
  @override
  Widget itemBannedIndicator(BuildContext context, AssetEntity asset) =>
      isSingleAssetMode
          ? const SizedBox.shrink()
          : super.itemBannedIndicator(context, asset);
}
