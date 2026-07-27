/// Platform entry point for opening the inventory store.
///
/// A conditional export because `dart:io` cannot even be *imported* in a web
/// compile: Android gets the file-backed store, the Chrome-wrapper desktop
/// build gets IndexedDB.
library;

export 'repository_factory_io.dart'
    if (dart.library.js_interop) 'repository_factory_web.dart';
