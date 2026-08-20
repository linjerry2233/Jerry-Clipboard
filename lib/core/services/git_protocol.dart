/// Git Wire Protocol 核心实现
///
/// 实现 pkt-line 编解码、Git 对象模型（blob/tree/commit）、
/// packfile 解析与生成。用于 Android 端通过 SSH 通道进行 Git 同步，
/// 替代系统 Git CLI。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart'
    show ByteOrder, Inflate, InputMemoryStream, getAdler32;
import 'package:crypto/crypto.dart';

/// Pure planning rules shared by the Git CLI and SSH transports.
///
/// Ciphertext cannot be used as a change detector because AES-GCM creates a
/// fresh nonce for every encryption.  A matching plaintext digest means the
/// existing Git blob is authoritative and can be reused verbatim.
class GitSyncIndexPlanner {
  const GitSyncIndexPlanner._();

  static GitSyncBlobPlan planEntry({
    required String? remoteBlobSha,
    required String? remoteDigest,
    required String localDigest,
  }) {
    final reusable =
        remoteBlobSha != null &&
        remoteBlobSha.isNotEmpty &&
        remoteDigest != null &&
        remoteDigest == localDigest;
    return GitSyncBlobPlan(
      reuseRemoteBlob: reusable,
      createBlob: !reusable,
      blobSha: reusable ? remoteBlobSha : null,
    );
  }

  /// A single Git commit is the transaction boundary for payloads, tombstones
  /// and the encrypted index.  Keeping this list explicit also makes it hard
  /// for a future caller to accidentally commit an index independently.
  static Set<String> transactionPaths({
    required Iterable<String> dataPaths,
    required Iterable<String> tombstonePaths,
  }) => <String>{...dataPaths, ...tombstonePaths, 'meta/sync_index.json'};

  static String indexKey(String dataType, String syncId) => '$dataType/$syncId';

  static String payloadPath(String dataType, String syncId) =>
      '${indexKey(dataType, syncId)}.json';
}

class GitSyncBlobPlan {
  final bool reuseRemoteBlob;
  final bool createBlob;
  final String? blobSha;

  const GitSyncBlobPlan({
    required this.reuseRemoteBlob,
    required this.createBlob,
    required this.blobSha,
  });
}

// ============ Pkt-Line 编解码 ============

/// Pkt-Line 数据包
class PktLine {
  /// 数据内容，null 表示 flush-pkt
  final List<int>? data;

  const PktLine(this.data);

  bool get isFlush => data == null;

  /// 编码为 wire 格式
  ///
  /// 普通数据：`<4位十六进制长度><data>`
  /// flush-pkt：`0000`
  List<int> encode() {
    if (data == null) return [0x30, 0x30, 0x30, 0x30]; // '0000'
    final payload = data!;
    final length = payload.length + 4;
    final hex = length.toRadixString(16).padLeft(4, '0');
    return [...utf8.encode(hex), ...payload];
  }

  /// 编码字符串（自动添加 LF）
  static List<int> encodeString(String s) {
    final bytes = utf8.encode('$s\u000a');
    return PktLine(bytes).encode();
  }

  @override
  String toString() =>
      isFlush ? 'PktLine(flush)' : 'PktLine(${utf8.decode(data!)})';
}

/// Builds a shallow upload-pack request for the current tip. The deepen command
/// is part of the want phase; the flush terminates that command list and limits
/// the server response to the latest commit/tree/blob set instead of history.
List<int> buildShallowWantPacket(String sha) {
  final wantLine = PktLine.encodeString('want $sha no-progress');
  final deepenLine = PktLine.encodeString('deepen 1');
  final flush = const PktLine(null).encode();
  final doneLine = PktLine.encodeString('done');
  return [...wantLine, ...deepenLine, ...flush, ...doneLine];
}

/// 从字节流中读取 pkt-line
Iterable<PktLine> parsePktLines(List<int> input) sync* {
  var offset = 0;
  while (offset < input.length) {
    if (offset + 4 > input.length) break;
    final hex = utf8.decode(input.sublist(offset, offset + 4));
    final length = int.tryParse(hex, radix: 16);
    if (length == null || length == 0) {
      yield const PktLine(null);
      offset += 4;
      continue;
    }
    if (length < 4) break;
    final dataLength = length - 4;
    if (offset + 4 + dataLength > input.length) break;
    yield PktLine(input.sublist(offset + 4, offset + 4 + dataLength));
    offset += length;
  }
}

