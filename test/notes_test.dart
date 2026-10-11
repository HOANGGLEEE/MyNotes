import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mynotes/database.dart';
import 'package:mynotes/main.dart';

void main() {
  test(
    'pending edits survive stale acknowledgements and remote merges',
    () async {
      final db = NoteDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.save('alice', 'First', 'offline');
      final first = (await db.pending('alice')).single;
      await db.save('alice', 'Second', 'new edit', previous: first);
      await db.acknowledge(first);
      expect((await db.pending('alice')).single.title, 'Second');
      await db.merge('alice', {
        'id': first.id,
        'user_id': 'alice',
        'title': 'Remote',
        'body': '',
        'pinned': false,
        'deleted': false,
        'updated_at': DateTime.now().toIso8601String(),
      });
      expect((await db.pending('alice')).single.title, 'Second');
      expect(await db.watchNotes('bob').first, isEmpty);
      final current = (await db.pending('alice')).single;
      await db.save(
        'alice',
        current.title,
        current.body,
        previous: current,
        deleted: true,
      );
      expect(await db.watchNotes('alice').first, isEmpty);
      expect((await db.pending('alice')).single.deleted, isTrue);
      await expectLater(
        db.merge('alice', {'user_id': 'bob'}),
        throwsStateError,
      );
    },
  );
  testWidgets('Create and search a note', (tester) async {
    final db = NoteDatabase(NativeDatabase.memory());
    await tester.runAsync(() => db.customSelect('select 1').get());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MyNotesApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghi chú mới'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Ý tưởng');
    await tester.enterText(find.byType(TextField).at(2), 'Nội dung của tôi');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Ý tưởng'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'không tồn tại');
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy ghi chú.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    // Drift schedules stream cleanup; keep it outside the fake widget clock.
    await tester.runAsync(db.close);
  });
}
