# CommunityDome — Android Release Signing & Play Store Guide

This covers three changes made on the `fix/post-likes-table-and-release-signing`
branch, and what's still needed from you before Play Store submission.

## 1. What changed

- **`applicationId`/`namespace` changed from `com.example.communitydome` to
  `com.communitydome.app`.** Play Console blocks any `com.example.*`
  package name outright (it's reserved/example namespace) — this had to
  change before submission regardless, and can never change again after
  your first publish, so it was worth deciding deliberately rather than
  discovering it at upload time.
- **`MainActivity.kt` moved** from
  `android/app/src/main/kotlin/com/example/communityhub/` (note: it was
  already inconsistent with the old `com.example.communitydome` package
  it declared — a pre-existing drift, probably from an earlier rename)
  to `android/app/src/main/kotlin/com/communitydome/app/`, with its
  `package` declaration updated to match.
- **Real release signing wired up** in `android/app/build.gradle.kts`:
  a `signingConfigs.release` that reads `android/key.properties`
  (git-ignored — see `key.properties.example`), falling back to debug
  signing if that file doesn't exist yet. Previously `release` was
  hardcoded to `signingConfigs.getByName("debug")`.
- **`.gitignore` fix**: it had no rule at all for `key.properties` or
  `*.jks`/`*.keystore` — a real signing key placed anywhere in this
  tree would have been committable by default.
- **Fixed `post_likes` → `likes`** in four files (separate commit,
  `fix: like/unlike writes to nonexistent post_likes table`) — every
  like/unlike on a post was silently failing.

## 2. What you need to do — in order, some of this blocks the build

**This is the important part: changing applicationId breaks the build
until you complete step 1 below.** The `com.google.gms.google-services`
Gradle plugin fails the build if it can't find a client entry matching
the app's package name in `google-services.json` — and the committed
one is registered to the old `com.example.communitydome`, not the new
`com.communitydome.app`. Don't merge this branch to `main` without
doing this first, or your next build (local or CI) will fail with
"No matching client found for package name."

1. **Firebase**: console.firebase.google.com → your `communitydom-5f0c3`
   project → Project settings → add a new Android app with package name
   `com.communitydome.app` (or edit the existing app's package name if
   Firebase allows that in your case — usually it doesn't, so adding a
   new Android app entry to the same project is the reliable path).
   Download the new `google-services.json` and replace
   `android/app/google-services.json` with it.

2. **Google Sign-In**: register `com.communitydome.app` + the release
   SHA-1 below in Google Cloud Console → APIs & Services → Credentials
   → your Android OAuth 2.0 Client ID (create a new one if needed,
   scoped to the new package name):
   ```
   SHA1:   17:45:B6:D9:E2:A5:E3:6A:04:69:27:44:00:20:BF:3E:D2:32:6D:22
   SHA256: B3:7E:04:8A:7F:DF:F2:50:24:0D:75:FC:55:09:C7:8B:BE:E5:FC:44:5A:FB:72:75:6C:3A:39:DB:1E:A7:50:8E
   ```
   (Same fingerprints as before — this is the same upload keystore,
   only the package name changed.) If you already had a debug SHA-1
   registered for the old package name, register a new entry — release
   builds sign with a different key than debug, so this doesn't
   overwrite anything.

3. **Release keystore**: place `communityhub-release-key.jks`
   (delivered earlier this session) into `android/`, copy
   `android/key.properties.example` to `android/key.properties`, and
   fill in the real password values (also delivered earlier — save
   them to a password manager if you haven't already; they won't be
   shown again). This file is the single most important artifact in
   this project — if it's lost after your first Play Store publish,
   there's no recovery path for that listing.

4. **Verify the build**: `flutter pub get && flutter build appbundle --release`
   should succeed once steps 1 and 3 are done.

## 3. Play Console checklist (unchanged from before)

- Play Console developer account ($25 one-time), if you don't have one.
- Store listing: title, description, icon, feature graphic, screenshots.
- Privacy policy — **already done**: your `gh-pages` branch hosts one
  live at https://ajchemengu-web.github.io/communityhub/, already
  written for CommunityDome and listing the real third-party services
  (Supabase, Google Sign-In, YouTube IFrame API).
- Data Safety form, content rating questionnaire.
- Upload the `.aab`, start on **Internal Testing** before Production.
