/// Normaliza texto del asistente/análisis para mostrarlo más ordenado en el chat.
abstract final class ChatResponseFormatter {
  static final _bulletPrefix = RegExp(r'^\s*([•\-\*]|\u2022)\s+');

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

  /// Limpia viñetas forzadas o antiestéticas en respuestas cortas, saludos o textos conversacionales.
  static String cleanConversationalBullets(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final lines = trimmed.split('\n');
    final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) return trimmed;

    final bulletLines =
        nonEmpty.where((l) => _bulletPrefix.hasMatch(l.trim())).toList();

    final hasHeader = nonEmpty.any(
      (l) => l.trim().startsWith('**') && l.trim().endsWith('**'),
    );
    final isConversational = trimmed.toLowerCase().contains('mucho gusto') ||
        trimmed.toLowerCase().contains('hola') ||
        trimmed.toLowerCase().contains('servicio') ||
        trimmed.toLowerCase().contains('bienvenido') ||
        trimmed.toLowerCase().contains('ayudarte') ||
        trimmed.toLowerCase().contains('asesorarte');

    final shouldClean =
        (bulletLines.isNotEmpty && !hasHeader && nonEmpty.length <= 4) ||
            (isConversational && bulletLines.isNotEmpty);

    if (!shouldClean) return text;

    final cleanedItems = <String>[];
    for (final line in nonEmpty) {
      var item = line.trim().replaceFirst(_bulletPrefix, '').trim();
      if (item.isEmpty) continue;
      // Capitalizar inicial
      item = item[0].toUpperCase() + item.substring(1);
      // Puntuación adecuada al final
      if (!item.endsWith('.') &&
          !item.endsWith('!') &&
          !item.endsWith('?') &&
          !item.endsWith(':')) {
        item = '$item.';
      }
      cleanedItems.add(item);
    }

    return cleanedItems.join(' ');
  }

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

    // Si es un texto conversacional con viñetas forzadas, limpiarlo al instante
    final cleaned = cleanConversationalBullets(value);
    if (cleaned != value) {
      return cleaned;
    }

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
              !trimmed.startsWith('•') &&
              trimmed.length < 40 &&
              !trimmed.contains('http'))) {
        if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
        final label = trimmed.replaceAll(RegExp(r':\s*$'), '');
        out.add('**$label**');
        out.add('');
        continue;
      }

      out.add(line);
    }

    final formatted = _collapseBlankLines(out).join('\n').trim();
    return cleanConversationalBullets(formatted);
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
