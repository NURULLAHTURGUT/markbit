/// One command of a toolchain. Placeholders in [args]/[exe]:
/// `{src}` source file, `{dir}` working directory, `{out}` compiled binary.
class ExecStep {
  const ExecStep(this.exe, this.args);
  final String exe;
  final List<String> args;
}

/// A way of running a language locally: a probe to detect it and the steps
/// (compile, run) to execute.
class ToolChain {
  const ToolChain({
    required this.label,
    required this.probe,
    required this.steps,
    this.shell = false,
  });

  final String label;

  /// Command used to check availability, e.g. `['python', '--version']`.
  final List<String> probe;
  final List<ExecStep> steps;

  /// Needed for `.cmd`/`.bat` shims on Windows (npm, kotlinc...).
  final bool shell;
}

class CodeLanguage {
  const CodeLanguage({
    required this.id,
    required this.name,
    required this.extension,
    this.aliases = const [],
    this.toolchains = const [],
    this.pistonId,
    this.sample = '',
    this.fileName,
  });

  final String id;
  final String name;
  final String extension;
  final List<String> aliases;
  final List<ToolChain> toolchains;

  /// Language name understood by Piston-compatible execution APIs.
  final String? pistonId;
  final String sample;
  final String? fileName;

  bool get runnable => toolchains.isNotEmpty || pistonId != null;

  String get sourceFileName => fileName ?? 'main.$extension';
}

abstract final class Languages {
  static const _py = ['-u', '{src}'];

