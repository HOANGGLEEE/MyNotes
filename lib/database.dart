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
  IntColumn get serverRevision => integer().withDefault(const Constant(0))();
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(notes, notes.serverRevision);
      }
    },
  );
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
    String? id,
    bool? pinned,
    bool deleted = false,
  }) async {
    final noteId = previous?.id ?? id ?? const Uuid().v4();
    final current = await (select(notes)..where((n) => n.id.equals(noteId)))
        .getSingleOrNull();
    if ((previous != null && previous.owner != owner) ||
        (current != null && current.owner != owner)) {
      throw StateError('Owner mismatch');
    }
    await into(notes).insertOnConflictUpdate(
      NotesCompanion.insert(
        id: noteId,
        owner: owner,
        title: title.trim(),
        body: body,
        pinned: Value(pinned ?? current?.pinned ?? previous?.pinned ?? false),
        deleted: Value(deleted),
        dirty: const Value(true),
        revision: Value((current?.revision ?? previous?.revision ?? 0) + 1),
        serverRevision: Value(current?.serverRevision ?? 0),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<List<Note>> pending(String owner) => (select(
    notes,
  )..where((n) => n.owner.equals(owner) & n.dirty.equals(true))).get();
  Future<void> acknowledge(Note note, int serverRevision) async {
    await transaction(() async {
      final current = await (select(notes)
            ..where((n) => n.id.equals(note.id) & n.owner.equals(note.owner)))
          .getSingleOrNull();
      if (current == null) return;
      // An edit made during the upload remains dirty and will be retried
      // against the newly accepted server revision.
      await (update(notes)
            ..where((n) => n.id.equals(note.id) & n.owner.equals(note.owner)))
          .write(NotesCompanion(
        serverRevision: Value(serverRevision),
        dirty: Value(current.revision != note.revision),
      ));
    });
  }

  Future<void> preserveConflict(Note uploaded) async {
    await transaction(() async {
      final current = await (select(notes)
            ..where((n) =>
                n.id.equals(uploaded.id) & n.owner.equals(uploaded.owner)))
          .getSingleOrNull();
      // Do not resolve an older snapshot over newer local user input.
      if (current == null || !current.dirty ||
          current.revision != uploaded.revision) {
        return;
      }
      final conflictTitle = current.title.length > 175
          ? current.title.substring(0, 175)
          : current.title;
      await into(notes).insert(NotesCompanion.insert(
        id: const Uuid().v4(),
        owner: current.owner,
        title: '$conflictTitle (bản xung đột)',
        body: current.body,
        pinned: Value(current.pinned),
        deleted: const Value(false),
        dirty: const Value(true),
        revision: const Value(1),
        serverRevision: const Value(0),
        updatedAt: DateTime.now().toUtc(),
      ));
      // Keep the original row so the cloud version can replace it on pull.
      await (update(notes)
            ..where((n) =>
                n.id.equals(current.id) & n.owner.equals(current.owner)))
          .write(const NotesCompanion(dirty: Value(false)));
    });
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
            serverRevision: Value((row['revision'] as num).toInt()),
            updatedAt: DateTime.parse(row['updated_at'] as String),
          ),
        );
      });
}
