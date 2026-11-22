import 'cattle.dart';

/// Prepared online: the minimal list of cattle in the user's current scope, with an expiry.
/// Offline capture is allowed only while it is valid for the same user. It never grants
/// write permission: the server re-authorizes every intent at sync time.
class WorkSession {
  const WorkSession({
    required this.username,
    required this.preparedAt,
    required this.expiresAt,
    required this.cattle,
  });

  final String username;
  final DateTime preparedAt;
  final DateTime expiresAt;
  final List<Cattle> cattle;

  bool isValidFor(String? user, DateTime now) => user == username && now.isBefore(expiresAt);

  Cattle? byRfid(String rfid) {
    for (final c in cattle) {
      if (c.rfid == rfid) return c;
    }
    return null;
  }
}
