// This file lets sqflite_common_ffi_web load its IndexedDB worker on web.
// Do not rename or move it; the plugin looks for it at /sqflite_sw.js.
// It forwards to the real worker bundled as a package asset.

// Import the worker script from the package assets path.
// Reference: https://pub.dev/packages/sqflite_common_ffi_web
self.importScripts('assets/packages/sqflite_common_ffi_web/assets/sqflite_sw.js');
