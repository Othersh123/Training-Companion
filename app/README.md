# Training Companion: the Flutter app

See the [project README](../README.md) for what it does and why, and [docs/HOW-IT-WORKS.md](../docs/HOW-IT-WORKS.md) for how it fits together.

```bash
flutter test
flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=dart_defines.json
```

`dart_defines.json` holds your Google Web client ID for Drive backup (copy `dart_defines.example.json`). It's git-ignored; without it the app builds with backup switched off.
