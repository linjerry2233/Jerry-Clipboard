import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/git_protocol.dart';

void main() {
  test('PktLine appends an LF control byte', () {
    final encoded = PktLine.encodeString('done');
    expect(encoded, <int>[
      0x30,
      0x30,
      0x30,
      0x39,
      0x64,
      0x6f,
      0x6e,
      0x65,
      0x0a,
    ]);
  });

  test('shallow fetch request asks only for the current tip', () {
    const head = '0123456789abcdef0123456789abcdef01234567';
    final lines = parsePktLines(buildShallowWantPacket(head)).toList();
    expect(utf8.decode(lines[0].data!), 'want $head no-progress\n');
    expect(utf8.decode(lines[1].data!), 'deepen 1\n');
    expect(lines[2].isFlush, isTrue);
    expect(utf8.decode(lines[3].data!), 'done\n');
  });

  test('receive-pack accepts standard ok ref status order', () {
    final response = <int>[
      ...PktLine(utf8.encode('unpack ok\n')).encode(),
      ...PktLine(utf8.encode('ok refs/heads/main\n')).encode(),
      ...const PktLine(null).encode(),
    ];
    expect(parseReceivePackStatus(response), isTrue);
  });

  test('receive-pack rejects an ng ref status', () {
    final response = <int>[
      ...PktLine(utf8.encode('unpack ok\n')).encode(),
      ...PktLine(utf8.encode('ng refs/heads/main protected branch\n')).encode(),
      ...const PktLine(null).encode(),
    ];
    expect(parseReceivePackStatus(response), isFalse);
  });

  test('an orphan commit has no parent and points at the empty tree', () {
    final emptyTree = GitTree([]);
    final commit = GitCommit(
      treeSha1: emptyTree.sha1Bytes,
      author: 'Jerry Test <test@example.invalid> 0 +0000',
      committer: 'Jerry Test <test@example.invalid> 0 +0000',
      message: 'clear history',
    );
    expect(parseCommitParent(commit.content), isNull);
    expect(parseCommitTree(commit.content), emptyTree.sha1Hex);
  });

  test('packfile isolate payload preserves the regular writer output', () {
    final objects = <PackObjectEntry>[
      PackObjectEntry(
        type: GitObjectType.blob,
        content: utf8.encode('clipboard payload'),
      ),
      PackObjectEntry(type: GitObjectType.tree, content: <int>[1, 2, 3, 4]),
    ];
    final payload = objects
        .map((object) => <dynamic>[object.type.packType, object.content])
        .toList(growable: false);

    expect(writePackfilePayload(payload), PackfileWriter.write(objects));
  });

  test('packfile payload is sendable to a background isolate', () async {
    final payload = <List<dynamic>>[
      <dynamic>[GitObjectType.blob.packType, utf8.encode('background payload')],
    ];
    final result = await Isolate.run(() => writePackfilePayload(payload));
    expect(result, isNotEmpty);
    expect(utf8.decode(result.sublist(0, 4)), 'PACK');
  });

  test('planner identifies payload files separately from index keys', () {
    expect(
      GitSyncIndexPlanner.indexKey('clipboard', 'item-1'),
      'clipboard/item-1',
    );
    expect(
      GitSyncIndexPlanner.payloadPath('clipboard', 'item-1'),
      'clipboard/item-1.json',
    );
  });

  test(
    'PackfileParser resolves every object in a real delta-compressed pack',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'jerry_git_pack_test_',
      );
      try {
        Future<ProcessResult> git(List<String> arguments) =>
            Process.run('git', arguments, workingDirectory: temp.path);

        expect((await git(['init', '-q'])).exitCode, 0);
        expect((await git(['config', 'user.name', 'Jerry Test'])).exitCode, 0);
        expect(
          (await git([
            'config',
            'user.email',
            'jerry-test@example.invalid',
          ])).exitCode,
          0,
        );

        final lines = List.generate(
          500,
          (index) => 'shared line ${index.toString().padLeft(4, '0')}',
        );
        for (var revision = 0; revision < 12; revision++) {
          lines[revision * 7] = 'changed in revision $revision';
          await File(
            '${temp.path}${Platform.pathSeparator}data.txt',
          ).writeAsString(lines.join('\n'));
          expect((await git(['add', 'data.txt'])).exitCode, 0);
          expect(
            (await git(['commit', '-q', '-m', 'revision $revision'])).exitCode,
            0,
          );
        }

        final expectedResult = await git([
          'rev-list',
          '--objects',
          '--all',
          '--no-object-names',
        ]);
        expect(expectedResult.exitCode, 0);
        final expectedShas = (expectedResult.stdout as String)
            .split(RegExp(r'\s+'))
            .where((value) => value.isNotEmpty)
            .toSet();

        final packProcess = await Process.start('git', [
          'pack-objects',
          '--stdout',
          '--revs',
          '--no-thin',
          '--window=50',
          '--depth=50',
          '--all',
        ], workingDirectory: temp.path);
        await packProcess.stdin.close();
        final packBytes = await packProcess.stdout
            .expand((chunk) => chunk)
            .toList();
        final stderr = await packProcess.stderr
            .transform(SystemEncoding().decoder)
            .join();
        final exitCode = await packProcess.exitCode;
        expect(exitCode, 0, reason: stderr);

        final parsed = PackfileParser(Uint8List.fromList(packBytes)).parse();
        expect(parsed.keys.toSet(), containsAll(expectedShas));
        expect(parsed.length, expectedShas.length);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
}
