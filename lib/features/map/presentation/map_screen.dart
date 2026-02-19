import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import 'package:horizon/core/log/app_log.dart';
import 'package:horizon/providers/map_provider.dart';
import 'package:horizon/providers/app_settings_provider.dart';
import 'package:horizon/providers/connectivity_provider.dart';
import 'package:horizon/providers/location_provider.dart';
import 'package:horizon/providers/weather_provider.dart';
import 'package:horizon/providers/routing_provider.dart';
import 'package:horizon/providers/offline_provider.dart';
import 'package:horizon/services/route_compare_service.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/explainability_engine.dart';
import 'package:horizon/ui/horizon_bottom_sheet.dart';
import 'package:horizon/ui/horizon_breakpoints.dart';
import 'package:horizon/ui/horizon_theme.dart';
import 'package:horizon/ui/horizon_card.dart';
import 'package:horizon/widgets/horizon_map.dart';

import 'package:horizon/features/map/presentation/utils/format_utils.dart';
import 'package:horizon/features/map/presentation/utils/glass_decoration.dart';
import 'package:horizon/features/map/presentation/widgets/weather_status_pill.dart';
import 'package:horizon/features/map/presentation/widgets/route_info_card.dart';
import 'package:horizon/features/map/presentation/widgets/route_chip.dart';
import 'package:horizon/features/map/presentation/widgets/offline_progress_bar.dart';
import 'package:horizon/features/map/presentation/widgets/geocoding_selection_sheet.dart';
import 'package:horizon/features/map/presentation/widgets/settings_sheet.dart';
import 'package:horizon/features/map/presentation/widgets/home_today_dashboard_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  ConnectivityProvider? _connectivity;
  VoidCallback? _connectivityListener;
  WeatherProvider? _weather;
  RoutingProvider? _routing;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showRecent = false;
  bool _uiVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = Provider.of<AppSettingsProvider>(context, listen: false);
      unawaited(s.load().then((_) {
        if (!mounted) return;
        final map = Provider.of<MapProvider>(context, listen: false);
        map.syncNotificationsEnabledFromSettings(s.notificationsEnabled);
      }));

      final weather = Provider.of<WeatherProvider>(context, listen: false);
      _weather = weather;

      final routing = Provider.of<RoutingProvider>(context, listen: false);
      _routing = routing;

      final conn = Provider.of<ConnectivityProvider>(context, listen: false);
      _connectivity = conn;
      _connectivityListener = () {
        final map = Provider.of<MapProvider>(context, listen: false);
        map.syncIsOnlineFromConnectivity(conn.isOnline);
        weather.syncIsOnline(conn.isOnline);
        routing.syncIsOnline(conn.isOnline);
      };
      conn.addListener(_connectivityListener!);
      _connectivityListener!();
      
      _searchFocusNode.addListener(() {
        setState(() {
          _showRecent = _searchFocusNode.hasFocus && _searchController.text.isEmpty;
        });
      });
    });
  }

  @override
  void dispose() {
    final conn = _connectivity;
    final listener = _connectivityListener;
    if (conn != null && listener != null) {
      conn.removeListener(listener);
    }
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final p = Provider.of<MapProvider>(context, listen: false);
    final fg = state == AppLifecycleState.resumed;
    p.setAppInForeground(fg);

    final w = _weather;
    if (w != null) {
      w.syncAppInForeground(fg);
    }

    final r = _routing;
    if (r != null) {
      r.syncAppInForeground(fg);
    }
  }

  Future<void> _recenterOnUser(MapProvider mapProvider) async {
    if (kIsWeb) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Localisation limitée sur Web. Autorise la permission navigateur puis réessaie.')),
      );
      return;
    }

    try {
      final loc = Provider.of<LocationProvider>(context, listen: false);
      final position = await loc.getCurrentPosition();
      final target = LatLng(position.latitude, position.longitude);
      unawaited(HapticFeedback.mediumImpact());
      mapProvider.centerOnUser(target);
      final weather = Provider.of<WeatherProvider>(context, listen: false);
      unawaited(weather.refreshWeatherAt(target, userInitiated: true));
    } catch (e, st) {
      assert(() {
        AppLog.w('map.recenterOnUser failed', error: e, stackTrace: st);
        return true;
      }());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de récupérer la position. Vérifie les permissions et le GPS.')),
      );
    }
  }

  void _onMapMoveStart() {
    if (!_uiVisible) return;
    setState(() => _uiVisible = false);
    _hideTimer?.cancel();
  }

  void _onMapMoveEnd() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _uiVisible = true);
    });
  }

  void _pokeUi() {
    if (!_uiVisible) setState(() => _uiVisible = true);
    _onMapMoveEnd();
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = Provider.of<MapProvider>(context);
    final weather = Provider.of<WeatherProvider>(context);
    final routing = Provider.of<RoutingProvider>(context);
    final offline = Provider.of<OfflineProvider>(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurfaceStrong = scheme.onSurface.withOpacity(0.88);
    final onSurfaceMuted = scheme.onSurface.withOpacity(0.60);
    final onSurfaceSubtle = scheme.onSurface.withOpacity(0.55);
    final w = MediaQuery.sizeOf(context).width;
    final edgeInset = w >= HorizonBreakpoints.medium
        ? HorizonTokens.space32
        : (w >= HorizonBreakpoints.compact ? HorizonTokens.space24 : HorizonTokens.space20);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ----- Map -----
          HorizonMap(
            onMapCreated: (controller) {
              mapProvider.setController(controller);
              weather.setController(controller);
              routing.setController(controller);
              offline.setController(controller);
            },
            onCameraMoveStarted: _onMapMoveStart,
            onCameraMoveFinished: _onMapMoveEnd,
            onMapTap: (ll) => _pokeUi(),
          ),
          if (!mapProvider.isStyleLoaded)
            const Center(child: CircularProgressIndicator()),

          // ----- Top Search Bar -----
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            top: _uiVisible ? 10 : -100,
            left: edgeInset,
            right: edgeInset,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _uiVisible ? 1.0 : 0.0,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSearchBar(context, mapProvider, onSurfaceMuted, onSurfaceSubtle),
                    if (_showRecent && mapProvider.recentSearches.isNotEmpty)
                      _buildRecentSearches(context, mapProvider, scheme),
                  ],
                ),
              ),
            ),
          ),

          // ----- Top status area -----
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            top: _uiVisible ? 70 : 10,
            left: edgeInset,
            right: edgeInset,
            child: Center(
              child: Hero(
                tag: 'status-pill',
                child: Material(
                  color: scheme.surface.withOpacity(0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const WeatherStatusPill(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: routing.routeVariants.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: const RouteInfoCard(),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ----- Bottom controls -----
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            bottom: _uiVisible ? 40 : -200,
            left: edgeInset,
            child: SafeArea(
              top: false,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _uiVisible ? 1.0 : 0.0,
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: w >= HorizonBreakpoints.medium ? 640 : 340,
                      maxHeight: MediaQuery.sizeOf(context).height * (w >= HorizonBreakpoints.medium ? 0.70 : 0.42),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRoutingControls(
                            context, routing, offline, mapProvider,
                            onSurfaceStrong, onSurfaceMuted, onSurfaceSubtle, scheme,
                          ),
                          _buildRoutingMessages(context, routing, onSurfaceStrong),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            bottom: _uiVisible ? 40 : -200,
            right: edgeInset,
            child: SafeArea(
              top: false,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _uiVisible ? 1.0 : 0.0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: MediaQuery.sizeOf(context).height * (w >= HorizonBreakpoints.medium ? 0.70 : 0.62),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: _buildActionColumn(
                      context, routing, offline, mapProvider,
                      onSurfaceStrong, onSurfaceMuted, onSurfaceSubtle, scheme,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: const OfflineProgressBar(),
    );
  }

  // ---------------------------------------------------------------------------
  // Extracted build helpers (still in same file for access to state/context)
  // ---------------------------------------------------------------------------

  Widget _buildRoutingControls(
    BuildContext context,
    RoutingProvider routing,
    OfflineProvider offline,
    MapProvider mapProvider,
    Color onSurfaceStrong,
    Color onSurfaceMuted,
    Color onSurfaceSubtle,
    ColorScheme scheme,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: glassDecoration(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _routingTitle(context, routing, onSurfaceStrong, onSurfaceMuted)),
                    if (routing.routeVariants.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      _clearRouteButton(routing, onSurfaceMuted),
                      const SizedBox(width: 10),
                      _whyRouteButton(context, routing, scheme),
                    ],
                  ],
                ),
                if (routing.routeVariants.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _variantChips(routing),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _routingTitle(BuildContext context, RoutingProvider routing, Color strong, Color muted) {
    String title;
    String? subtitle;

    if (routing.routingLoading) {
      title = 'Route…';
    } else if (routing.routingError != null) {
      title = 'Route indisponible';
    } else if (routing.routeVariants.isEmpty) {
      title = 'Itinéraire';
      subtitle = 'Long-press: départ puis arrivée';
    } else if (routing.selectedVariant == RouteVariantKind.imported && routing.gpxRouteName != null) {
      title = 'GPX';
      subtitle = routing.gpxRouteName;
    } else {
      title = 'Variante';
      subtitle = routeVariantLabel(routing.selectedVariant.name);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: strong,
              ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
          ),
      ],
    );
  }

  Widget _clearRouteButton(RoutingProvider routing, Color muted) {
    return InkWell(
      onTap: () => routing.clearRoute(),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Tooltip(
          message: 'Effacer l\'itinéraire',
          child: Semantics(
            button: true,
            label: 'Effacer l\'itinéraire',
            child: Icon(Icons.close_rounded, size: 18, color: muted),
          ),
        ),
      ),
    );
  }

  Widget _whyRouteButton(BuildContext context, RoutingProvider routing, ColorScheme scheme) {
    return TextButton(
      onPressed: () async {
        final selected = routing.currentRouteExplanation;
        if (selected == null) return;
        final all = routing.routeExplanations;
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: false,
          builder: (ctx) {
            final theme = Theme.of(ctx);
            final entries = all.entries.toList();
            entries.sort((a, b) => a.key.index.compareTo(b.key.index));

            final schm = theme.colorScheme;
            final muted = schm.onSurface.withOpacity(0.60);
            final body = schm.onSurface.withOpacity(0.88);
            final textTheme = theme.textTheme;

            return HorizonBottomSheet(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pourquoi cette route ?', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text(selected.headline, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (selected.caveat != null) ...[
                    const SizedBox(height: 6),
                    Text(selected.caveat!, style: textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                  if (selected.metrics.avgConfidence > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Fiabilité : ${routing.confidenceLabel(selected.metrics.avgConfidence)} (confiance ${(selected.metrics.avgConfidence * 100).round()}%)',
                      style: textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (selected.factors.isEmpty)
                    Text('Aucun facteur dominant détecté.', style: textTheme.bodySmall?.copyWith(color: muted))
                  else
                    ...selected.factors.map((f) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: schm.primary.withOpacity(0.65),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.title, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(f.detail, style: textTheme.bodySmall?.copyWith(color: body)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  Text('Comparaison rapide', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ...entries.map((e) {
                    final ex = e.value;
                    final label = routeVariantLabel(e.key.name);
                    final selectedMark = e.key == routing.selectedVariant ? ' • sélectionnée' : '';
                    final elev = ex.metrics.elevationGain.round();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '$label$selectedMark — elev +${elev}m, vent ${msToKmh(ex.metrics.avgWind).toStringAsFixed(0)} km/h, pluie ~${ex.metrics.rainKm.toStringAsFixed(1)} km, conf ${(ex.metrics.avgConfidence * 100).round()}%',
                        style: textTheme.bodySmall?.copyWith(color: body),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  FutureBuilder<DepartureWindowRecommendation?>(
                    future: routing.recommendDepartureWindowForSelectedVariant(),
                    builder: (context, snap) {
                      final rec = snap.data;
                      if (snap.connectionState != ConnectionState.done) {
                        return Text('Calcul…', style: textTheme.bodySmall?.copyWith(color: muted));
                      }
                      if (rec == null) return const SizedBox.shrink();
                      final when = DateTime.now().add(rec.bestOffset);
                      final hh = when.hour.toString().padLeft(2, '0');
                      final mm = when.minute.toString().padLeft(2, '0');
                      return Text(
                        'Fenêtre optimale : $hh:$mm (${rec.rationale})',
                        style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Tooltip(
        message: 'Pourquoi cette route ?',
        child: Semantics(
          button: true,
          label: 'Afficher pourquoi cette route est recommandée',
          child: Text(
            'Pourquoi ?'.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
          ),
        ),
      ),
    );
  }

  Widget _variantChips(RoutingProvider routing) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (routing.routeVariants.any((v) => v.kind == RouteVariantKind.fast))
          RouteChip(label: 'Rapide', selected: routing.selectedVariant == RouteVariantKind.fast, onTap: () => routing.selectRouteVariant(RouteVariantKind.fast)),
        if (routing.routeVariants.any((v) => v.kind == RouteVariantKind.safe))
          RouteChip(label: 'Sûre', selected: routing.selectedVariant == RouteVariantKind.safe, onTap: () => routing.selectRouteVariant(RouteVariantKind.safe)),
        if (routing.routeVariants.any((v) => v.kind == RouteVariantKind.scenic))
          RouteChip(label: 'Calme', selected: routing.selectedVariant == RouteVariantKind.scenic, onTap: () => routing.selectRouteVariant(RouteVariantKind.scenic)),
        if (routing.routeVariants.any((v) => v.kind == RouteVariantKind.imported))
          RouteChip(label: 'GPX', selected: routing.selectedVariant == RouteVariantKind.imported, onTap: () => routing.selectRouteVariant(RouteVariantKind.imported)),
      ],
    );
  }

  Widget _buildRoutingMessages(BuildContext context, RoutingProvider routing, Color onSurfaceStrong) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (routing.routingError != null)
          _glassMessage(context, routing.routingError!, color: const Color(0xFFC88B6E)),
        if (routing.gpxImportLoading || routing.gpxImportError != null)
          _glassMessage(
            context,
            routing.gpxImportLoading ? 'Import…' : (routing.gpxImportError ?? 'Import GPX'),
            color: routing.gpxImportError == null ? onSurfaceStrong : const Color(0xFFC88B6E),
          ),
        if (routing.routeExplanation != null)
          _glassMessage(context, routing.routeExplanation!, color: onSurfaceStrong, opacity: 0.54),
      ],
    );
  }

  Widget _glassMessage(BuildContext context, String text, {required Color color, double opacity = 0.62}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22.0),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: glassDecoration(context, opacity: opacity),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionColumn(
    BuildContext context,
    RoutingProvider routing,
    OfflineProvider offline,
    MapProvider mapProvider,
    Color onSurfaceStrong,
    Color onSurfaceMuted,
    Color onSurfaceSubtle,
    ColorScheme scheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _fab(
          heroTag: 'settings',
          order: 1,
          icon: Icons.tune_rounded,
          tooltip: 'Réglages',
          color: onSurfaceStrong,
          onPressed: () => SettingsSheet.show(context),
        ),
        _fab(
          heroTag: 'dashboard',
          order: 1.5,
          icon: Icons.dashboard_customize_outlined,
          tooltip: 'Dashboard Journalier',
          color: onSurfaceStrong,
          onPressed: () => HomeTodayDashboardSheet.show(context),
        ),
        _fab(
          heroTag: 'pmtiles-pack',
          order: 2,
          icon: offline.pmtilesEnabled ? Icons.storage_rounded : Icons.storage_outlined,
          tooltip: kIsWeb
              ? 'Pack offline indisponible sur Web'
              : (offline.pmtilesEnabled ? 'Désactiver le pack offline' : 'Activer le pack offline'),
          color: onSurfaceStrong,
          onPressed: kIsWeb
              ? null
              : () {
                  if (offline.pmtilesEnabled) {
                    offline.disablePmtilesPack();
                  } else {
                    offline.enablePmtilesPack(
                      url: 'https://r2-public.protomaps.com/protomaps-sample-datasets/cb_2018_us_zcta510_500k.pmtiles',
                      fileName: 'horizon.pmtiles',
                      regionNameForUi: 'Pack offline',
                    );
                  }
                },
          onLongPress: (!kIsWeb && offline.pmtilesEnabled)
              ? () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Supprimer le pack offline ?'),
                      content: const Text('Le pack PMTiles sera supprimé de l\'appareil.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
                        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await offline.uninstallCurrentPmtilesPack();
                  }
                }
              : null,
        ),
        _fab(
          heroTag: 'offline-download',
          order: 3,
          icon: Icons.cloud_download_outlined,
          tooltip: kIsWeb ? 'Offline indisponible sur Web' : 'Télécharger la région visible',
          color: onSurfaceStrong,
          onPressed: kIsWeb ? null : () => offline.downloadVisibleRegion(regionName: 'Visible region'),
          onLongPress: kIsWeb
              ? null
              : () async {
                  final packs = await offline.listOfflinePacks();
                  if (!context.mounted) return;
                  await _showOfflinePacksSheet(context, offline, packs);
                },
        ),
        _fab(
          heroTag: 'recenter',
          order: 0,
          icon: Icons.my_location_rounded,
          tooltip: 'Ma position',
          color: scheme.primary,
          onPressed: () {
            unawaited(HapticFeedback.lightImpact());
            _recenterOnUser(mapProvider);
          },
        ),
        _fab(
          heroTag: 'import-gpx',
          order: 5,
          icon: Icons.file_open_outlined,
          tooltip: 'Importer GPX',
          color: onSurfaceStrong,
          onPressed: () => routing.importGpxRoute(),
        ),
      ],
    );
  }

  Widget _buildSearchBar(
    BuildContext context,
    MapProvider mapProvider,
    Color onSurfaceMuted,
    Color onSurfaceSubtle,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: glassDecoration(context, opacity: 0.92).copyWith(
        borderRadius: BorderRadius.circular(28),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        textInputAction: TextInputAction.search,
        onChanged: (v) {
          setState(() {
            _showRecent = _searchFocusNode.hasFocus && v.isEmpty;
          });
        },
        onSubmitted: (query) async {
          unawaited(HapticFeedback.mediumImpact());
          _searchFocusNode.unfocus();
          final results = await mapProvider.searchLocation(query);
          if (!context.mounted) return;
          if (results.length > 1) {
            unawaited(GeocodingSelectionSheet.show(
              context,
              results: results,
              onSelected: (r) => mapProvider.centerOnUser(r.location),
            ));
          } else if (results.isEmpty && query.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Aucun résultat pour "$query"')),
            );
          }
          _searchController.clear();
        },
        decoration: InputDecoration(
          hintText: 'Où allez-vous ?',
          hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: onSurfaceSubtle, fontWeight: FontWeight.w600),
          prefixIcon: mapProvider.geocodingLoading
              ? Container(
                  width: 20,
                  height: 20,
                  padding: const EdgeInsets.all(12),
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.search, color: onSurfaceMuted),
          suffixIcon: IconButton(
            icon: Icon(Icons.close_rounded, color: onSurfaceMuted, size: 20),
            onPressed: () => _searchController.clear(),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _fab({
    required String heroTag,
    required double order,
    required IconData icon,
    required String tooltip,
    required Color color,
    VoidCallback? onPressed,
    VoidCallback? onLongPress,
  }) {
    Widget fab = FloatingActionButton.small(
      heroTag: heroTag,
      onPressed: onPressed,
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Icon(icon, color: color),
        ),
      ),
    );
    if (onLongPress != null) {
      fab = GestureDetector(
        onLongPress: onLongPress,
        child: fab,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FocusTraversalOrder(
        order: NumericFocusOrder(order),
        child: fab,
      ),
    );
  }

  Future<void> _showOfflinePacksSheet(BuildContext context, OfflineProvider offline, List<dynamic> packs) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        final onSurfaceMuted = scheme.onSurface.withOpacity(0.60);
        return HorizonBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Packs offline', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (packs.isEmpty)
                Text('Aucun pack installé.', style: theme.textTheme.bodySmall?.copyWith(color: onSurfaceMuted))
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: packs.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (c, i) {
                      final p = packs[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.id as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text('${p.type.name} • ${formatBytes(p.sizeBytes as int)}', style: theme.textTheme.bodySmall?.copyWith(color: onSurfaceMuted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: ctx,
                                builder: (dctx) => AlertDialog(
                                  title: const Text('Supprimer ce pack ?'),
                                  content: Text(p.id as String),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Annuler')),
                                    TextButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Supprimer')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await offline.uninstallOfflinePackById(p.id as String);
                                if (ctx.mounted) Navigator.of(ctx).pop();
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
