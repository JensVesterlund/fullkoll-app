// Dev-only lint sweep for i18n coverage and hardcoded UI strings.
// Usage: dart run tool/i18n_lint.dart
// In Dreamflow, this file is provided for reference; run locally if needed.

import 'dart:convert';
import 'dart:io';

// Simplified heuristic: find Text('...') or Text("...") not starting with context.l10n.translate(
final uiStringPattern = RegExp(r'''Text\(\s*['"](?!context\.l10n\.translate\().+?['"]''');

void main() async {
  final lib = Directory('lib');
  final dartFiles = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final offenders = <String, List<String>>{}; // file -> lines
  for (final file in dartFiles) {
    if (file.path.contains('/i18n/') || file.path.contains('/generated/')) continue;
    final content = await file.readAsString();
    final matches = uiStringPattern.allMatches(content);
    for (final m in matches) {
      final line = _lineForOffset(content, m.start);
      offenders.putIfAbsent(file.path, () => <String>[]).add('line $line');
    }
  }

  final sv = json.decode(File('assets/i18n/sv-SE.json').readAsStringSync()) as Map;
  final en = json.decode(File('assets/i18n/en-US.json').readAsStringSync()) as Map;
  final svKeys = sv.keys.cast<String>().toSet();
  final enKeys = en.keys.cast<String>().toSet();
  final missingInEn = svKeys.difference(enKeys).toList()..sort();

  stdout.writeln('== i18n Lint ==');
  stdout.writeln('Hardcoded Text(..) occurrences: ${offenders.values.fold<int>(0, (a, b) => a + b.length)}');
  offenders.forEach((file, lines) => stdout.writeln('  $file -> ${lines.join(', ')}'));
  stdout.writeln('Missing keys in en-US: ${missingInEn.length}');
  for (final k in missingInEn) {
    stdout.writeln('  $k');
  }
}

int _lineForOffset(String content, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < content.length; i++) {
    if (content.codeUnitAt(i) == 10) line++;
  }
  return line;
}
