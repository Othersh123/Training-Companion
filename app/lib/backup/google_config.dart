/// The Web OAuth client ID from your own Google Cloud project, used as the serverClientId for
/// Google sign-in (Drive backup). It isn't a secret, but it belongs to one person's project,
/// so it's kept out of the repo: put it in `app/dart_defines.json` (git-ignored) as
/// `{"GOOGLE_WEB_CLIENT_ID": "...apps.googleusercontent.com"}` and build with
/// `--dart-define-from-file=dart_defines.json`. Without it the app builds and runs with
/// Drive backup switched off.
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: 'PASTE_YOUR_WEB_CLIENT_ID');
