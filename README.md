# OffersBucket

OffersBucket is a local-first Flutter app for keeping coupons, promotions, and personal offers in one searchable bucket.

## Current MVP

- Android and iOS Flutter project
- MotoMall-inspired charcoal/white visual system, geometric typography, and responsive coupon grids
- Home dashboard with featured offer and active offer count
- Search across brand, title, and category
- Category filters and expiry/newest/brand sorting
- Add custom offers with promo code and expiry date
- Store original notification text and view it in offer details
- Android notification and email-preview capture from explicitly allowed apps
- Installed-app allowlist with capture disabled by default
- Review captured messages before saving them as offers
- Explore web deals by searching brand, product, or category
- Favorite offers
- Archive expired offers
- Local persistence on device through `shared_preferences`
- Settings surface for expiry reminders and compact cards
- Local expiry reminders scheduled one day before coupon expiry

## Run

### Visual styling

Shared styling lives in `lib/theme/app_theme.dart` and `lib/widgets/`.
The design follows MotoMall's light-gray grid background, charcoal pill buttons,
rounded white panels, and bold/light wordmark while retaining OffersBucket branding.
Manrope is bundled for offline use under the SIL Open Font License
(`assets/fonts/OFL.txt`); it is a geometric alternative to MotoMall's commercial
Gilroy font. Exact Gilroy matching requires licensed app-embedding font files.
The editable logo source is `assets/branding/offersbucket_mark.svg`, with launcher
icons supplied for Android, iOS, and macOS.

```bash
flutter pub get
flutter run
```

`flutter run` creates a debug build. Debug APKs can be very large because they contain the Dart VM and multiple CPU architectures. Do not use that APK for distribution.

Android distribution builds (configure production signing before uploading to Google Play):

```bash
# Preferred for Google Play; Play delivers the correct ABI per device.
flutter build appbundle --release

# Direct APK distribution; creates one small APK per CPU architecture.
flutter build apk --release --split-per-abi
```

Measured on October 25, 2026 (MB = 1,000,000 bytes): existing debug universal APK
181.90 MB; existing release universal APK 56.93 MB. Newly built release APKs:

- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`: 20.21 MB, for devices supporting ARM64 (most current phones).
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`: 17.69 MB, for devices supporting 32-bit ARM.
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`: 21.67 MB, for x86-64 devices/emulators.

Install only the APK matching the device's CPU architecture. These APKs require
Android 7.0 (API 24) or newer. ARM64 is approximately 65% smaller than the
universal release, with notification capture and other app features retained.
All three APKs passed signature verification and archive-integrity checks;
installation and notification capture on a physical device remain unverified.

### Android signing and Play Protect

`android/app/build.gradle.kts` currently signs release builds with the local
Android debug key. The APKs have valid signatures, but are not production-signed
or ready for a Play test-track upload. Configure a private release/upload
keystore and Play App Signing before publishing. Keep keystores and passwords
out of source control. A different signing key cannot update an existing
differently-signed installation; back up app data before replacing that install.

Notification capture declares `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE`.
Google Play Protect can block APKs declaring this permission when installed from
a browser, messaging app, or file manager in affected markets. The warning may
say, "This app can request access to sensitive data. This can increase the risk
of identity theft or financial fraud." Turning capture off in the app, reducing
APK size, or changing the signing key alone does not remove this declared
permission or resolve that block.

Notification capture is a core feature and remains enabled as an available,
opt-in capability. Use Google Play testing/distribution with the required
privacy disclosures and consent, or appeal an incorrect Play Protect
classification after reviewing Google's guidance. Do not disable Play Protect.
Account registration alone does not clear a sideload warning or guarantee app
approval.

- [Play Console registration](https://support.google.com/googleplay/android-developer/answer/6112435): US$25 one-time fee and account verification.
- [Play testing options](https://developer.android.com/guide/app-bundle/test#test_on_play): start with internal testing rather than a public release.
- [Play Protect developer guidance and appeals](https://developers.google.com/android/play-protect/warning-dev-guidance).

Local development on your own test device with `flutter run` does not require a
paid Play Console account.

Enable email account and sync after creating a Supabase project:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Run [`supabase/schema.sql`](supabase/schema.sql) in Supabase SQL Editor first. Without these defines, OffersBucket stays local-only and still works offline.

Checks:

```bash
flutter analyze
flutter test
```

## Android notification capture

1. Open **Settings → App & email notifications**.
2. Open Android notification access settings and enable OffersBucket.
3. Select allowed apps. Gmail, Outlook, and other mail apps are listed when
   installed; selecting one captures only its Android notification previews.
4. Turn on **Capture notifications**.
5. Review captured messages and save useful ones as offers.

Capture is deny-by-default, local-only, and limited to selected packages. The
feature does not read email inboxes or fetch full email bodies. iOS cannot read
notifications generated by other apps, so iOS continues to support manual or
shared-text entry instead.

If notification access is not granted at startup, OffersBucket shows a warning
and continues in custom-coupon-only mode. Use **Settings → App & email
notifications → Grant again** to retry Android permission access later.

Explore uses the public read-only Actually Useful Deals API. It requires no API
key or account. Search results are external deals, not automatically saved
coupons; open the merchant page and verify price, availability, and terms.

Expiry reminders request device notification permission, then schedule one local
reminder per active coupon for one day before expiry. Disabling the setting
cancels pending reminders. Reminders are rescheduled when coupons are added or
imported.

## Google Drive app-only backup access

Load from Google Drive uses Google's `drive.appdata` scope. OffersBucket can
read only files in its own hidden application-data folder; it cannot browse or
read the user's normal Drive files. Google sign-in opens Google's account
chooser and never asks for a Gmail password inside the app.

Create OAuth client IDs in Google Cloud and enable the Google Drive API. Pass
the client IDs when running the app:

```bash
flutter run \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID \
  --dart-define=GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID
```

Android needs the web OAuth client ID and the Android app registration with the
correct package name and signing SHA. iOS and macOS need the platform client ID
plus its reversed client ID as a URL scheme in their respective `Info.plist`
files; the project includes the current scheme and the
`google_sign_in_ios` integration guide describes this URL-scheme entry.

Settings provides **Save to Google Drive** and **Load from Google Drive**.
Save creates or updates `offersbucket-backup.json` in the app-only folder;
Load reads the newest backup from that same folder.

## Product architecture

See [`docs/architecture.md`](docs/architecture.md) for the local-first data flow, Supabase sync plan, and notification capture constraints.

The initial Supabase schema is in [`supabase/schema.sql`](supabase/schema.sql).
