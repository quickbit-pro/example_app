import 'package:flutter/material.dart';

import '../../../brands/example/example_colors.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/l10n/app_localizations.dart';
import '../data/assistant_api.dart';

/// Inert, bounded presentation for concierge answers. Links and HTML remain
/// text; only separately validated source/action widgets open destinations.
class AssistantAnswer extends StatefulWidget {
  const AssistantAnswer(
      {super.key, required this.text, this.answer, this.onOpenSource});

  final String text;
  final AssistantStructuredAnswer? answer;
  final ValueChanged<String>? onOpenSource;

  @override
  State<AssistantAnswer> createState() => _AssistantAnswerState();
}

class _AssistantAnswerState extends State<AssistantAnswer> {
  bool _showFullAnswer = false;
  int _answerRevision = 0;

  @override
  void didUpdateWidget(covariant AssistantAnswer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.answer != widget.answer) {
      _showFullAnswer = false;
      _answerRevision++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: palette.ink,
          fontSize: 13.5 * context.brandDesign.typographyScale,
          height: 1.5,
        );
    final answer = widget.answer;
    final preview = _legacyPreview(widget.text);
    final collapsed = answer == null && preview != widget.text.trim();

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        // A short reading measure also helps on desktop and wide tablets.
        constraints: const BoxConstraints(maxWidth: 680),
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (answer != null) ...[
                Semantics(
                  header: true,
                  child: Text(
                    answer.title,
                    style: style.copyWith(
                      fontSize: style.fontSize! * 1.3,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(answer.summary, style: style),
                if (answer.options.isNotEmpty) const SizedBox(height: 16),
                for (var index = 0; index < answer.options.length; index++) ...[
                  if (index > 0) const SizedBox(height: 12),
                  _RecommendationCard(
                    key: ValueKey('$_answerRevision:$index'),
                    number: index + 1,
                    option: answer.options[index],
                    style: style,
                    onOpenSource: widget.onOpenSource,
                  ),
                ],
                if (answer.nextStep != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsetsDirectional.only(
                        start: 12, top: 2, bottom: 2),
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(color: palette.accent, width: 3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Next step',
                            style: style.copyWith(
                                fontWeight: FontWeight.w700,
                                color: palette.accent)),
                        const SizedBox(height: 4),
                        Text(answer.nextStep!, style: style),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                _FormattedAnswer(
                  text: _showFullAnswer ? widget.text : preview,
                  style: style,
                ),
                if (collapsed)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _showFullAnswer = !_showFullAnswer),
                      icon: Icon(
                        _showFullAnswer
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                      ),
                      label: Text(
                          _showFullAnswer ? 'Show less' : 'Show full answer'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.accent,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationCard extends StatefulWidget {
  const _RecommendationCard({
    super.key,
    required this.number,
    required this.option,
    required this.style,
    this.onOpenSource,
  });

  final int number;
  final AssistantAnswerOption option;
  final TextStyle style;
  final ValueChanged<String>? onOpenSource;

  @override
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<_RecommendationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final option = widget.option;
    final style = widget.style;
    final source = option.source;
    final sourceUri = source == null ? null : safeAssistantLink(source.url);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${widget.number}'.padLeft(2, '0'),
                  textAlign: TextAlign.center,
                  style: style.copyWith(
                      color: palette.accent, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    option.title,
                    style: style.copyWith(
                        fontSize: style.fontSize! * 1.12,
                        height: 1.35,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < option.highlights.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•', style: style.copyWith(color: palette.accent)),
                const SizedBox(width: 8),
                Expanded(child: Text(option.highlights[index], style: style)),
              ],
            ),
          ],
          if (sourceUri != null && widget.onOpenSource != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => widget.onOpenSource!(source!.url),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.open_in_new_rounded, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('View website')),
                          Text(sourceUri.host,
                              style: style.copyWith(
                                  fontSize:
                                      11 * context.brandDesign.typographyScale,
                                  color: palette.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (option.details != null) ...[
            if (_expanded) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: palette.borderSubtle),
              const SizedBox(height: 12),
              _FormattedAnswer(text: option.details!, style: style),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                expanded: _expanded,
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18),
                  label: Text(_expanded ? 'Less details' : 'More details'),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.accent,
                    minimumSize: const Size(0, 44),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormattedAnswer extends StatelessWidget {
  const _FormattedAnswer({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < blocks.length; index++)
          Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : _blockGap(blocks[index - 1], blocks[index]),
            ),
            child: _AnswerBlockView(block: blocks[index], style: style),
          ),
      ],
    );
  }
}

/// Existing saved conversations and older API replies get a compact preview,
/// even if the model ignored every formatting instruction.
String _legacyPreview(String text) {
  final trimmed = text.trim();
  if (trimmed.length <= 500 && _parseBlocks(trimmed).length <= 8) {
    return trimmed;
  }
  var preview = truncateAssistantText(trimmed, 260);
  final lines = preview.split('\n');
  if (lines.length > 5) preview = lines.take(5).join('\n');
  final lastSpace = preview.lastIndexOf(RegExp(r'\s'));
  if (lastSpace > 0 && lastSpace >= preview.length - 40) {
    preview = preview.substring(0, lastSpace);
  }
  return '${preview.trimRight()}…';
}

class _AnswerBlockView extends StatelessWidget {
  const _AnswerBlockView({required this.block, required this.style});

  final _AnswerBlock block;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final content = Text.rich(
      TextSpan(children: _inlineSpans(block.text)),
      style: block.kind == _BlockKind.heading
          ? style.copyWith(fontWeight: FontWeight.w700)
          : style,
      softWrap: true,
    );
    return switch (block.kind) {
      _BlockKind.heading => Semantics(header: true, child: content),
      _BlockKind.bullet => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(block.marker!, style: style),
            const SizedBox(width: 8),
            Expanded(child: content),
          ],
        ),
      _BlockKind.paragraph => content,
    };
  }
}

