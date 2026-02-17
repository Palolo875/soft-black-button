import 'dart:io';

Future<void> main() async {
  final buildDir = Directory('build/web');
  if (!await buildDir.exists()) {
    print('Error: build/web directory not found. Run flutter build web first.');
    exit(1);
  }

  final server = await HttpServer.bind('0.0.0.0', 5000);
  print('Serving Flutter web app on http://0.0.0.0:5000');

  await for (final request in server) {
    var path = request.uri.path;
    if (path == '/') path = '/index.html';

    final file = File('build/web$path');
    if (await file.exists()) {
      final ext = path.split('.').last.toLowerCase();
      final contentType = _mimeType(ext);
      request.response.headers.set('Content-Type', contentType);
      request.response.headers.set('Cache-Control', 'no-cache');
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      await file.openRead().pipe(request.response);
    } else {
      final indexFile = File('build/web/index.html');
      request.response.headers.set('Content-Type', 'text/html');
      request.response.headers.set('Cache-Control', 'no-cache');
      await indexFile.openRead().pipe(request.response);
    }
  }
}

String _mimeType(String ext) {
  switch (ext) {
    case 'html': return 'text/html; charset=utf-8';
    case 'js': return 'application/javascript';
    case 'css': return 'text/css';
    case 'json': return 'application/json';
    case 'png': return 'image/png';
    case 'jpg': case 'jpeg': return 'image/jpeg';
    case 'gif': return 'image/gif';
    case 'svg': return 'image/svg+xml';
    case 'ico': return 'image/x-icon';
    case 'woff': return 'font/woff';
    case 'woff2': return 'font/woff2';
    case 'ttf': return 'font/ttf';
    case 'otf': return 'font/otf';
    default: return 'application/octet-stream';
  }
}
