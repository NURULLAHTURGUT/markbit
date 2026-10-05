import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';
import '../../core/l10n/app_strings.dart';
import '../languages.dart';
import 'execution.dart';

/// A scratch SQLite database shared by this note's blocks until the app closes.
/// Each run opens/closes the connection in a short-lived worker isolate.
class SqlExecutor implements CodeExecutor {
  Future<Directory>? _directory;
  final _jobs = <_SqlJob>{};
  bool _closed = false;
  Future<void>? _closing;
  @override
  String get name => 'Local SQLite';
  @override
  Future<bool> supports(CodeLanguage language) async =>
      language.id == 'sql' && !_closed;

  @override
  Stream<RunEvent> execute(ExecutionRequest request) {
    final job = _SqlJob();
    late StreamController<RunEvent> controller;
    Future<void> run() async {
      _jobs.add(job);
      final timer = Stopwatch()..start();
      try {
        if (_closed) throw const FormatException('SQL session closed');
        controller.add(const RunPhase('Running'));
        final directory = await (_directory ??= Directory.systemTemp.createTemp(
          'markbit-sql-',
        ));
        if (job.cancelled) return;
        final path = p.join(directory.path, 'note.sqlite');
        final code = request.code, timeout = request.timeout.inMilliseconds;
        final address = job.flag.address;
        final result = await _launchSql(path, code, timeout, address);
        if (job.cancelled) return;
        timer.stop();
        if (result['error'] != null) {
          final message = _sqlError(result);
          controller.add(RunOutput('$message\n', isError: true));
          controller.add(
            RunFinished(
              elapsed: timer.elapsed,
              exitCode: 1,
              failure: message,
              timedOut: result['timedOut'] == true,
              cancelled: result['cancelled'] == true,
            ),
          );
        } else {
          controller.add(RunOutput(_sqlOutput(result)));
          controller.add(RunFinished(elapsed: timer.elapsed, exitCode: 0));
        }
      } catch (e) {
        if (!job.cancelled) {
          final message = trs('SQL execution failed: {error}', {'error': '$e'});
          controller.add(RunOutput('$message\n', isError: true));
          controller.add(RunFinished(elapsed: timer.elapsed, failure: message));
        }
      } finally {
        _jobs.remove(job);
        job.finish();
        await controller.close();
      }
    }

    controller = StreamController<RunEvent>(
      onListen: () => unawaited(run()),
      onCancel: () {
        job.cancel();
        return job.done.future;
      },
    );
    return controller.stream;
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    final active = _jobs.toList();
    for (final job in active) {
      job.cancel();
    }
    await Future.wait(active.map((j) => j.done.future));
    final directory = await _directory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class _SqlJob {
  final flag = calloc<Int32>();
  final done = Completer<void>();
  bool cancelled = false, finished = false;
  void cancel() {
    if (!finished) {
      cancelled = true;
      flag.value = 1;
    }
  }

  void finish() {
    finished = true;
    calloc.free(flag);
    done.complete();
  }
}

typedef _Prepare =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Int32,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Utf8>>,
    );
typedef _Step = Int32 Function(Pointer<Void>);
typedef _Int = Int32 Function(Pointer<Void>);
typedef _Text = Pointer<Utf8> Function(Pointer<Void>);
typedef _ColumnInt = Int32 Function(Pointer<Void>, Int32);
typedef _ColumnText = Pointer<Utf8> Function(Pointer<Void>, Int32);
typedef _ColumnInteger = Int64 Function(Pointer<Void>, Int32);
typedef _ColumnDouble = Double Function(Pointer<Void>, Int32);
typedef _Progress = Int32 Function(Pointer<Void>);
typedef _SetProgress =
    Void Function(
      Pointer<Void>,
      Int32,
      Pointer<NativeFunction<_Progress>>,
      Pointer<Void>,
    );
typedef _Authorize =
    Int32 Function(
      Pointer<Void>,
      Int32,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _SetAuthorize =
    Int32 Function(
      Pointer<Void>,
      Pointer<NativeFunction<_Authorize>>,
      Pointer<Void>,
    );

// Capture only transferable arguments, never the executor or stream controller.
Future<Map<String, dynamic>> _launchSql(
  String path,
  String sql,
  int timeoutMs,
  int flagAddress,
) => Isolate.run(() => _runSql(path, sql, timeoutMs, flagAddress));

Map<String, dynamic> _runSql(
  String path,
  String sql,
  int timeoutMs,
  int flagAddress,
) {
  Database? db;
  NativeCallable<_Progress>? progress;
  NativeCallable<_Authorize>? authorizer;
  Pointer<Utf8>? source;
  Pointer<Pointer<Void>>? statement;
  Pointer<Pointer<Utf8>>? tail;
  int Function(Pointer<Void>)? finalize;
  void Function(
    Pointer<Void>,
    int,
    Pointer<NativeFunction<_Progress>>,
    Pointer<Void>,
  )?
  setProgress;
  int Function(
    Pointer<Void>,
    Pointer<NativeFunction<_Authorize>>,
    Pointer<Void>,
  )?
  setAuthorizer;
  var transaction = false;
  final flag = Pointer<Int32>.fromAddress(flagAddress);
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  final bytes = utf8.encode(sql);
  var offset = 0, errorOffset = -1;
  var deniedTransaction = false;
  try {
    if (sql.trim().isEmpty) {
      throw const FormatException('Enter SQL code to run.');
    }
    if (bytes.length > 1000000 || sql.contains('\x00')) {
      throw const FormatException(
        'SQL code is too large or contains invalid characters.',
      );
    }
    if (flag.value != 0) return {'error': 'Query cancelled', 'cancelled': true};
    db = sqlite3.open(path);
    final handle = db.handle.cast<Void>(), lib = open.openSqlite();
    final prepare = lib
        .lookupFunction<
          _Prepare,
          int Function(
            Pointer<Void>,
            Pointer<Utf8>,
            int,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Utf8>>,
          )
        >('sqlite3_prepare_v2');
    final step = lib.lookupFunction<_Step, int Function(Pointer<Void>)>(
      'sqlite3_step',
    );
    finalize = lib.lookupFunction<_Int, int Function(Pointer<Void>)>(
      'sqlite3_finalize',
    );
    final columnCount = lib.lookupFunction<_Int, int Function(Pointer<Void>)>(
      'sqlite3_column_count',
    );
    final parameterCount = lib
        .lookupFunction<_Int, int Function(Pointer<Void>)>(
          'sqlite3_bind_parameter_count',
        );
    final readOnly = lib.lookupFunction<_Int, int Function(Pointer<Void>)>(
      'sqlite3_stmt_readonly',
    );
    final changes = lib.lookupFunction<_Int, int Function(Pointer<Void>)>(
      'sqlite3_total_changes',
    );
    final error = lib
        .lookupFunction<_Text, Pointer<Utf8> Function(Pointer<Void>)>(
          'sqlite3_errmsg',
        );
    final sqlOffset = lib.lookupFunction<_Int, int Function(Pointer<Void>)>(
      'sqlite3_error_offset',
    );
    final columnName = lib
        .lookupFunction<
          _ColumnText,
          Pointer<Utf8> Function(Pointer<Void>, int)
        >('sqlite3_column_name');
    final columnType = lib
        .lookupFunction<_ColumnInt, int Function(Pointer<Void>, int)>(
          'sqlite3_column_type',
        );
    final columnText = lib
        .lookupFunction<
          _ColumnText,
          Pointer<Utf8> Function(Pointer<Void>, int)
        >('sqlite3_column_text');
    final columnInteger = lib
        .lookupFunction<_ColumnInteger, int Function(Pointer<Void>, int)>(
          'sqlite3_column_int64',
        );
    final columnDouble = lib
        .lookupFunction<_ColumnDouble, double Function(Pointer<Void>, int)>(
          'sqlite3_column_double',
        );
    final columnBytes = lib
        .lookupFunction<_ColumnInt, int Function(Pointer<Void>, int)>(
          'sqlite3_column_bytes',
        );
    setProgress = lib
        .lookupFunction<
          _SetProgress,
          void Function(
            Pointer<Void>,
            int,
            Pointer<NativeFunction<_Progress>>,
            Pointer<Void>,
          )
        >('sqlite3_progress_handler');
    setAuthorizer = lib
        .lookupFunction<
          _SetAuthorize,
          int Function(
            Pointer<Void>,
            Pointer<NativeFunction<_Authorize>>,
            Pointer<Void>,
          )
        >('sqlite3_set_authorizer');
    progress = NativeCallable<_Progress>.isolateLocal(
      (Pointer<Void> _) =>
          flag.value != 0 || DateTime.now().isAfter(deadline) ? 1 : 0,
      exceptionalReturn: 1,
    );
    authorizer = NativeCallable<_Authorize>.isolateLocal((
      Pointer<Void> _,
      int action,
      Pointer<Utf8> a,
      Pointer<Utf8> b,
      Pointer<Utf8> database,
      Pointer<Utf8> trigger,
    ) {
      if (action == 22 || action == 32) {
        deniedTransaction = true;
        return 1;
      }
      final function = b == nullptr ? '' : b.toDartString().toLowerCase();
      if (action == 24 ||
          action == 25 ||
          action == 31 &&
              ['load_extension', 'readfile', 'writefile'].contains(function)) {
        return 1;
      }
      return 0;
    }, exceptionalReturn: 1);
    db.execute(
      'PRAGMA busy_timeout=1000; PRAGMA cache_size=-2048; PRAGMA temp_store=FILE;',
    );
    db.execute('BEGIN IMMEDIATE');
    transaction = true;
    setProgress(handle, 1000, progress.nativeFunction, nullptr);
    setAuthorizer(handle, authorizer.nativeFunction, nullptr);
    source = sql.toNativeUtf8(allocator: calloc);
    statement = calloc<Pointer<Void>>();
    tail = calloc<Pointer<Utf8>>();
    final results = <Map<String, dynamic>>[];
    var capturedRows = 0,
        capturedChars = 0,
        truncated = false,
        totalStatements = 0;
    while (offset < bytes.length) {
      if (flag.value != 0 || DateTime.now().isAfter(deadline)) {
        throw const FormatException('SQL execution interrupted');
      }
      final pointer = Pointer<Utf8>.fromAddress(source.address + offset);
      statement.value = nullptr;
      final status = prepare(
        handle,
        pointer,
        bytes.length - offset,
        statement,
        tail,
      );
      if (status != 0) {
        final relative = sqlOffset(handle);
        errorOffset = relative >= 0 ? offset + relative : offset;
        throw FormatException(
          deniedTransaction
              ? 'Transaction commands are unnecessary: each run is already atomic.'
              : error(handle).toDartString(),
        );
      }
      final next = tail.value.address - source.address;
      if (next <= offset) break;
      offset = next;
      final current = statement.value;
      if (current == nullptr) {
        continue; // Whitespace/comments, parsed by SQLite.
      }
      totalStatements++;
      if (totalStatements > 200) {
        throw const FormatException('Run up to 200 SQL statements at a time.');
      }
      if (parameterCount(current) != 0) {
        throw const FormatException(
          'Enter parameter values directly in this SQL block before running it.',
        );
      }
      final count = columnCount(current), isReadOnly = readOnly(current) != 0;
      final columns = List.generate(
        count,
        (i) => columnName(current, i).toDartString(),
      );
      final rows = <List<Object?>>[];
      final before = changes(handle);
      while (true) {
        final status = step(current);
        if (status == 101) break; // SQLITE_DONE
        if (status != 100) throw FormatException(error(handle).toDartString());
        if (capturedRows >= 1000 || capturedChars >= 200000) {
          truncated = true;
          if (isReadOnly) break;
          continue;
        }
        final row = List<Object?>.generate(count, (i) {
          switch (columnType(current, i)) {
            case 1:
              return columnInteger(current, i);
            case 2:
              return columnDouble(current, i);
            case 3:
              final length = columnBytes(current, i);
              final size = math.min(length, 4000);
              final value = utf8.decode(
                columnText(current, i).cast<Uint8>().asTypedList(size),
                allowMalformed: true,
              );
              if (length > size) truncated = true;
              return length > size ? '$value…' : value;
            case 4:
              return '[BLOB: ${columnBytes(current, i)} bytes]';
            default:
              return null;
          }
        });
        capturedChars += jsonEncode(row).length;
        capturedRows++;
        rows.add(row);
      }
      if (results.length < 200) {
        results.add({
          'columns': columns,
          'rows': rows,
          'changed': changes(handle) - before,
        });
      }
      finalize(current);
      statement.value = nullptr;
    }
    setAuthorizer(handle, nullptr, nullptr);
    db.execute('COMMIT');
    transaction = false;
    return {
      'results': results,
      'truncated': truncated,
      'statements': totalStatements,
    };
  } catch (e) {
    final cancelled = flag.value != 0,
        timedOut = DateTime.now().isAfter(deadline);
    final result = <String, dynamic>{
      'error': e is FormatException ? e.message : e.toString(),
      'cancelled': cancelled,
      'timedOut': timedOut,
    };
    if (errorOffset >= 0) {
      final prefix = utf8.decode(
        bytes.take(errorOffset.clamp(0, bytes.length)).toList(),
        allowMalformed: true,
      );
      result['line'] = '\n'.allMatches(prefix).length + 1;
      result['column'] = prefix.split('\n').last.length + 1;
    }
    return result;
  } finally {
    if (statement != null && statement.value != nullptr) {
      finalize?.call(statement.value);
    }
    if (db != null) {
      setAuthorizer?.call(db.handle.cast<Void>(), nullptr, nullptr);
      setProgress?.call(db.handle.cast<Void>(), 0, nullptr, nullptr);
      if (transaction) {
        try {
          db.execute('ROLLBACK');
        } catch (_) {}
      }
      db.dispose();
    }
    progress?.close();
    authorizer?.close();
    if (statement != null) calloc.free(statement);
    if (tail != null) calloc.free(tail);
    if (source != null) calloc.free(source);
  }
}

String _sqlError(Map<String, dynamic> result) {
  if (result['cancelled'] == true) {
    return trs('SQL execution stopped. Changes were rolled back.');
  }
  if (result['timedOut'] == true) {
    return trs('SQL execution timed out. Changes were rolled back.');
  }
  final raw = result['error'] as String;
  final missing = RegExp(r'no such table:\s*(.+)').firstMatch(raw);
  var message = missing == null
      ? trs('SQL error: {error}', {'error': trs(raw)})
      : trs(
          'Table {name} does not exist. Run its CREATE TABLE block in this note first.',
          {'name': missing[1]!},
        );
  if (result['line'] != null) {
    message +=
        '\n${trs('Line {line}, column {column}', {'line': result['line'], 'column': result['column']})}';
  }
  return '$message\n${trs('Changes from this run were rolled back.')}';
}

String _sqlOutput(Map<String, dynamic> result) {
  final out = StringBuffer();
  var clipped = false;
  final results = result['results'] as List;
  if (results.isEmpty) return '${trs('No executable SQL statement found.')}\n';
  for (final (index, data) in results.indexed) {
    if (results.length > 1) out.writeln(trs('Statement {n}', {'n': index + 1}));
    final columns = List<String>.from(data['columns']);
    if (columns.isEmpty) {
      out.writeln(
        trs('SQL completed. {n} rows affected.', {'n': data['changed']}),
      );
      continue;
    }
    final rows = (data['rows'] as List)
        .map((r) => List<Object?>.from(r))
        .toList();
    String cell(Object? v) => (v?.toString() ?? 'NULL')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', ' ');
    final widths = List.generate(
      columns.length,
      (i) => math.min(
        40,
        [
          cell(columns[i]).length,
          ...rows.map((r) => cell(r[i]).length),
        ].fold<int>(1, math.max),
      ),
    );
    String line(List<Object?> row) => List.generate(columns.length, (i) {
      final text = cell(row[i]), width = widths[i];
      if (text.length > width) clipped = true;
      return (text.length > width
              ? '${text.substring(0, math.max(0, width - 1))}…'
              : text)
          .padRight(width);
    }).join(' | ');
    out.writeln(line(columns));
    out.writeln(widths.map((w) => '-' * w).join('-+-'));
    for (final row in rows) {
      out.writeln(line(row));
    }
    out.writeln(trs('{n} rows returned.', {'n': rows.length}));
    if (data['changed'] > 0) {
      out.writeln(
        trs('SQL completed. {n} rows affected.', {'n': data['changed']}),
      );
    }
    out.writeln();
  }
  if (result['truncated'] == true || clipped) {
    out.writeln(
      trs('SQL output was limited. Use LIMIT or filters to narrow the result.'),
    );
  }
  return out.toString();
}
