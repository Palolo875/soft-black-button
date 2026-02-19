import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:horizon/core/errors/remote_service_exception.dart';

String friendlyError(Object error) {
  if (error is RemoteServiceException) {
    return error.message;
  }
  if (error is TimeoutException) {
    return 'Délai dépassé. Vérifie ta connexion et réessaie.';
  }
  if (error is SocketException) {
    return 'Connexion réseau indisponible.';
  }
  if (error is HttpException) {
    return 'Erreur réseau (HTTP).';
  }
  if (error is FormatException) {
    return 'Données reçues invalides.';
  }
  if (error is PlatformException) {
    final msg = error.message;
    if (msg != null && msg.trim().isNotEmpty) {
      return msg;
    }
    return error.code;
  }

  return 'Une erreur est survenue.';
}
