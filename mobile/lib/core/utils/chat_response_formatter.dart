/// Normaliza texto del asistente/análisis para mostrarlo más ordenado en el chat.
abstract final class ChatResponseFormatter {
  static final _loPrincipal = RegExp(
    r'Lo principal:\s*(.+?)(?:\.\s*En total|\.\s*$|$)',
    caseSensitive: false,
    dotAll: true,
  );
  static final _enTotal = RegExp(
    r'\s*En total\s+\d+\s+error\(es\)\s+y\s+\d+\s+aviso\(s\)\.?\s*',
    caseSensitive: false,
  );
  static final _statsLine = RegExp(
    r'^Errores:\s*\d+\s*\|\s*Avisos:\s*\d+.*$',
    caseSensitive: false,
  );
  static final _sectionLabel = RegExp(
    r'^(Siguiente paso|Resumen|Hallazgos|Detalle|Recomendaciones|Escala)\s*:\s*$',
    caseSensitive: false,
  );

  /// Convierte el detalle denso del veredicto en markdown con viñetas.
  static String formatVerdictDetail(
    String detail, {
    bool omitTotals = true,
  }) {
    final trimmed = detail.trim();
    if (trimmed.isEmpty) return '';

    var working = trimmed;
    if (omitTotals) {
      working = working.replaceAll(_enTotal, ' ').trim();
    }

    final match = _loPrincipal.firstMatch(working);
    if (match == null) {
      return _splitSemicolonsAsList(working);
    }

    final itemsRaw = match.group(1)?.trim() ?? '';
    final items = _splitPrincipalItems(itemsRaw);
    if (items.isEmpty) return working;

    final buffer = StringBuffer('**Hallazgos principales**\n');
    for (final item in items) {
      buffer.writeln('- $item');
    }
    return buffer.toString().trimRight();
  }

  /// Reordena el cuerpo markdown del asistente: secciones, listas y menos densos.
  static String formatAssistantText(String text) {
    var value = text.replaceAll('\r\n', '\n').trim();
    if (value.isEmpty) return value;

    // "Lo principal: A; B; C." → lista con título.
    value = value.replaceAllMapped(_loPrincipal, (match) {
      final items = _splitPrincipalItems(match.group(1) ?? '');
      if (items.isEmpty) return match.group(0)!;
      final buf = StringBuffer('\n**Hallazgos principales**\n');
      for (final item in items) {
        buf.writeln('- $item');
      }
      return '\n${buf.toString().trim()}\n';
    });

    // Quitar "En total..." redundante (ya hay badges).
    value = value.replaceAll(_enTotal, '\n');

    final lines = value.split('\n');
    final out = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
        continue;
      }

      // Línea de contadores tipo "Errores: 7 | Avisos: 13 | ..."
      if (_statsLine.hasMatch(trimmed)) {
        continue;
      }

      // "Siguiente paso:" / etiquetas de sección → título en negrita.
      if (_sectionLabel.hasMatch(trimmed) ||
          (trimmed.endsWith(':') &&
              !trimmed.startsWith('-') &&
              !trimmed.startsWith('*') &&
              trimmed.length < 40 &&
              !trimmed.contains('http'))) {
        if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
        final label = trimmed.replaceAll(RegExp(r':\s*$'), '');
        out.add('**$label**');
        out.add('');
        continue;
      }

      // Párrafos muy largos con "; " → viñetas si parecen hallazgos.
      if (trimmed.contains('; ') &&
          trimmed.length > 80 &&
          !trimmed.startsWith('-') &&
          !trimmed.startsWith('*') &&
          !RegExp(r'^\d+\.').hasMatch(trimmed)) {
        final pieces = _splitPrincipalItems(trimmed);
        if (pieces.length >= 2) {
          if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
          for (final piece in pieces) {
            out.add('- $piece');
          }
          out.add('');
          continue;
        }
      }

      out.add(line);
    }

    return _collapseBlankLines(out).join('\n').trim();
  }

  static List<String> _splitPrincipalItems(String raw) {
    return raw
        .split(RegExp(r'\s*;\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => e.replaceAll(RegExp(r'\.+$'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String _splitSemicolonsAsList(String text) {
    final items = _splitPrincipalItems(text);
    if (items.length < 2) return text;
    final buffer = StringBuffer();
    for (final item in items) {
      buffer.writeln('- $item');
    }
    return buffer.toString().trimRight();
  }

  /// Quita del cuerpo un bloque de hallazgos si ya se mostró en el veredicto.
  static String stripDuplicateHallazgos(String body) {
    final pattern = RegExp(
      r'\n?\*\*Hallazgos principales\*\*\n(?:- .+\n?)+',
      caseSensitive: false,
    );
    return body.replaceFirst(pattern, '\n').trim();
  }

  static List<String> _collapseBlankLines(List<String> lines) {
    final result = <String>[];
    for (final line in lines) {
      if (line.isEmpty && (result.isEmpty || result.last.isEmpty)) continue;
      result.add(line);
    }
    while (result.isNotEmpty && result.last.isEmpty) {
      result.removeLast();
    }
    return result;
  }
}
