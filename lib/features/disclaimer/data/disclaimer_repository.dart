import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';

/// Current disclaimer version. Bump this when the disclaimer text changes
/// to require re-acceptance.
const kDisclaimerVersion = '1.0';

/// Repository for tracking disclaimer acceptance.
///
/// Records acceptance locally (Drift) and remotely (Supabase).
class DisclaimerRepository {
  DisclaimerRepository(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;

  /// Check if the current user has accepted the latest disclaimer.
  Future<bool> hasAcceptedLatest(String userId) async {
    final record = await _db.getLatestDisclaimer(userId);
    if (record == null) return false;
    return record.disclaimerVersion == kDisclaimerVersion;
  }

  /// Record disclaimer acceptance locally and enqueue sync.
  Future<void> accept({
    required String userId,
    required String appVersion,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    // Write to local DB
    await _db.into(_db.localDisclaimerAcceptances).insert(
      LocalDisclaimerAcceptancesCompanion.insert(
        id: id,
        userId: userId,
        acceptedAt: Value(now),
        appVersion: appVersion,
        disclaimerVersion: kDisclaimerVersion,
      ),
    );

    // Enqueue for sync
    await _db.enqueueSync(
      targetTable: 'disclaimer_acceptances',
      operation: 'insert',
      recordId: id,
      payloadJson: '{'
          '"id":"$id",'
          '"user_id":"$userId",'
          '"accepted_at":"${now.toIso8601String()}",'
          '"app_version":"$appVersion",'
          '"disclaimer_version":"$kDisclaimerVersion"'
          '}',
    );

    // Also try to write directly to Supabase (best-effort)
    try {
      await _client.from('disclaimer_acceptances').insert({
        'id': id,
        'user_id': userId,
        'accepted_at': now.toIso8601String(),
        'app_version': appVersion,
        'disclaimer_version': kDisclaimerVersion,
      });
    } catch (_) {
      // Sync queue will handle this later
    }
  }
}
