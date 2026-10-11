import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mynotes/database.dart';

void main() {
  test('offline notes and pending uploads survive database reopen', () async {
    final dir = await Directory.systemTemp.createTemp('mynotes-test-');
    // Keep the disposable test file; no user data is removed.
    final file = File('${dir.path}/notes.sqlite');
    final first = NoteDatabase(NativeDatabase(file));
    await first.save('local', 'Bền vững', 'Sau khi khởi động lại');
    await first.close();
    final reopened = NoteDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    expect((await reopened.watchNotes('local').first).single.title, 'Bền vững');
    expect(
      (await reopened.pending('local')).single.body,
      'Sau khi khởi động lại',
    );
  });
}
