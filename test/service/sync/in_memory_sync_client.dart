import 'dart:io' as io;

import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:dio/dio.dart';

/// File-backed in-memory SyncClientBase for tests: writes go to a local
/// temp directory keyed by remote path, so upload/download round-trips work.
class InMemorySyncClient implements SyncClientBase {
  final io.Directory dir;
  final Map<String, List<int>> files = {};

  InMemorySyncClient(this.dir);

  io.File _file(String path) =>
      io.File('${dir.path}/${path.replaceAll('/', '_')}');

  @override
  Future<void> ping() async {}

  @override
  Future<void> testFullCapabilities() async {}

  @override
  Future<void> mkdirAll(String path) async {}

  @override
  Future<List<RemoteFile>> readDir(String path) async => [];

  @override
  Future<void> remove(String path) async {
    files.remove(path);
    final f = _file(path);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<bool> isExist(String path) async {
    if (files.containsKey(path)) return true;
    return _file(path).existsSync();
  }

  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int sent, int total)? onProgress,
      CancelToken? cancelToken}) async {
    files[remotePath] = await io.File(localPath).readAsBytes();
    await _file(remotePath).writeAsBytes(files[remotePath]!);
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath,
      {void Function(int received, int total)? onProgress}) async {
    await io.File(localPath).writeAsBytes(files[remotePath]!);
  }

  @override
  Future<List<RemoteFile>> safeReadDir(String path) async => [];

  @override
  Future<RemoteFile?> readProps(String path) async => null;

  @override
  String get protocolName => 'InMemory';

  @override
  Map<String, dynamic> get config => {};

  @override
  void updateConfig(Map<String, dynamic> newConfig) {}

  @override
  bool get isConfigured => true;
}