// ============ Git 对象模型 ============

/// Git 对象类型
enum GitObjectType {
  commit(1),
  tree(2),
  blob(3),
  tag(4);

  final int packType;
  const GitObjectType(this.packType);

  static GitObjectType fromPackType(int t) =>
      GitObjectType.values.firstWhere((e) => e.packType == t);
}

/// Git 对象基类
abstract class GitObject {
  GitObjectType get type;
  List<int> get content;

  /// 序列化为 Git 对象格式：`<type> <size>\0<content>`
  List<int> serialize() {
    final header = utf8.encode('${type.name} ${content.length}\u0000');
    return [...header, ...content];
  }

  /// 计算 SHA1 哈希（40 字符十六进制）
  String get sha1Hex => sha1.convert(serialize()).toString();

  /// 获取 20 字节二进制 SHA1
  Uint8List get sha1Bytes =>
      Uint8List.fromList(sha1.convert(serialize()).bytes);
}

/// Git Blob 对象（文件内容）
class GitBlob extends GitObject {
  @override
  final GitObjectType type = GitObjectType.blob;
  final List<int> _content;

  GitBlob(this._content);

  @override
  List<int> get content => _content;

  factory GitBlob.fromString(String s) => GitBlob(utf8.encode(s));
  String get asString => utf8.decode(content);
}

/// Tree entry 条目
class TreeEntry {
  final String mode; // '100644' 或 '40000'
  final String name;
  final Uint8List sha1Bytes; // 20 字节

  const TreeEntry({
    required this.mode,
    required this.name,
    required this.sha1Bytes,
  });

  bool get isDirectory => mode == '40000';
}

/// Git Tree 对象（目录结构）
class GitTree extends GitObject {
  @override
  final GitObjectType type = GitObjectType.tree;
  final List<TreeEntry> entries;

  GitTree(this.entries);

  @override
  List<int> get content {
    final builder = BytesBuilder();
    // tree entries 必须按名称排序
    final sorted = List<TreeEntry>.from(entries)
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final entry in sorted) {
      builder.add(utf8.encode('${entry.mode} ${entry.name}\u0000'));
      builder.add(entry.sha1Bytes);
    }
    return builder.toBytes();
  }

  TreeEntry? find(String name) {
    for (final e in entries) {
      if (e.name == name) return e;
    }
    return null;
  }
}

/// Git Commit 对象
class GitCommit extends GitObject {
  @override
  final GitObjectType type = GitObjectType.commit;
  final Uint8List treeSha1;
  final Uint8List? parentSha1;
  final String author;
  final String committer;
  final String message;

  GitCommit({
    required this.treeSha1,
    this.parentSha1,
    required this.author,
    required this.committer,
    required this.message,
  });

  @override
  List<int> get content {
    final builder = BytesBuilder();
    builder.add(utf8.encode('tree ${bytesToHex(treeSha1)}\u000a'));
    if (parentSha1 != null) {
      builder.add(utf8.encode('parent ${bytesToHex(parentSha1!)}\u000a'));
    }
    builder.add(utf8.encode('author $author\u000a'));
    builder.add(utf8.encode('committer $committer\u000a'));
    builder.add(utf8.encode('\u000a$message\u000a'));
    return builder.toBytes();
  }
}

// ============ Packfile 解析 ============

/// Packfile 中解析出的对象
class PackedObject {
  final GitObjectType type;
  final List<int> data;

  const PackedObject({required this.type, required this.data});
}

/// 内部：delta 记录
class _DeltaRecord {
  final List<int> deltaData;
  final int packOffset;
  final int? basePackOffset; // ofs_delta: base 在 packfile 中的偏移
  final String? baseShaHex; // ref_delta: base 的 SHA1

  _DeltaRecord({
    required this.deltaData,
    required this.packOffset,
    this.basePackOffset,
    this.baseShaHex,
  });
}

/// 解析 packfile
class PackfileParser {
  final Uint8List _data;
  int _offset = 0;

  // packOffset → SHA1 hex（用于 ofs_delta 查找 base）
  final Map<int, String> _offsetToSha = {};

  PackfileParser(this._data);

