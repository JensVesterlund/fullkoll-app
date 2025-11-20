import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Hanterar krypterad lagring av uppladdade dokument via FlutterSecureStorage.
class DocumentStorage {
  DocumentStorage._();

  static FlutterSecureStorage? _storageInstance;
  static FlutterSecureStorage get _storage => _storageInstance ??= const FlutterSecureStorage();
  static final Uuid _uuid = const Uuid();
  static const int _maxBytes = 10 * 1024 * 1024; // 10 MB

  /// Sparar ett dokument krypterat och returnerar metadata + bytes.
  static Future<StoredDocument> saveDocument({
    required String ownerId,
    required String module,
    required String originalName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (bytes.length > _maxBytes) {
      throw ArgumentError('File exceeds 10 MB limit');
    }

    final id = _uuid.v4();
    final key = _keyFor(id);
    final createdAt = DateTime.now();
    final payload = {
      'id': id,
      'ownerId': ownerId,
      'module': module,
      'name': originalName,
      'mimeType': mimeType,
      'size': bytes.length,
      'createdAt': createdAt.toIso8601String(),
      'data': base64Encode(bytes),
    };

    await _storage.write(key: key, value: jsonEncode(payload));

    return StoredDocument(
      id: id,
      ownerId: ownerId,
      module: module,
      name: originalName,
      mimeType: mimeType,
      size: bytes.length,
      createdAt: createdAt,
      bytes: bytes,
    );
  }

  /// Hamnar metadata och bytes for ett tidigare sparat dokument.
  static Future<StoredDocument?> fetchDocument(String? url) async {
    if (url == null) return null;
    final id = _extractId(url);
    if (id == null) return null;
    final raw = await _storage.read(key: _keyFor(id));
    if (raw == null) return null;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final data = decoded['data'] as String?;
    if (data == null) return null;

    final bytes = Uint8List.fromList(base64Decode(data));
    return StoredDocument(
      id: decoded['id'] as String,
      ownerId: decoded['ownerId'] as String? ?? '',
      module: decoded['module'] as String? ?? '',
      name: decoded['name'] as String? ?? 'dokument',
      mimeType: decoded['mimeType'] as String? ?? 'application/octet-stream',
      size: decoded['size'] as int? ?? bytes.length,
      createdAt: decoded['createdAt'] != null ? DateTime.parse(decoded['createdAt'] as String) : DateTime.now(),
      bytes: bytes,
    );
  }

  /// Tar bort ett dokument och dess krypterade innehall.
  static Future<void> deleteDocument(String? url) async {
    if (url == null) return;
    final id = _extractId(url);
    if (id == null) return;
    await _storage.delete(key: _keyFor(id));
  }

  /// Anvands av dev-gastlaget for att nollstalla krypterade dokument.
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// Exponerar den interna 10 MB-gransen sa att UI kan validera innan sparning.
  static int get maxBytes => _maxBytes;

  static String _keyFor(String id) => 'doc_$id';

  static String buildUrl(String id) => 'secure://document/$id';

  static String? _extractId(String url) {
    final segments = url.split('/');
    return segments.isNotEmpty ? segments.last : null;
  }
}

class StoredDocument {
  final String id;
  final String ownerId;
  final String module;
  final String name;
  final String mimeType;
  final int size;
  final DateTime createdAt;
  final Uint8List bytes;

  StoredDocument({
    required this.id,
    required this.ownerId,
    required this.module,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.createdAt,
    required this.bytes,
  });

  String get url => DocumentStorage.buildUrl(id);

  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';
}