enum _BlockKind { paragraph, heading, bullet }

class _AnswerBlock {
  const _AnswerBlock(this.kind, this.text, {this.marker});

  final _BlockKind kind;
  final String text;
  final String? marker;
}

final _heading = RegExp(r'^#{1,2}[ \t]+(.+)$');
final _boldHeading = RegExp(r'^\*\*([^*]+)\*\*$');
final _sectionLabel = RegExp(r'^[^:<>\[\]/\\*#]+:$');
final _bullet = RegExp(r'^([-+*•]|\d{1,3}[.)])[ \t]+(.+)$');
final _bold = RegExp(r'\*\*([^*\n]+)\*\*');

List<_AnswerBlock> _parseBlocks(String text) {
  final blocks = <_AnswerBlock>[];
  final paragraph = <String>[];
  var canContinueBullet = false;

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(_AnswerBlock(_BlockKind.paragraph, paragraph.join('\n')));
    paragraph.clear();
  }

  for (final rawLine in text.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      flushParagraph();
      canContinueBullet = false;
      continue;
    }

    final plainHeading = line.runes.length <= 80 &&
        _sectionLabel.hasMatch(line) &&
        !_bullet.hasMatch(line);
    final heading = _heading.firstMatch(line)?.group(1) ??
        _boldHeading.firstMatch(line)?.group(1) ??
        (plainHeading ? line : null);
    // Long emphasized sentences remain body copy rather than dominating a
    // narrow conversation. Unknown markdown syntax is preserved as text.
    if (heading != null && heading.runes.length <= 120) {
      flushParagraph();
      blocks.add(_AnswerBlock(_BlockKind.heading, heading));
      canContinueBullet = false;
      continue;
    }

    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      final marker = bullet.group(1)!;
      blocks.add(_AnswerBlock(_BlockKind.bullet, bullet.group(2)!,
          marker: marker.length == 1 ? '•' : marker));
      canContinueBullet = true;
      continue;
    }

    if (canContinueBullet && rawLine.startsWith(RegExp(r'[ \t]'))) {
      final previous = blocks.removeLast();
      blocks.add(_AnswerBlock(_BlockKind.bullet, '${previous.text}\n$line',
          marker: previous.marker));
    } else {
      canContinueBullet = false;
      paragraph.add(line);
    }
  }
  flushParagraph();
  return blocks;
}

double _blockGap(_AnswerBlock previous, _AnswerBlock current) {
  if (current.kind == _BlockKind.heading) return 12;
  if (previous.kind == _BlockKind.heading) return 8;
  if (previous.kind == _BlockKind.bullet && current.kind == _BlockKind.bullet) {
    return 6;
  }
  return 10;
}

List<InlineSpan> _inlineSpans(String text) {
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final match in _bold.allMatches(text)) {
    if (match.start > offset) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
    }
    spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700)));
    offset = match.end;
  }
  if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
  return spans;
}
