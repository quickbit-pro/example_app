import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/app_states.dart' show friendlyErrorMessage;
import 'example_mark.dart';
import 'example_tokens.dart';
import 'example_ui.dart' show ExampleThemeContext;

/// Empty state for a Example list, panel or screen.
///
/// One glyph, one headline, one line of body, at most one primary and one
/// text action, centred and no wider than 320 px so it holds at 375 px. No
/// card around it: an empty state is content, not a component, and the
/// space around it is the point. The glyph is the brand mark by default (a
/// quiet reminder of whose product this is when there is nothing else on
/// the screen); pass [icon] when the section has its own symbol (a card, a
/// coin, a bell).
///
/// Write the title as what the user can do or expect, not as an absence:
/// "Your first card is a tap away" over "No cards". The body is one line.
/// The primary action, if any, is the single most useful next step.
///
/// [compact] is for an empty section inside a page (the activity panel
/// before the first transaction): smaller glyph, title-size type, tighter
/// spacing. The default is for a whole screen or tab.
class ExampleEmptyState extends StatelessWidget {
  const ExampleEmptyState({
    required this.title,
    this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
    super.key,
  });

  /// Headline. Say what comes next, not what is missing.
  final String title;

  /// One supporting line in the secondary text tone. Optional.
  final String? body;

  /// Replaces the brand mark in the glyph circle. Tinted with the brand
  /// accent for the current theme (`iris` at night, a daylight violet ink on
  /// paper).
  final IconData? icon;

  /// Primary action label; renders a `FilledButton` when non-null.
  final String? actionLabel;

  /// Primary action. A null callback with a label renders the button
  /// disabled.
  final VoidCallback? onAction;

  /// Text action under the primary ("Learn more", "Not now").
  final String? secondaryLabel;

  /// Secondary action.
  final VoidCallback? onSecondary;

  /// Section-sized composition for an empty panel inside a page.
  final bool compact;

  @override
  Widget build(BuildContext context) => _StateComposition(
        glyph: icon == null
            ? _Glyph.mark(compact: compact)
            : _Glyph.icon(icon!, tint: _GlyphTint.accent, compact: compact),
        title: title,
        body: body,
        primaryLabel: actionLabel,
        onPrimary: onAction,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
        compact: compact,
        liveRegion: false,
      );
}

/// Error state for a Example list, panel or screen, with a retry.
///
/// Same composition as [ExampleEmptyState]. The danger token appears once,
/// as the icon tint; the title, body and button stay in the resting
/// palette so the screen reads as calm and recoverable rather than alarmed.
/// The whole state is a live region, so assistive technology announces it
/// when it replaces loading content.
///
/// Pass [error] to derive the body through `friendlyErrorMessage` (the same
/// mapping the generic `ErrorState` uses), or [body] to say something more
/// specific; [body] wins when both are given. The account-provisioning
/// special case (502/503/504 right after registration) stays in
/// `lib/core/widgets/app_states.dart`; route through `ErrorState` there
/// when that behaviour matters.
class ExampleErrorState extends StatelessWidget {
  const ExampleErrorState({
    this.title = 'Something went wrong',
    this.body,
    this.error,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.icon = Icons.cloud_off_rounded,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
    super.key,
  });

  /// Headline.
  final String title;

  /// One supporting line. Overrides the message derived from [error].
  final String? body;

  /// The failure, mapped to a friendly one-liner when [body] is null.
  final Object? error;

  /// Retry. Renders the primary button when non-null.
  final VoidCallback? onRetry;

  /// Label of the retry button.
  final String retryLabel;

  /// Glyph icon, tinted with the danger ink for the current theme.
  final IconData icon;

  /// Text action under the retry ("Contact support", "Go back").
  final String? secondaryLabel;

  /// Secondary action.
  final VoidCallback? onSecondary;

  /// Section-sized composition for a failed panel inside a page.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final message =
        body ?? (error == null ? null : friendlyErrorMessage(error));
    return _StateComposition(
      glyph: _Glyph.icon(icon, tint: _GlyphTint.danger, compact: compact),
      title: title,
      body: message,
      primaryLabel: onRetry == null ? null : retryLabel,
      primaryIcon: Icons.refresh_rounded,
      onPrimary: onRetry,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
      compact: compact,
      liveRegion: true,
    );
  }
}

/// Shared layout of the two states. Vertical rhythm on the 4 pt scale:
/// glyph, 16 (12 compact), title, 8, body, 24 (16 compact), actions, 4.
class _StateComposition extends StatelessWidget {
  const _StateComposition({
    required this.glyph,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.compact,
    required this.liveRegion,
    this.primaryIcon,
  });

