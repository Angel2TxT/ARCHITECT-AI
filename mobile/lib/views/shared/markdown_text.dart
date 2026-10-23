import 'package:flutter/material.dart';

/// Renderiza Markdown básico del backend: negrita, listas y títulos de sección.
class MarkdownText extends StatelessWidget {
  const MarkdownText({
    super.key,
    required this.data,
    this.style,
  });

  final String data;
  final TextStyle? style;

  static final _boldPattern = RegExp(r'\*\*(.+?)\*\*');
  static final _listPrefix = RegExp(r'^\s*[-*]\s+');
  static final _numberedPrefix = RegExp(r'^\s*(\d+)[.)]\s+');
  static final _headingOnly = RegExp(r'^\*\*(.+)\*\*\s*$');

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final lines = data.replaceAll('\r\n', '\n').split('\n');
    final structured = lines.any(
      (line) =>
          _listPrefix.hasMatch(line) ||
          _numberedPrefix.hasMatch(line) ||
          _headingOnly.hasMatch(line.trim()) ||
          line.trim().isEmpty,
    );

    if (!structured && lines.length <= 1) {
      return Text.rich(
        TextSpan(style: baseStyle, children: _inlineSpans(data, baseStyle)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          _buildLine(lines[i], baseStyle, i == 0),
      ],
    );
  }

  Widget _buildLine(String line, TextStyle baseStyle, bool isFirst) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return const SizedBox(height: 10);
    }

    final heading = _headingOnly.firstMatch(trimmed);
    if (heading != null) {
      return Padding(
        padding: EdgeInsets.only(top: isFirst ? 0 : 6, bottom: 4),
        child: Text(
          heading.group(1)!,
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: (baseStyle.fontSize ?? 14) + 0.5,
            height: 1.35,
          ),
        ),
      );
    }

    final numbered = _numberedPrefix.firstMatch(line);
    if (numbered != null) {
      final body = line.substring(numbered.end);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '${numbered.group(1)}.',
                style: baseStyle.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: baseStyle,
                  children: _inlineSpans(body, baseStyle),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final listMatch = _listPrefix.firstMatch(line);
    if (listMatch != null) {
      final body = line.substring(listMatch.end);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: baseStyle.copyWith(fontWeight: FontWeight.w700)),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: baseStyle,
                  children: _inlineSpans(body, baseStyle),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(style: baseStyle, children: _inlineSpans(line, baseStyle)),
      ),
    );
  }

  static List<InlineSpan> _inlineSpans(String text, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _boldPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: baseStyle.copyWith(fontWeight: FontWeight.w800),
        ),
      );
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text));
    }
    return spans;
  }
}
