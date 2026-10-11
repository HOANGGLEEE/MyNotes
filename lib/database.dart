import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
part 'database.g.dart';

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get owner => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Notes])
class NoteDatabase extends _$NoteDatabase {
  NoteDatabase([QueryExecutor? executor])
    : super(
        executor ??
            LazyDatabase(() async {
              final dir = await getApplicationSupportDirectory();
              return NativeDatabase.createInBackground(
                File(p.join(dir.path, 'mynotes.sqlite')),
              );
            }),
      );
  @override
  int get schemaVersion => 1;
  Stream<List<Note>> watchNotes(String owner) =>
      (select(notes)
            ..where((n) => n.owner.equals(owner) & n.deleted.equals(false))
            ..orderBy([
              (n) => OrderingTerm.desc(n.pinned),
              (n) => OrderingTerm.desc(n.updatedAt),
            ]))
          .watch();
  Future<void> save(
    String owner,
    String title,
    String body, {
    Note? previous,
    bool? pinned,
    bool deleted = false,
  }) async {
    if (previous != null && previous.owner != owner) {
      throw StateError('Owner mismatch');
    }
    await into(notes).insertOnConflictUpdate(
      NotesCompanion.insert(
        id: previous?.id ?? const Uuid().v4(),
        owner: owner,
        title: title.trim(),
        body: body,
        pinned: Value(pinned ?? previous?.pinned ?? false),
        deleted: Value(deleted),
        dirty: const Value(true),
        revision: Value((previous?.revision ?? 0) + 1),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<List<Note>> pending(String owner) => (select(
    notes,
  )..where((n) => n.owner.equals(owner) & n.dirty.equals(true))).get();
  Future<void> acknowledge(Note note) async {
    await (update(notes)..where(
          (n) =>
              n.id.equals(note.id) &
              n.owner.equals(note.owner) &
              n.revision.equals(note.revision),
        ))
        .write(const NotesCompanion(dirty: Value(false)));
  }

  Future<void> merge(String owner, Map<String, dynamic> row) =>
      transaction(() async {
        if (row['user_id'] != owner) {
          throw StateError('Owner mismatch');
        }
        final existing = await (select(
          notes,
        )..where((n) => n.id.equals(row['id'] as String))).getSingleOrNull();
        if (existing != null && (existing.owner != owner || existing.dirty)) {
          return;
        }
        await into(notes).insertOnConflictUpdate(
          NotesCompanion.insert(
            id: row['id'] as String,
            owner: owner,
            title: row['title'] as String,
            body: row['body'] as String,
            pinned: Value(row['pinned'] as bool),
            deleted: Value(row['deleted'] as bool),
            dirty: const Value(false),
            updatedAt: DateTime.parse(row['updated_at'] as String),
          ),
        );
      });
}