  final Widget glyph;
  final String title;
  final String? body;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool compact;
  final bool liveRegion;

  /// Measure cap so the body stays near 40 characters a line at 14 px.
  static const double _maxWidth = 320;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    // Body ink by role: pearl .68 at night, night .72 on paper. The title
    // takes the theme's on-surface ink and the two actions take the themed
    // button colours, which already resolve per brightness, so nothing here
    // forks a colour the theme owns.
    final secondary = isExample
        ? ExamplePalette.of(context).textSecondary
        : theme.colorScheme.onSurfaceVariant;
    final titleStyle =
        compact ? theme.textTheme.titleMedium : theme.textTheme.headlineSmall;
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(color: secondary);
    final body = this.body?.trim();
    final hasActions = primaryLabel != null || secondaryLabel != null;

    return Semantics(
      liveRegion: liveRegion,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: compact ? AppSpacing.md : AppSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                glyph,
                SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                Semantics(
                  header: true,
                  child: Text(
                    context.tr(title),
                    textAlign: TextAlign.center,
                    style: titleStyle,
                  ),
                ),
                if (body != null && body.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.tr(body),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle,
                  ),
                ],
                if (hasActions)
                  SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                if (primaryLabel != null)
                  primaryIcon == null
                      ? FilledButton(
                          onPressed: onPrimary,
                          child: Text(context.tr(primaryLabel!)),
                        )
                      : FilledButton.icon(
                          onPressed: onPrimary,
                          icon: Icon(primaryIcon, size: 18),
                          label: Text(context.tr(primaryLabel!)),
                        ),
                if (secondaryLabel != null) ...[
                  if (primaryLabel != null)
                    const SizedBox(height: AppSpacing.xxs),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                    ),
                    onPressed: onSecondary,
                    child: Text(context.tr(secondaryLabel!)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the glyph icon means, resolved to an ink for the current theme
/// rather than fixed at the call site: the same symbol has to hold 3:1
/// against a night surface and against white.
enum _GlyphTint { accent, danger }

/// The glyph circle.
///
/// At night it is a level-2 disc with a subtle edge — depth by surface, the
/// Twilight way. In daylight the same disc turns white on the lavender
/// paper, keeps the lavender hairline and floats on one soft shadow — depth
/// by light, the daylight way. The two read with the same weight: the dark
/// disc separates from its page at 1.25:1, and the shadow under the white
/// one reaches 1.33:1 at its core.
///
/// Both hold the mark or an icon at half the disc's diameter, and the icon
/// clears 3:1 on its own ground in either theme (`iris` 5.9:1 on level 2,
/// `lightIris` 6.2:1 on white; `danger` 5.6:1 and `lightDanger` 5.1:1). Decorative, so it is excluded from
/// semantics; the title carries the meaning.
class _Glyph extends StatelessWidget {
  const _Glyph.mark({required this.compact})
      : icon = null,
        tint = null;

  const _Glyph.icon(IconData this.icon,
      {required _GlyphTint this.tint, required this.compact});

  final IconData? icon;
  final _GlyphTint? tint;
  final bool compact;

  Color _tint(ThemeData theme, ExamplePalette palette, bool isExample) =>
      switch (tint!) {
        _GlyphTint.accent =>
          isExample ? palette.accent : theme.colorScheme.primary,
        _GlyphTint.danger =>
          isExample ? palette.danger : theme.colorScheme.error,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    final palette = ExamplePalette.of(context);
    final light = isExample && !palette.isDark;
    final size = compact ? 40.0 : 56.0;
    final inner = size * .5;
    // The one place the themes take different roles rather than different
    // values: at night the disc is the level-2 surface (depth by surface);
    // in daylight it is the white panel surface lifted off the paper by one
    // ambient shadow (depth by light).
    final fill = isExample
        ? (palette.isDark ? palette.surfaceSubtle : palette.surface)
        : theme.colorScheme.surfaceContainerHighest;
    final edge = isExample
        ? BorderSide(color: palette.borderSubtle)
        : BorderSide(color: theme.colorScheme.outlineVariant);
    final icon = this.icon;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.fromBorderSide(edge),
          boxShadow: light
              ? [
                  BoxShadow(
                    color: palette.shadowLift,
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                    spreadRadius: -6,
                  )
                ]
              : null,
        ),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: icon == null
                ? ExampleMark(size: inner)
                : Icon(
                    icon,
                    size: inner,
                    color: _tint(theme, palette, isExample),
                  ),
          ),
        ),
      ),
    );
  }
}
