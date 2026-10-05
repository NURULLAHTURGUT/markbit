import 'package:flutter_test/flutter_test.dart';
import 'package:markbit/core/l10n/app_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:markbit/domain/execution/sql_executor.dart';
import 'package:markbit/domain/execution/execution.dart';
import 'package:markbit/domain/languages.dart';

void main() {
  late SqlExecutor sql;
  setUp(() {
    sql = SqlExecutor();
    AppStrings.current = AppStrings(const Locale('en'));
  });
  tearDown(() => sql.close());
  Future<({String output, RunFinished result})> run(
    String code, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final events = await sql
        .execute(
          ExecutionRequest(
            language: Languages.find('sql')!,
            code: code,
            timeout: timeout,
          ),
        )
        .toList();
    return (
      output: events.whereType<RunOutput>().map((e) => e.text).join(),
      result: events.whereType<RunFinished>().single,
    );
  }

  test(
    'Screenshot CREATE, INSERT and SELECT blocks share this note SQL session',
    () async {
      expect(
        (await run(
          'CREATE TABLE Calisanlar (id INT PRIMARY KEY, ad VARCHAR(50), soyad VARCHAR(50), maas DECIMAL(10,2));',
        )).result.success,
        true,
      );
      final inserted = await run(
        "INSERT INTO Calisanlar VALUES (1,'Ahmet','Yilmaz',5000),(2,'Mehmet','Demir',6000),(3,'Ayse','Kara',7000);",
      );
      expect(inserted.output, contains('3 rows affected'));
      expect(inserted.result.success, true);
      final queried = await run('SELECT * FROM Calisanlar WHERE maas > 5500;');
      expect(queried.result.success, true);
      expect(queried.output, contains('Mehmet'));
      expect(queried.output, contains('Ayse'));
      expect(queried.output, isNot(contains('Ahmet')));
      final other = SqlExecutor();
      try {
        expect(
          (await other
                  .execute(
                    ExecutionRequest(
                      language: Languages.find('sql')!,
                      code: 'SELECT * FROM Calisanlar',
                    ),
                  )
                  .toList())
              .whereType<RunFinished>()
              .single
              .success,
          false,
        );
      } finally {
        await other.close();
      }
    },
  );
  test(
    'Whole SQL scripts handle comments, quoted semicolons and trigger bodies',
    () async {
      final result = await run('''-- a comment;
      CREATE TABLE sample(id INTEGER PRIMARY KEY,value TEXT);
      CREATE TABLE audit(message TEXT);
      CREATE TRIGGER log AFTER INSERT ON sample BEGIN
        INSERT INTO audit VALUES('created; item');
        INSERT INTO audit VALUES(NEW.value);
      END;
      INSERT INTO sample(value) VALUES('hello; world');
      SELECT * FROM audit; -- trailing comment
    ''');
      expect(result.result.success, true, reason: result.output);
      expect(result.output, contains('created; item'));
      expect(result.output, contains('hello; world'));
    },
  );
  test(
    'Failed scripts roll back earlier changes and give helpful Turkish missing-table message',
    () async {
      await run('CREATE TABLE t(x INTEGER UNIQUE);');
      final bad = await run(
        'INSERT INTO t VALUES(1); INSERT INTO t VALUES(1);',
      );
      expect(bad.result.success, false);
      expect(
        (await run('SELECT COUNT(*) AS count FROM t')).output,
        contains('0'),
      );
      AppStrings.current = AppStrings(const Locale('tr'));
      final missing = await run('SELECT * FROM Calisanlar;');
      expect(missing.output, contains('Önce bu nottaki CREATE TABLE'));
      expect(missing.output, contains('Satır 1'));
      expect(missing.output, isNot(contains('Piston')));
    },
  );
  test('Native timeout rolls back and later queries remain usable', () async {
    await run('CREATE TABLE t(x INTEGER);');
    final result = await run(
      'INSERT INTO t VALUES(1); WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n) SELECT SUM(x) FROM n;',
      timeout: const Duration(milliseconds: 80),
    );
    expect(result.result.timedOut, true);
    expect((await run('SELECT COUNT(*) FROM t')).output, contains('0'));
  });
  test('Cancel stops a native SQL run before allowing a new run', () async {
    final request = ExecutionRequest(
      language: Languages.find('sql')!,
      code:
          'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n) SELECT SUM(x) FROM n;',
    );
    final sub = sql.execute(request).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel().timeout(const Duration(seconds: 3));
    expect((await run('SELECT 42 AS result')).result.success, true);
  });
  test('Output is bounded and incompatible parameters are explained', () async {
    final large = await run(
      'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<5000) SELECT x FROM n;',
    );
    expect(large.result.success, true);
    expect(large.output, contains('1000 rows returned'));
    expect(large.output, contains('output was limited'));
    expect(
      (await run('SELECT :name')).output,
      contains('parameter values directly'),
    );
    expect(
      (await run("ATTACH DATABASE 'external.sqlite' AS other")).result.success,
      false,
    );
  });
}