  /// 解析并返回所有对象（SHA1 hex → 对象）
  Map<String, PackedObject> parse() {
    final objects = <String, PackedObject>{};
    final deltas = <_DeltaRecord>[];

    final sig = utf8.decode(_data.sublist(0, 4));
    if (sig != 'PACK') throw FormatException('无效 packfile 签名: $sig');
    _offset = 4;
    final version = _readUint32();
    if (version != 2) throw FormatException('不支持的 packfile 版本: $version');
    final numObjects = _readUint32();

    for (var i = 0; i < numObjects; i++) {
      final objStart = _offset;
      final result = _readObject();
      if (result is _DeltaRecord) {
        deltas.add(result);
      } else if (result is PackedObject) {
        final sha = _computeObjectSha(result.type, result.data);
        objects[sha] = result;
        _offsetToSha[objStart] = sha;
      }
    }

    // 解析 delta（可能需要多轮，因为 delta 可能依赖另一个 delta）
    var pending = deltas;
    while (pending.isNotEmpty) {
      final unresolved = <_DeltaRecord>[];
      for (final delta in pending) {
        final baseSha = _findBaseSha(delta);
        if (baseSha == null || !objects.containsKey(baseSha)) {
          unresolved.add(delta);
          continue;
        }
        final base = objects[baseSha]!;
        final applied = _applyDelta(base.data, delta.deltaData);
        final resolved = PackedObject(type: base.type, data: applied);
        final sha = _computeObjectSha(resolved.type, resolved.data);
        objects[sha] = resolved;
        _offsetToSha[delta.packOffset] = sha;
      }
      if (unresolved.length == pending.length) {
        throw FormatException(
          'packfile 包含 ${unresolved.length} 个无法解析的 delta 对象；'
          '首个 baseOffset=${unresolved.first.basePackOffset}，'
          'baseSha=${unresolved.first.baseShaHex}，'
          '已知 offset=${_offsetToSha.keys.take(5).toList()}，'
          '已知 SHA=${objects.keys.take(5).toList()}',
        );
      }
      pending = unresolved;
    }

    return objects;
  }

  String? _findBaseSha(_DeltaRecord delta) {
    if (delta.baseShaHex != null) return delta.baseShaHex;
    if (delta.basePackOffset != null) return _offsetToSha[delta.basePackOffset];
    return null;
  }

  int _readUint32() {
    final val =
        _data[_offset] << 24 |
        _data[_offset + 1] << 16 |
        _data[_offset + 2] << 8 |
        _data[_offset + 3];
    _offset += 4;
    return val;
  }

  /// 读取一个对象，返回 PackedObject 或 _DeltaRecord
  Object _readObject() {
    final objectOffset = _offset;
    final firstByte = _data[_offset++];

    final type = (firstByte >> 4) & 0x07;
    var size = firstByte & 0x0F;
    var shift = 4;

    if ((firstByte & 0x80) != 0) {
      var b = _data[_offset++];
      size |= (b & 0x7F) << shift;
      shift += 7;
      while ((b & 0x80) != 0 && shift <= 32) {
        b = _data[_offset++];
        size |= (b & 0x7F) << shift;
        shift += 7;
      }
    }

    if (type == 6) {
      // ofs_delta
      final baseDistance = _readOfsDelta();
      final decompressed = _readZlib(size);
      return _DeltaRecord(
        deltaData: decompressed,
        packOffset: objectOffset,
        basePackOffset: objectOffset - baseDistance,
      );
    } else if (type == 7) {
      // ref_delta
      final baseSha = _data.sublist(_offset, _offset + 20);
      _offset += 20;
      final decompressed = _readZlib(size);
      return _DeltaRecord(
        deltaData: decompressed,
        packOffset: objectOffset,
        baseShaHex: bytesToHex(Uint8List.fromList(baseSha)),
      );
    }

    final decompressed = _readZlib(size);
    return PackedObject(
      type: GitObjectType.fromPackType(type),
      data: decompressed,
    );
  }

  int _readOfsDelta() {
    var b = _data[_offset++];
    var offset = b & 0x7F;
    while ((b & 0x80) != 0) {
      offset += 1;
      b = _data[_offset++];
      offset = (offset << 7) | (b & 0x7F);
    }
    return offset;
  }

