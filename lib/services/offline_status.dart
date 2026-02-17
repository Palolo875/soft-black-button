enum OfflineNetStatus { online, offline, unknown }

class OfflineStatus {
  final OfflineNetStatus net;
  final bool syncing;
  final String? message;

  const OfflineStatus({
    required this.net,
    required this.syncing,
    this.message,
  });
}
