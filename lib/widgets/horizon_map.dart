import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:horizon/providers/map_provider.dart';
import 'package:horizon/providers/location_provider.dart';
import 'package:horizon/providers/weather_provider.dart';
import 'package:horizon/providers/routing_provider.dart';
import 'package:horizon/core/log/app_log.dart';

class HorizonMap extends StatefulWidget {
  final void Function(MaplibreMapController)? onMapCreated;

  const HorizonMap({super.key, this.onMapCreated});

  @override
  State<HorizonMap> createState() => _HorizonMapState();
}

class _HorizonMapState extends State<HorizonMap> {
  Future<String>? _styleFuture;
  final MapController _webMapController = MapController();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _styleFuture = rootBundle.loadString('assets/styles/horizon_style.json');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final loc = Provider.of<LocationProvider>(context, listen: false);
      unawaited(loc.ensurePermission());
      if (kIsWeb) {
        final p = Provider.of<MapProvider>(context, listen: false);
        final w = Provider.of<WeatherProvider>(context, listen: false);
        final r = Provider.of<RoutingProvider>(context, listen: false);
        p.setStyleLoaded(true);
        w.setStyleLoaded(true);
        r.setStyleLoaded(true);
      }
    });
  }

  void _onMapCreated(MaplibreMapController controller) {
    _loadImages();
    if (widget.onMapCreated != null) {
      widget.onMapCreated!(controller);
    }
  }

  Future<void> _loadImages() async {
    // Dans une vraie app, on chargerait des assets. Ici on peut utiliser des couleurs unies ou des formes simples
    // controller.addImage("wind-icon", ...);
  }

  @override
  Widget build(BuildContext context) {
    final granted = context.select<LocationProvider, bool>((p) => p.permissionGranted);

    if (kIsWeb) {
      final start = context.select<MapProvider, LatLng?>((p) => p.routeStart);
      final end = context.select<MapProvider, LatLng?>((p) => p.routeEnd);
      final selectedVariant = context.select<MapProvider, RouteVariantKind>((p) => p.selectedVariant);
      final variants = context.select<MapProvider, List<RouteVariant>>((p) => p.routeVariants);
      final webCenter = context.select<MapProvider, LatLng?>((p) => p.webCenter);
      final scheme = Theme.of(context).colorScheme;

      if (webCenter != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _webMapController.move(ll.LatLng(webCenter.latitude, webCenter.longitude), 14.0);
        });
      }

      final selected = variants.where((v) => v.kind == selectedVariant).cast<RouteVariant?>().firstOrNull;
      final line = selected?.shape;

      final polylines = <Polyline>[];
      if (line != null && line.isNotEmpty) {
        polylines.add(
          Polyline(
            points: line.map((p) => ll.LatLng(p.latitude, p.longitude)).toList(),
            strokeWidth: 4,
            color: scheme.primary.withOpacity(0.78),
            borderStrokeWidth: 2,
            borderColor: scheme.surface.withOpacity(0.85),
          ),
        );
      }

      final markers = <Marker>[];
      if (start != null) {
        markers.add(
          Marker(
            width: 28,
            height: 28,
            point: ll.LatLng(start.latitude, start.longitude),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.92),
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface.withOpacity(0.9), width: 2),
              ),
            ),
          ),
        );
      }
      if (end != null) {
        markers.add(
          Marker(
            width: 28,
            height: 28,
            point: ll.LatLng(end.latitude, end.longitude),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.tertiary.withOpacity(0.92),
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface.withOpacity(0.9), width: 2),
              ),
            ),
          ),
        );
      }

      return FlutterMap(
        mapController: _webMapController,
        options: MapOptions(
          initialCenter: const ll.LatLng(48.8566, 2.3522),
          initialZoom: 11.0,
          onTap: (tapPosition, latLng) {
            Provider.of<RoutingProvider>(context, listen: false).onMapTap(LatLng(latLng.latitude, latLng.longitude));
          },
          onLongPress: (tapPosition, latLng) {
            Provider.of<RoutingProvider>(context, listen: false)
                .setRoutePoint(LatLng(latLng.latitude, latLng.longitude));
          },
        ),
        children: [
          const TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'app.horizon',
          ),
          if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
          if (markers.isNotEmpty) MarkerLayer(markers: markers),
        ],
      );
    }

    final styleFuture = _styleFuture;
    if (styleFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<String>(
      future: styleFuture,
      builder: (context, snap) {
        final style = snap.data;
        if (style == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return MaplibreMap(
          styleString: style,
          onMapCreated: _onMapCreated,
          initialCameraPosition: const CameraPosition(
            target: LatLng(48.8566, 2.3522), // Paris par défaut
            zoom: 11.0,
          ),
          myLocationEnabled: granted,
          myLocationTrackingMode: granted ? MyLocationTrackingMode.tracking : MyLocationTrackingMode.none,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          compassEnabled: true,
          trackCameraPosition: true,
          onStyleLoadedCallback: () {
            AppLog.d('map.style.loaded');
            Provider.of<MapProvider>(context, listen: false).setStyleLoaded(true);
            Provider.of<WeatherProvider>(context, listen: false).setStyleLoaded(true);
            Provider.of<RoutingProvider>(context, listen: false).setStyleLoaded(true);
          },
          onMapLongClick: (point, latLng) {
            Provider.of<RoutingProvider>(context, listen: false).setRoutePoint(latLng);
          },
          onMapClick: (point, latLng) {
            Provider.of<RoutingProvider>(context, listen: false).onMapTap(latLng);
          },
        );
      },
    );
  }
}