  /// 解压 zlib 数据并推进 offset
  ///
  /// 使用一次流式 DEFLATE 解析读取一个 zlib 流，并按输入流实际消费的
  /// 字节数推进 offset。
  ///
  /// 之前通过二分搜索反复解压 packfile 的剩余部分，时间和内存开销会随
  /// 仓库对象数快速放大，在 Android 上表现为拉取长期无响应。
  List<int> _readZlib(int expectedSize) {
    final input = InputMemoryStream(
      Uint8List.sublistView(_data, _offset),
      byteOrder: ByteOrder.bigEndian,
    );
    final cmf = input.readByte();
    final flg = input.readByte();
    if ((cmf & 0x0f) != 8 || ((cmf << 8) + flg) % 31 != 0) {
      throw const FormatException('无效的 zlib 数据头');
    }
    if ((flg & 0x20) != 0) {
      throw const FormatException('不支持带预置字典的 zlib 数据');
    }

    final decompressed = Inflate.stream(
      input,
      uncompressedSize: expectedSize,
    ).getBytes();
    if (input.length < 4) {
      throw const FormatException('zlib 数据缺少 Adler-32 校验值');
    }
    final expectedAdler32 = input.readUint32();
    final actualAdler32 = getAdler32(decompressed);
    if (actualAdler32 != expectedAdler32) {
      throw FormatException(
        'zlib Adler-32 校验失败：期望 $expectedAdler32，实际 $actualAdler32',
      );
    }
    if (decompressed.length != expectedSize) {
      throw FormatException(
        'Git 对象解压长度不匹配：期望 $expectedSize，实际 ${decompressed.length}',
      );
    }

    _offset += input.position;
    return decompressed;
  }

  /// 应用 delta 指令
  List<int> _applyDelta(List<int> base, List<int> delta) {
    var pos = 0;

    final sourceSizeResult = _readDeltaSize(delta, pos);
    final sourceSize = sourceSizeResult.$1;
    pos = sourceSizeResult.$2;
    if (sourceSize != base.length) {
      throw FormatException('delta 基对象长度不匹配：期望 $sourceSize，实际 ${base.length}');
    }

    final targetSizeResult = _readDeltaSize(delta, pos);
    final targetSize = targetSizeResult.$1;
    pos = targetSizeResult.$2;

    final result = <int>[];

    while (pos < delta.length) {
      final op = delta[pos++];
      if ((op & 0x80) != 0) {
        // Copy 指令
        var copyOffset = 0;
        var copySize = 0;

        if ((op & 0x01) != 0) copyOffset |= delta[pos++];
        if ((op & 0x02) != 0) copyOffset |= delta[pos++] << 8;
        if ((op & 0x04) != 0) copyOffset |= delta[pos++] << 16;
        if ((op & 0x08) != 0) copyOffset |= delta[pos++] << 24;

        if ((op & 0x10) != 0) copySize |= delta[pos++];
        if ((op & 0x20) != 0) copySize |= delta[pos++] << 8;
        if ((op & 0x40) != 0) copySize |= delta[pos++] << 16;

        if (copySize == 0) copySize = 0x10000;

        result.addAll(base.sublist(copyOffset, copyOffset + copySize));
      } else if (op > 0) {
        // Add 指令
        result.addAll(delta.sublist(pos, pos + op));
        pos += op;
      }
    }

    if (result.length != targetSize) {
      throw FormatException('delta 结果长度不匹配：期望 $targetSize，实际 ${result.length}');
    }
    return result;
  }

  (int, int) _readDeltaSize(List<int> delta, int start) {
    var pos = start;
    var value = 0;
    var shift = 0;
    while (true) {
      if (pos >= delta.length) {
        throw const FormatException('delta 长度字段被截断');
      }
      final byte = delta[pos++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return (value, pos);
      shift += 7;
      if (shift > 63) throw const FormatException('delta 长度字段过大');
    }
  }

  String _computeObjectSha(GitObjectType type, List<int> data) {
    final header = utf8.encode('${type.name} ${data.length}\u0000');
    return sha1.convert([...header, ...data]).toString();
  }
}

// ============ Packfile 生成 ============

/// Packfile 写入时的对象条目
class PackObjectEntry {
  final GitObjectType type;
  final List<int> content;

  const PackObjectEntry({required this.type, required this.content});
}

/// 生成 packfile
class PackfileWriter {
  static List<int> write(List<PackObjectEntry> objects) {
    final builder = BytesBuilder();

    // Header
    builder.add(utf8.encode('PACK'));
    _writeUint32(builder, 2);
    _writeUint32(builder, objects.length);

    for (final obj in objects) {
      _writeObject(builder, obj);
    }

    // SHA1 trailer
    final data = builder.toBytes();
    final digest = sha1.convert(data);
    return [...data, ...digest.bytes];
  }

