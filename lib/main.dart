import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database.dart';
import 'sync.dart';

final databaseProvider = Provider<NoteDatabase>((ref) {
  final db = NoteDatabase();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});
final clientProvider = Provider<SupabaseClient?>((ref) => null);
final syncProvider = Provider<NoteSync>((ref) {
  final sync = NoteSync(ref.watch(databaseProvider), ref.watch(clientProvider));
  ref.onDispose(sync.dispose);
  return sync;
});
final notesProvider = StreamProvider.family<List<Note>, String>(
  (ref, owner) => ref.watch(databaseProvider).watchNotes(owner),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  SupabaseClient? client;
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: key);
    client = Supabase.instance.client;
  }
  runApp(
    ProviderScope(
      overrides: [clientProvider.overrideWithValue(client)],
      child: const MyNotesApp(),
    ),
  );
}

class MyNotesApp extends StatelessWidget {
  const MyNotesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MyNotes',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff526442)),
      scaffoldBackgroundColor: const Color(0xfff7f8f2),
    ),
    home: const NotesPage(),
  );
}

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});
  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  String query = '';
  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        unawaited(ref.read(syncProvider).sync());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể lưu. Vui lòng thử lại.')),
        );
      }
    }
  }

  Future<void> edit(Note? note) async {
    final owner = ref.read(syncProvider).owner;
    final title = TextEditingController(text: note?.title ?? '');
    final body = TextEditingController(text: note?.body ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note == null ? 'Ghi chú mới' : 'Sửa ghi chú'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Tiêu đề'),
                ),
                TextField(
                  controller: body,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 100000,
                  decoration: const InputDecoration(labelText: 'Nội dung'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (mounted &&
        result == true &&
        (title.text.trim().isNotEmpty || body.text.trim().isNotEmpty)) {
      await perform(
        () => ref
            .read(databaseProvider)
            .save(owner, title.text, body.text, previous: note),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    title.dispose();
    body.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncProvider);
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final data = ref.watch(notesProvider(sync.owner));
        final client = ref.watch(clientProvider);
        return Scaffold(
          appBar: AppBar(
            title: const Text('MyNotes'),
            actions: [
              IconButton(
                tooltip: 'Đồng bộ',
                onPressed: sync.owner == 'local' ? null : sync.sync,
                icon: const Icon(Icons.sync),
              ),
              if (client != null)
                TextButton(
                  onPressed: () async {
                    try {
                      if (sync.owner == 'local') {
                        await client.auth.signInWithOAuth(
                          OAuthProvider.google,
                          redirectTo: 'com.hoang.mynotes://login-callback/',
                        );
                      } else {
                        await client.auth.signOut();
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Không thể kết nối đăng nhập.'),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    sync.owner == 'local' ? 'Đăng nhập Google' : 'Đăng xuất',
                  ),
                ),
              const SizedBox(width: 16),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => edit(null),
            icon: const Icon(Icons.add),
            label: const Text('Ghi chú mới'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Không gian cho ý tưởng của bạn',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(sync.status),
                    if (sync.owner == 'local')
                      const Text(
                        'Ghi chú trên thiết bị được giữ riêng với ghi chú tài khoản.',
                      ),
                    const SizedBox(height: 20),
                    TextField(
                      onChanged: (value) =>
                          setState(() => query = value.toLowerCase()),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Tìm ghi chú',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: data.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, _) => const Center(
                          child: Text('Không thể mở dữ liệu ghi chú.'),
                        ),
                        data: (notes) {
                          final visible = notes
                              .where(
                                (n) => '${n.title}\n${n.body}'
                                    .toLowerCase()
                                    .contains(query),
                              )
                              .toList();
                          if (visible.isEmpty) {
                            return Center(
                              child: Text(
                                query.isEmpty
                                    ? 'Chưa có ghi chú. Hãy ghi lại ý tưởng đầu tiên.'
                                    : 'Không tìm thấy ghi chú.',
                              ),
                            );
                          }
                          return LayoutBuilder(
                            builder: (context, box) => GridView.builder(
                              padding: const EdgeInsets.only(bottom: 90),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: box.maxWidth >= 900
                                        ? 3
                                        : box.maxWidth >= 600
                                        ? 2
                                        : 1,
                                    mainAxisExtent: 240,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final note = visible[index];
                                return Card(
                                  child: InkWell(
                                    onTap: () => edit(note),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            note.title.isEmpty
                                                ? 'Không có tiêu đề'
                                                : note.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge,
                                          ),
                                          const SizedBox(height: 12),
                                          Expanded(
                                            child: Text(
                                              note.body,
                                              maxLines: 5,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              Text(
                                                '${note.updatedAt.day}/${note.updatedAt.month}/${note.updatedAt.year}',
                                              ),
                                              const Spacer(),
                                              IconButton(
                                                tooltip: note.pinned
                                                    ? 'Bỏ ghim'
                                                    : 'Ghim',
                                                icon: Icon(
                                                  note.pinned
                                                      ? Icons.push_pin
                                                      : Icons.push_pin_outlined,
                                                ),
                                                onPressed: () => perform(
                                                  () => ref
                                                      .read(databaseProvider)
                                                      .save(
                                                        note.owner,
                                                        note.title,
                                                        note.body,
                                                        previous: note,
                                                        pinned: !note.pinned,
                                                      ),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Ẩn ghi chú',
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                                onPressed: () async {
                                                  final confirmed =
                                                      await showDialog<bool>(
                                                        context: context,
                                                        builder: (context) => AlertDialog(
                                                          title: const Text(
                                                            'Ẩn ghi chú này?',
                                                          ),
                                                          content: const Text(
                                                            'Nội dung vẫn được giữ trong cơ sở dữ liệu.',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    false,
                                                                  ),
                                                              child: const Text(
                                                                'Hủy',
                                                              ),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    true,
                                                                  ),
                                                              child: const Text(
                                                                'Đồng ý',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                  if (mounted &&
                                                      confirmed == true) {
                                                    await perform(
                                                      () => ref
                                                          .read(
                                                            databaseProvider,
                                                          )
                                                          .save(
                                                            note.owner,
                                                            note.title,
                                                            note.body,
                                                            previous: note,
                                                            deleted: true,
                                                          ),
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
