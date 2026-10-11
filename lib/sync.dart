import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database.dart';

class NoteSync extends ChangeNotifier {
  NoteSync(this.db, this.client) {
    _auth = client?.auth.onAuthStateChange.listen((_) => _sessionChanged());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
    _sessionChanged();
  }
  final NoteDatabase db;
  final SupabaseClient? client;
  StreamSubscription<AuthState>? _auth;
  Timer? _timer;
  RealtimeChannel? _channel;
  bool _busy = false;
  bool _closed = false;
  String status = 'Lưu trên thiết bị';
  String get owner => client?.auth.currentUser?.id ?? 'local';
  void _sessionChanged() {
    if (_channel != null) {
      unawaited(client!.removeChannel(_channel!));
    }
    _channel = null;
    if (owner != 'local') {
      _channel =
          client!
              .channel('notes:$owner')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'notes',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: owner,
                ),
                callback: (_) => sync(),
              )
            ..subscribe();
    }
    status = owner == 'local' ? 'Lưu trên thiết bị' : 'Đang đồng bộ';
    notifyListeners();
    unawaited(sync());
  }

  Future<void> sync() async {
    if (_busy || _closed || owner == 'local' || client == null) {
      return;
    }
    _busy = true;
    final user = owner;
    try {
      for (final note in await db.pending(user)) {
        if (owner != user || _closed) {
          return;
        }
        // Atomic server-side compare-and-swap prevents blind overwrites.
        final result = await client!.rpc('save_note_if_revision', params: {
          'p_id': note.id,
          'p_title': note.title,
          'p_body': note.body,
          'p_pinned': note.pinned,
          'p_deleted': note.deleted,
          'p_expected_revision': note.serverRevision,
        });
        final newRevision = (result as num?)?.toInt();
        if (newRevision == null) {
          await db.preserveConflict(note);
          status = 'Xung đột: đã giữ một bản sao';
          continue;
        }
        if (owner != user || _closed) return;
        await db.acknowledge(note, newRevision);
      }
      for (var offset = 0; ; offset += 500) {
        final rows = await client!
            .from('notes')
            .select()
            .eq('user_id', user)
            .order('id')
            .range(offset, offset + 499);
        if (owner != user || _closed) {
          return;
        }
        for (final row in rows) {
          await db.merge(user, row);
        }
        if (rows.length < 500) {
          break;
        }
      }
      if (!status.startsWith('Xung đột')) status = 'Đã đồng bộ';
    } catch (_) {
      status = 'Chưa đồng bộ — sẽ thử lại';
    } finally {
      _busy = false;
      if (!_closed) {
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    unawaited(_auth?.cancel());
    if (_channel != null) {
      unawaited(client!.removeChannel(_channel!));
    }
    super.dispose();
  }
}