  static void _writeUint32(BytesBuilder builder, int value) {
    builder.add([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  static void _writeObject(BytesBuilder builder, PackObjectEntry obj) {
    final type = obj.type.packType;
    var size = obj.content.length;

    var firstByte = (type << 4) | (size & 0x0F);
    size >>= 4;
    if (size > 0) firstByte |= 0x80;
    builder.addByte(firstByte);

    while (size > 0) {
      var b = size & 0x7F;
      size >>= 7;
      if (size > 0) b |= 0x80;
      builder.addByte(b);
    }

    // zlib 压缩内容
    final compressed = ZLibEncoder().convert(obj.content);
    builder.add(compressed);
  }
}

/// Isolate entry point for packfile compression.  The payload deliberately
/// contains only primitive values and byte lists so it can cross an isolate
/// boundary on Android without sending Git model objects.
List<int> writePackfilePayload(List<List<dynamic>> payload) {
  final objects = payload
      .map(
        (entry) => PackObjectEntry(
          type: GitObjectType.fromPackType(entry[0] as int),
          content: List<int>.from(entry[1] as List),
        ),
      )
      .toList(growable: false);
  return PackfileWriter.write(objects);
}

// ============ 辅助函数 ============

/// 20 字节二进制 SHA1 → 40 字符十六进制字符串
String bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 40 字符十六进制 SHA1 → 20 字节二进制
Uint8List hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}

/// 解析 tree 对象内容
List<TreeEntry> parseTreeContent(List<int> content) {
  final entries = <TreeEntry>[];
  var pos = 0;

  while (pos < content.length) {
    final spacePos = _indexOfByte(content, 0x20, pos);
    if (spacePos < 0) break;
    final mode = utf8.decode(content.sublist(pos, spacePos));

    final nullPos = _indexOfByte(content, 0x00, spacePos + 1);
    if (nullPos < 0) break;
    final name = utf8.decode(content.sublist(spacePos + 1, nullPos));

    final sha1 = Uint8List.fromList(content.sublist(nullPos + 1, nullPos + 21));

    entries.add(TreeEntry(mode: mode, name: name, sha1Bytes: sha1));
    pos = nullPos + 21;
  }

  return entries;
}

/// 解析 git-receive-pack 的 report-status 响应。
///
/// 成功引用行的格式是 `ok refs/heads/<branch>`。
bool parseReceivePackStatus(List<int> buffer) {
  var offset = 0;
  var unpackOk = false;
  var refOk = false;
  try {
    while (offset < buffer.length) {
      if (offset + 4 > buffer.length) break;
      final hex = String.fromCharCodes(buffer.sublist(offset, offset + 4));
      final length = int.tryParse(hex, radix: 16);
      if (length == null) break;
      if (length == 0) {
        offset += 4;
        continue;
      }
      if (length < 4 || offset + length > buffer.length) break;
      final payload = buffer.sublist(offset + 4, offset + length);
      final content =
          payload.isNotEmpty && payload[0] >= 0x01 && payload[0] <= 0x03
          ? payload.sublist(1)
          : payload;
      final line = utf8.decode(content, allowMalformed: true).trim();
      if (line == 'unpack ok') unpackOk = true;
      if (line.startsWith('ok ') && line.contains('refs/')) refOk = true;
      if (line.startsWith('ng ')) return false;
      offset += length;
    }
    return unpackOk && refOk;
  } catch (_) {
    return false;
  }
}

/// 解析 commit 对象，提取 tree SHA1
String? parseCommitTree(List<int> content) {
  final text = utf8.decode(content);
  final match = RegExp(
    r'^tree ([0-9a-f]{40})',
    multiLine: true,
  ).firstMatch(text);
  return match?.group(1);
}

/// 解析 commit 对象，提取 parent SHA1
String? parseCommitParent(List<int> content) {
  final text = utf8.decode(content);
  final match = RegExp(
    r'^parent ([0-9a-f]{40})',
    multiLine: true,
  ).firstMatch(text);
  return match?.group(1);
}

int _indexOfByte(List<int> data, int byte, int from) {
  for (var i = from; i < data.length; i++) {
    if (data[i] == byte) return i;
  }
  return -1;
}
