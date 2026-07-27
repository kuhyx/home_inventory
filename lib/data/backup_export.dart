/// Platform entry point for the explicit "Export inventory" action.
///
/// Conditional export because `dart:io` is unusable in a browser, and because
/// the three hosts genuinely disagree about what "save a file" means: Android
/// has no save dialog at all (`file_selector_android` implements only the open
/// side), a `dart:io` desktop gets a real save dialog, and the browser can only
/// hand the bytes to its download manager.
///
/// Importing is *not* here: `openFile` is implemented on every platform, so it
/// needs no seam.
library;

export 'backup_export_io.dart'
    if (dart.library.js_interop) 'backup_export_web.dart';