  static const List<CodeLanguage> all = [
    CodeLanguage(
      id: 'python',
      name: 'Python',
      extension: 'py',
      aliases: ['py', 'python3', 'py3'],
      pistonId: 'python',
      sample:
          'def greet(name: str) -> str:\n    return f"Hello, {name}!"\n\nprint(greet("Markbit"))\n',
      toolchains: [
        ToolChain(
          label: 'python',
          probe: ['python', '--version'],
          steps: [ExecStep('python', _py)],
        ),
        ToolChain(
          label: 'python3',
          probe: ['python3', '--version'],
          steps: [ExecStep('python3', _py)],
        ),
        ToolChain(
          label: 'py launcher',
          probe: ['py', '-3', '--version'],
          steps: [
            ExecStep('py', ['-3', '-u', '{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'javascript',
      name: 'JavaScript',
      extension: 'js',
      aliases: ['js', 'node', 'nodejs', 'mjs', 'jsx'],
      pistonId: 'javascript',
      sample:
          'const greet = (name) => `Hello, \${name}!`;\nconsole.log(greet("Markbit"));\n',
      toolchains: [
        ToolChain(
          label: 'node',
          probe: ['node', '--version'],
          steps: [
            ExecStep('node', ['{src}']),
          ],
        ),
        ToolChain(
          label: 'deno',
          probe: ['deno', '--version'],
          steps: [
            ExecStep('deno', ['run', '-A', '{src}']),
          ],
        ),
        ToolChain(
          label: 'bun',
          probe: ['bun', '--version'],
          steps: [
            ExecStep('bun', ['run', '{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'typescript',
      name: 'TypeScript',
      extension: 'ts',
      aliases: ['ts', 'tsx'],
      pistonId: 'typescript',
      sample:
          'const greet = (name: string): string => `Hello, \${name}!`;\nconsole.log(greet("Markbit"));\n',
      toolchains: [
        ToolChain(
          label: 'tsx',
          probe: ['tsx', '--version'],
          shell: true,
          steps: [
            ExecStep('tsx', ['{src}']),
          ],
        ),
        ToolChain(
          label: 'ts-node',
          probe: ['ts-node', '--version'],
          shell: true,
          steps: [
            ExecStep('ts-node', ['{src}']),
          ],
        ),
        ToolChain(
          label: 'deno',
          probe: ['deno', '--version'],
          steps: [
            ExecStep('deno', ['run', '-A', '{src}']),
          ],
        ),
        ToolChain(
          label: 'bun',
          probe: ['bun', '--version'],
          steps: [
            ExecStep('bun', ['run', '{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'dart',
      name: 'Dart',
      extension: 'dart',
      pistonId: 'dart',
      sample:
          'void main() {\n  final names = [\'Ada\', \'Linus\', \'Grace\'];\n  for (final n in names) {\n    print(\'Hello, \$n!\');\n  }\n}\n',
      toolchains: [
        ToolChain(
          label: 'dart',
          probe: ['dart', '--version'],
          shell: true,
          steps: [
            ExecStep('dart', ['run', '{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'java',
      name: 'Java',
      extension: 'java',
      fileName: 'Main.java',
      pistonId: 'java',
      sample:
          'public class Main {\n    public static void main(String[] args) {\n        System.out.println("Hello, Markbit!");\n    }\n}\n',
      toolchains: [
        ToolChain(
          label: 'java (source launcher)',
          probe: ['java', '-version'],
          steps: [
            ExecStep('java', ['{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'kotlin',
      name: 'Kotlin',
      extension: 'kt',
      aliases: ['kt', 'kts'],
      pistonId: 'kotlin',
      sample: 'fun main() {\n    println("Hello, Markbit!")\n}\n',
      toolchains: [
        ToolChain(
          label: 'kotlinc',
          probe: ['kotlinc', '-version'],
          shell: true,
          steps: [
            ExecStep('kotlinc', ['{src}', '-include-runtime', '-d', 'out.jar']),
            ExecStep('java', ['-jar', 'out.jar']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'c',
      name: 'C',
      extension: 'c',
      aliases: ['h'],
      pistonId: 'c',
      sample:
          '#include <stdio.h>\n\nint main(void) {\n    printf("Hello, Markbit!\\n");\n    return 0;\n}\n',
      toolchains: [
        ToolChain(
          label: 'gcc',
          probe: ['gcc', '--version'],
          steps: [
            ExecStep('gcc', ['{src}', '-O1', '-o', '{out}']),
            ExecStep('{out}', []),
          ],
        ),
        ToolChain(
          label: 'clang',
          probe: ['clang', '--version'],
          steps: [
            ExecStep('clang', ['{src}', '-O1', '-o', '{out}']),
            ExecStep('{out}', []),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'cpp',
      name: 'C++',
      extension: 'cpp',
      aliases: ['c++', 'cc', 'cxx', 'hpp'],
      pistonId: 'c++',
      sample:
          '#include <iostream>\n\nint main() {\n    std::cout << "Hello, Markbit!" << std::endl;\n    return 0;\n}\n',
      toolchains: [
        ToolChain(
          label: 'g++',
          probe: ['g++', '--version'],
          steps: [
            ExecStep('g++', ['{src}', '-std=c++17', '-O1', '-o', '{out}']),
            ExecStep('{out}', []),
          ],
        ),
        ToolChain(
          label: 'clang++',
          probe: ['clang++', '--version'],
          steps: [
            ExecStep('clang++', ['{src}', '-std=c++17', '-O1', '-o', '{out}']),
            ExecStep('{out}', []),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'csharp',
      name: 'C#',
      extension: 'cs',
      aliases: ['cs', 'c#', 'dotnet'],
      pistonId: 'csharp',
      sample: 'using System;\n\nConsole.WriteLine("Hello, Markbit!");\n',
      toolchains: [
        ToolChain(
          label: 'dotnet-script',
          probe: ['dotnet-script', '--version'],
          shell: true,
          steps: [
            ExecStep('dotnet-script', ['{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'go',
      name: 'Go',
      extension: 'go',
      aliases: ['golang'],
      pistonId: 'go',
      sample:
          'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("Hello, Markbit!")\n}\n',
      toolchains: [
        ToolChain(
          label: 'go',
          probe: ['go', 'version'],
          steps: [
            ExecStep('go', ['run', '{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'rust',
      name: 'Rust',
      extension: 'rs',
      aliases: ['rs'],
      pistonId: 'rust',
      sample: 'fn main() {\n    println!("Hello, Markbit!");\n}\n',
      toolchains: [
        ToolChain(
          label: 'rustc',
          probe: ['rustc', '--version'],
          steps: [
            ExecStep('rustc', ['{src}', '-o', '{out}']),
            ExecStep('{out}', []),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'ruby',
      name: 'Ruby',
      extension: 'rb',
      aliases: ['rb'],
      pistonId: 'ruby',
      sample: 'puts "Hello, Markbit!"\n',
      toolchains: [
        ToolChain(
          label: 'ruby',
          probe: ['ruby', '--version'],
          steps: [
            ExecStep('ruby', ['{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'php',
      name: 'PHP',
      extension: 'php',
      pistonId: 'php',
      sample: '<?php\necho "Hello, Markbit!\\n";\n',
      toolchains: [
        ToolChain(
          label: 'php',
          probe: ['php', '--version'],
          steps: [
            ExecStep('php', ['{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'lua',
      name: 'Lua',
      extension: 'lua',
      pistonId: 'lua',
      sample: 'print("Hello, Markbit!")\n',
      toolchains: [
        ToolChain(
          label: 'lua',
          probe: ['lua', '-v'],
          steps: [
            ExecStep('lua', ['{src}']),
          ],
        ),
        ToolChain(
          label: 'luajit',
          probe: ['luajit', '-v'],
          steps: [
            ExecStep('luajit', ['{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'perl',
      name: 'Perl',
      extension: 'pl',
      aliases: ['pl'],
      pistonId: 'perl',
      sample: 'print "Hello, Markbit!\\n";\n',
      toolchains: [
        ToolChain(
          label: 'perl',
          probe: ['perl', '--version'],
          steps: [
            ExecStep('perl', ['{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'bash',
      name: 'Bash',
      extension: 'sh',
      aliases: ['sh', 'shell', 'zsh', 'console'],
      pistonId: 'bash',
      sample: 'echo "Hello, Markbit!"\n',
      toolchains: [
        ToolChain(
          label: 'bash',
          probe: ['bash', '--version'],
          steps: [
            ExecStep('bash', ['{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'powershell',
      name: 'PowerShell',
      extension: 'ps1',
      aliases: ['ps1', 'pwsh', 'ps'],
      pistonId: 'powershell',
      sample: 'Write-Output "Hello, Markbit!"\n',
      toolchains: [
        ToolChain(
          label: 'pwsh',
          probe: [
            'pwsh',
            '-NoProfile',
            '-Command',
            '\$PSVersionTable.PSVersion.ToString()',
          ],
          steps: [
            ExecStep('pwsh', ['-NoProfile', '-File', '{src}']),
          ],
        ),
        ToolChain(
          label: 'Windows PowerShell',
          probe: [
            'powershell',
            '-NoProfile',
            '-Command',
            '\$PSVersionTable.PSVersion.ToString()',
          ],
          steps: [
            ExecStep('powershell', [
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              '{src}',
            ]),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'swift',
      name: 'Swift',
      extension: 'swift',
      pistonId: 'swift',
      sample: 'print("Hello, Markbit!")\n',
      toolchains: [
        ToolChain(
          label: 'swift',
          probe: ['swift', '--version'],
          steps: [
            ExecStep('swift', ['{src}']),
          ],
        ),
      ],
    ),
    CodeLanguage(
      id: 'r',
      name: 'R',
      extension: 'r',
      pistonId: 'r',
      sample: 'cat("Hello, Markbit!\\n")\n',
      toolchains: [
        ToolChain(
          label: 'Rscript',
          probe: ['Rscript', '--version'],
          steps: [
            ExecStep('Rscript', ['{src}']),
          ],
        ),
      ],
    ),
    // Highlight-only languages.
    CodeLanguage(
      id: 'sql',
      name: 'SQL',
      extension: 'sql',
      pistonId: 'sqlite3',
      sample: 'SELECT 1 + 1 AS result;\n',
    ),
    CodeLanguage(
      id: 'json',
      name: 'JSON',
      extension: 'json',
      sample: '{\n  "hello": "markbit"\n}\n',
    ),
    CodeLanguage(id: 'yaml', name: 'YAML', extension: 'yml', aliases: ['yml']),
    CodeLanguage(id: 'toml', name: 'TOML', extension: 'toml'),
    CodeLanguage(
      id: 'html',
      name: 'HTML',
      extension: 'html',
      aliases: ['htm', 'xml', 'svg', 'vue'],
    ),
    CodeLanguage(
      id: 'css',
      name: 'CSS',
      extension: 'css',
      aliases: ['scss', 'less'],
    ),
    CodeLanguage(
      id: 'markdown',
      name: 'Markdown',
      extension: 'md',
      aliases: ['md'],
    ),
    CodeLanguage(
      id: 'text',
      name: 'Plain text',
      extension: 'txt',
      aliases: ['txt', 'plaintext'],
    ),
  ];

  static final Map<String, CodeLanguage> _index = {
    for (final l in all) ...{l.id: l, for (final a in l.aliases) a: l},
  };

  /// Finds a language by id or alias (case-insensitive).
  static CodeLanguage? find(String? name) {
    if (name == null) return null;
    return _index[name.trim().toLowerCase()];
  }

  static List<CodeLanguage> get runnable =>
      all.where((l) => l.runnable).toList(growable: false);
}
