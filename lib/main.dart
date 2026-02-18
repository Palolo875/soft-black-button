import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app/providers/map_provider.dart';
import 'package:app/services/theme_settings_store.dart';
import 'package:app/ui/horizon_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:app/features/map/presentation/map_screen.dart';
import 'package:app/core/di/app_dependencies.dart';
import 'package:app/providers/app_settings_provider.dart';
import 'package:app/providers/connectivity_provider.dart';
import 'package:app/providers/location_provider.dart';
import 'package:app/providers/weather_provider.dart';
import 'package:app/providers/routing_provider.dart';
import 'package:app/providers/offline_provider.dart';

void main() {
  final deps = AppDependencies.create();
  runApp(HorizonApp(deps: deps));
}

class HorizonApp extends StatelessWidget {
  final AppDependencies deps;

  const HorizonApp({
    super.key,
    required this.deps,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: deps),
        ChangeNotifierProvider(
          create: (_) => ConnectivityProvider()..init(),
        ),
        ChangeNotifierProvider(
          create: (_) => LocationProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => WeatherProvider(
            weatherService: deps.weatherService,
            weatherEngine: deps.weatherEngine,
            scheduler: deps.scheduler,
            metrics: deps.metrics,
            analytics: deps.analytics,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => RoutingProvider(
            routingEngine: deps.routingEngine,
            routeCache: deps.routeCache,
            scheduler: deps.scheduler,
            metrics: deps.metrics,
            analytics: deps.analytics,
            routeCompare: deps.routeCompare,
            gpxImport: deps.gpxImport,
            routeWeatherProjector: deps.routeWeatherProjector,
            explainability: deps.explainability,
            notifications: deps.notifications,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => OfflineProvider(
            offlineService: deps.offlineService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(
            analytics: deps.analytics,
            metrics: deps.metrics,
            notifications: deps.notifications,
            notificationStore: deps.notificationStore,
            themeStore: deps.themeStore,
          ),
        ),
        ChangeNotifierProxyProvider<RoutingProvider, MapProvider>(
          create: (_) => MapProvider(
            privacyService: deps.privacyService,
            analytics: deps.analytics,
            metrics: deps.metrics,
          ),
          update: (_, routing, map) {
            map?.attachRouting(routing);
            return map!;
          },
        ),
        ProxyProvider2<MapProvider, OfflineProvider, MapProvider>(
          update: (_, map, offline, __) {
            map.attachOffline(offline);
            return map;
          },
        ),
      ],
      child: Consumer<AppSettingsProvider>(
        builder: (context, settings, _) {
          final mode = settings.appThemeMode;
          final themeMode = mode == AppThemeMode.dark
              ? ThemeMode.dark
              : (mode == AppThemeMode.light ? ThemeMode.light : ThemeMode.system);

          return MaterialApp(
            title: 'Horizon',
            debugShowCheckedModeBanner: false,
            theme: HorizonTheme.light(),
            darkTheme: HorizonTheme.dark(),
            themeMode: themeMode,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('fr', 'FR'),
              Locale('en', 'US'),
            ],
            home: const MapScreen(),
          );
        },
      ),
    );
  }
}
