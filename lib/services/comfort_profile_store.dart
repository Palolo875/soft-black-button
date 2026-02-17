import 'package:app/services/comfort_profile.dart';
import 'package:app/services/secure_file_store.dart';

class ComfortProfileStore {
  static const _key = 'comfort_profile_v1';

  final SecureFileStore _store;

  ComfortProfileStore({SecureFileStore store = const SecureFileStore()}) : _store = store;

  Future<ComfortProfile> load() async {
    final raw = await _store.readJsonDecrypted(_key);
    if (raw == null) return const ComfortProfile();
    return ComfortProfile.fromJson(raw);
  }

  Future<void> save(ComfortProfile profile) async {
    await _store.writeJsonEncrypted(_key, profile.toJson());
  }
}
