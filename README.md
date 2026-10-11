# MyNotes

Flutter Windows/Android, Material 3, Riverpod, Drift SQLite.

## Run offline

Open a new PowerShell terminal so the updated User PATH is loaded:

```powershell
flutter pub get
flutter run -d windows
flutter analyze
flutter test
flutter build windows --release
```

Local notes stay on this device and remain separate from account notes. Notes support create/edit, search, pin and soft hide. Hiding retains content; there is no permanent deletion command.

## Supabase preparation

1. Create/select your Supabase project. Review and apply `supabase/migrations/001_notes.sql` in its SQL editor. It creates a new table; do not run against an existing notes table without reviewing its schema.
2. Enable Google under Authentication > Providers. Keep the Google client secret only in Supabase, never in this app or repository. Configure Google's authorized redirect URI to the Supabase Auth callback shown in the dashboard.
3. Add `com.hoang.mynotes://login-callback/` to Supabase Auth redirect URLs.
4. Copy `supabase.example.json` to `supabase.local.json`. Fill in the project URL and publishable/anon key only. Never use a service-role or secret key. The local config is ignored by git. Public client keys are extractable from an app; RLS is the security boundary.
5. Run `flutter run -d windows --dart-define-from-file=supabase.local.json` or build with the same option.
6. On Windows, after a release build, run `powershell -File scripts/register-oauth.ps1`. This registers the custom protocol under the current user, and refuses to overwrite an existing registration. Register the executable you actually run; rebuilding/moving it requires reviewing the registration. Android intent filter is already included.

Signed-in notes are stored locally by account ID. Writes are queued durably in SQLite and retried on save, manual sync and every 30 seconds. Realtime triggers a refresh; full paginated pulls recover missed events. Soft-delete tombstones are retained. A revision guard avoids clearing a newer local edit when an older upload completes. Pending local edits are preserved during a pull.

Conflict policy: the last write accepted by the server wins across devices. This does not merge concurrent text edits; a later sync can replace another device's version. Server timestamps avoid reliance on client clocks. Offline local notes are not automatically uploaded on login. Local SQLite is not encrypted and is accessible to the Windows user.

## Required live checks

OAuth callback on Windows and Android; two-account RLS isolation (including insert/update); realtime between two devices; offline edits/restart/reconnect; simultaneous edits; sign-out/account switch during upload. These require your actual Supabase project and have not been verified by unit/widget tests.

Documentation: https://supabase.com/docs/guides/auth/social-login/auth-google and https://github.com/llfbandit/app_links/blob/main/doc/README_windows.md

## Verified on 2026-10-11

- SDK moved to `C:\src\flutter`; User PATH deduplicated, previous value saved in `user-path-before.txt`.
- Android command-line tools, Visual Studio Build Tools C++ and Developer Mode configured with installation approval. Flutter uses the existing JDK 21.
- `flutter doctor -v`: no issues found.
- `flutter analyze`: no issues found.
- Three tests passed: widget create/search, offline revision/account safeguards, SQLite persistence after reopen.
- Windows release build succeeded. The executable stayed running for a five-second smoke check and created its SQLite database. Native UI interaction was not manually verified.
- Windows OAuth URI registered for the current release executable. Supabase SQL, OAuth and multi-device sync have not been run against a live project. Android compilation/device testing has not been performed.
