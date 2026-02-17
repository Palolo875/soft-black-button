import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:app/providers/map_provider.dart';

class HorizonMap extends StatefulWidget {
  final void Function(MaplibreMapController)? onMapCreated;

  const HorizonMap({super.key, this.onMapCreated});

  @override
  State<HorizonMap> createState() => _HorizonMapState();
}

class _HorizonMapState extends State<HorizonMap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = Provider.of<MapProvider>(context, listen: false);
      unawaited(p.ensureLocationPermission());
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
    final granted = context.select<MapProvider, bool>((p) => p.locationPermissionGranted);
    return MaplibreMap(
      styleString: 'assets/styles/horizon_style.json',
      onMapCreated: _onMapCreated,
      initialCameraPosition: const CameraPosition(
        target: LatLng(48.8566, 2.3522), // Paris par défaut
        zoom: 11.0,
      ),
      myLocationEnabled: granted,
      myLocationTrackingMode: granted
          ? MyLocationTrackingMode.tracking
          : MyLocationTrackingMode.none,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      compassEnabled: true,
      trackCameraPosition: true,
      onStyleLoadedCallback: () {
        debugPrint("Style loaded successfully");
        Provider.of<MapProvider>(context, listen: false).setStyleLoaded(true);
      },
      onMapLongClick: (point, latLng) {
        Provider.of<MapProvider>(context, listen: false).setRoutePoint(latLng);
      },
      onMapClick: (point, latLng) {
        Provider.of<MapProvider>(context, listen: false).onMapTap(latLng);
      },
    );
  }
}
