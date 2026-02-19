import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:horizon/providers/map_provider.dart';
import 'package:horizon/providers/location_provider.dart';
import 'package:horizon/providers/weather_provider.dart';
import 'package:horizon/providers/routing_provider.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/core/log/app_log.dart';

class HorizonMap extends StatefulWidget {
  final void Function(MaplibreMapController)? onMapCreated;
  final VoidCallback? onCameraMoveStarted;
  final VoidCallback? onCameraMoveFinished;
  final void Function(LatLng)? onMapTap;

  const HorizonMap({
    super.key,
    this.onMapCreated,
    this.onCameraMoveStarted,
    this.onCameraMoveFinished,
    this.onMapTap,
  });

  @override
  State<HorizonMap> createState() => _HorizonMapState();
}

class _HorizonMapState extends State<HorizonMap> {
  Future<String>? _styleFuture;

  @override
  void initState() {
    super.initState();
    _styleFuture = rootBundle.loadString('assets/styles/horizon_style.json');
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
    final location = Provider.of<LocationProvider>(context);
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
            target: LatLng(48.8566, 2.3522), // Paris
            zoom: 11.0,
          ),
          myLocationEnabled: location.permissionGranted,
          myLocationTrackingMode: location.permissionGranted 
              ? MyLocationTrackingMode.tracking 
              : MyLocationTrackingMode.none,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          compassEnabled: true,
          trackCameraPosition: true,
          onCameraMove: widget.onCameraMoveStarted != null ? (_) => widget.onCameraMoveStarted!() : null,
          onCameraIdle: widget.onCameraMoveFinished,
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
            if (widget.onMapTap != null) widget.onMapTap!(latLng);
            Provider.of<RoutingProvider>(context, listen: false).onMapTap(latLng);
          },
        );
      },
    );
  }
}
