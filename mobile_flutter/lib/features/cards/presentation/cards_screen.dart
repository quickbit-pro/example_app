import '../../../shared/widgets/refresh_action.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../shared/shared.dart';
import '../../banking/application/banking_providers.dart';
import 'card_detail_screen.dart';
import '../../platform/application/platform_providers.dart';
import '../../../brands/example/example_tilt.dart';
import 'widgets/card_face.dart';
import 'widgets/card_ledger.dart';

class CardsScreen extends ConsumerWidget {
  const CardsScreen({this.initialCardId = '', super.key});

  final String initialCardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final isExample = ref.watch(appConfigProvider).branding.isExample;
    return dashboard.when(
      data: (snapshot) {
        if (snapshot.profile.isBusinessAccount) {
          return _CardsScaffold(
            body: EmptyState(
              title: context.tr('Cards are not included'),
              message: context.tr(
                  'This business template uses fiat accounts, transfers, and currency exchange.'),
              icon: Icons.account_balance_outlined,
            ),
          );
        }
        final detailedOverview = isExample;
        final cards = detailedOverview
            ? ref.watch(currentCardsProvider)
            : ref.watch(cardsProvider);
        return cards.when(
          data: (items) {
            if (items.isEmpty && !snapshot.canOrderCard) {
              return _CardsScaffold(
                body: _BankingRequired(
                  onContinue: () => context.go('/kyc/status'),
                ),
              );
            }
            // A single card or explicit card selection opens directly. Multiple
            // cards first show the roster so users can compare balances.
            final phone = MediaQuery.sizeOf(context).width < 820;
            final open = items
                .where((card) => card.status != CardStatus.cancelled)
                .toList();
            if (isExample &&
                phone &&
                open.isNotEmpty &&
                (open.length == 1 || initialCardId.isNotEmpty)) {
              final first = open.firstWhere(
                (card) => card.id == initialCardId,
                orElse: () => open.firstWhere(
                    (card) => card.status == CardStatus.active,
                    orElse: () => open.first),
              );
              return CardDetailScreen(
                key: ValueKey('cards-tab-${first.id}'),
                cardId: first.id,
                asTab: true,
              );
            }
            return _CardsScaffold(
              onOrderCard: snapshot.canOrderCard
                  ? () => context.go('/cards/order')
                  : null,
              body: _CardsContent(
                cards: items,
                initialCardId: initialCardId,
                isExample: isExample,
                onRefresh: () async {
                  ref.invalidate(cardDetailProvider);
                  ref.invalidate(cardsProvider);
                  await ref.read(currentCardsProvider.future);
                },
                onOpenCard: (card) => context.go('/cards/${card.id}'),
                onOrderCard: snapshot.canOrderCard
                    ? () => context.go('/cards/order')
                    : null,
              ),
            );
          },
          error: (error, stackTrace) => _CardsScaffold(
            body: ErrorState(
              error: error,
              onRetry: () {
                ref.invalidate(cardDetailProvider);
                ref.invalidate(cardsProvider);
              },
            ),
          ),
          loading: () => _CardsScaffold(
            body: LoadingState(label: context.tr('Loading cards')),
          ),
        );
      },
      error: (error, stackTrace) => _CardsScaffold(
        body: ErrorState(
          error: error,
          onRetry: () => ref.invalidate(dashboardProvider),
        ),
      ),
      loading: () => _CardsScaffold(
        body: LoadingState(label: context.tr('Checking card access')),
      ),
    );
  }
}

class _CardsScaffold extends ConsumerWidget {
  const _CardsScaffold({required this.body, this.onOrderCard});

  final Widget body;
  final VoidCallback? onOrderCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExample = context.isExampleTheme;
    final desktop = isExample &&
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Cards')),
        actions: [
          RefreshAction(onRefresh: () async {
            ref.invalidate(dashboardProvider);
            ref.invalidate(cardDetailProvider);
            ref.invalidate(cardTransactionsProvider);
            ref.invalidate(cardsProvider);
            await ref.read(currentCardsProvider.future);
          }),
          if (desktop) ...[
            if (onOrderCard != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  side: ExampleBorders.subtleSideOf(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                onPressed: onOrderCard,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(context.tr('Order card')),
              ),
          ] else ...[
            if (onOrderCard != null)
              TextButton(
                  onPressed: onOrderCard,
                  child: Text(context.tr('Order card'))),
            IconButton(
              tooltip: context.tr('Settings'),
              onPressed: () => context.go('/profile'),
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
      body: body,
    );
  }
}

class _CardsContent extends StatelessWidget {
  const _CardsContent({
    this.initialCardId = '',
    required this.cards,
    required this.isExample,
    required this.onRefresh,
    required this.onOpenCard,
    required this.onOrderCard,
  });

  final String initialCardId;
  final List<PaymentCard> cards;
  final bool isExample;
  final Future<void> Function() onRefresh;
  final ValueChanged<PaymentCard> onOpenCard;
  final VoidCallback? onOrderCard;

  @override
  Widget build(BuildContext context) {
    final openCards =
        cards.where((card) => card.status != CardStatus.cancelled).toList();
    final closedCards =
        cards.where((card) => card.status == CardStatus.cancelled).toList();
    final body = isExample
        ? _ExampleCardsView(
            key: ValueKey(initialCardId),
            initialCardId: initialCardId,
            openCards: openCards,
            closedCards: closedCards,
            onOpenCard: onOpenCard,
            onOrderCard: onOrderCard,
          )
        : _LegacyCardsView(
            cards: cards,
            openCards: openCards,
            closedCards: closedCards,
            onOpenCard: onOpenCard,
            onOrderCard: onOrderCard,
          );
    return RefreshIndicator(onRefresh: onRefresh, child: body);
  }
}

// ---------------------------------------------------------------------------
// Example: the wallet fans out.
// ---------------------------------------------------------------------------

/// The Example `/cards` screen.
///
/// The card is the subject, so it is the only thing above the fold: one face
/// at 92 % of the viewport, its neighbours peeking, and a hairline indicator
/// underneath. Everything below is the ledger for whichever card is on stage —
/// its balance as a [ExampleAmount], its month against its limit on a 2 pt
/// meter — and then the roster as a single [ExampleListGroup], which replaces
/// the old stack of glass panels each holding a shrunken card face (a card
/// inside a card, once per card).
///
/// The roster's rows carry the card, not a generic list glyph. Each one leads
/// with a [_CardMark] — the object's own silhouette in the brand's night
/// material, with its material and its state drawn into it — and states its
/// status in form first and in words only when the status is worth a word.
/// A row that is merely `Active` prints nothing about it, so a status word in
/// the column is always an exception rather than a default.
/// The card on the stage above takes the level-3 surface, which is the one
/// step in the ladder reserved for "the current card"; every other row stays
/// flat, so the group has a hierarchy instead of one uniform grey. A status
/// word off that fill is written in its own hue; on it the caption also
/// carries the positional note, which makes it a phrase rather than a label,
/// and a phrase there is body text on the ladder's brightest step — so it
/// steps off the hue and onto the secondary ink volume, which is the quietest
/// one that stays body-grade on that fill in both themes with the row's own
/// hover wash over it. See [_CardRosterRow] for the eight measurements.
///
/// The screen's one moment belongs to the artwork: the living card's single
/// specular pass once the route has settled. Nothing else animates on arrival.
/// The ledger — label, pill, amount and meter — cross-fades over
/// [ExampleMotion.state] when, and only when, the deck is paged to another
/// card, which is a response and not a greeting; under reduced motion it is an
/// instant swap. Nothing in the roster animates at all — a wallet index is a
/// utility list, and a screen gets one moment.
class _ExampleCardsView extends StatefulWidget {
  const _ExampleCardsView({
    super.key,
    this.initialCardId = '',
    required this.openCards,
    required this.closedCards,
    required this.onOpenCard,
    required this.onOrderCard,
  });

  final String initialCardId;
  final List<PaymentCard> openCards;
  final List<PaymentCard> closedCards;
  final ValueChanged<PaymentCard> onOpenCard;
  final VoidCallback? onOrderCard;

  @override
  State<_ExampleCardsView> createState() => _ExampleCardsViewState();
}

class _ExampleCardsViewState extends State<_ExampleCardsView> {
  int _index = 0;
  bool _showClosed = false;

  @override
  void initState() {
    super.initState();
    final requested =
        _deckCards.indexWhere((card) => card.id == widget.initialCardId);
    if (requested >= 0) _index = requested;
  }

  /// Cards the deck pages through: the live ones, or the closed ones when
  /// every card has been closed and there is nothing else to put on stage.
  List<PaymentCard> get _deckCards =>
      widget.openCards.isNotEmpty ? widget.openCards : widget.closedCards;

  @override
  void didUpdateWidget(covariant _ExampleCardsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = _deckCards.length;
    if (_index >= count) _index = count == 0 ? 0 : count - 1;
  }

  @override
  Widget build(BuildContext context) {
    final deck = _deckCards;
    if (deck.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, AppSpacing.xs, 20, 110),
        children: [
          EmptyState(
            title: context.tr('No cards yet'),
            message: context.tr('Order a card when your account is ready.'),
            icon: Icons.credit_card_off_outlined,
            // The one action an empty wallet has. It sits on the plain
            // scaffold, so the glass CTA goes opaque and keeps the silhouette
            // rather than dissolving into paper.
            action: ExampleGlassButton(
              label: context.tr('Order card'),
              icon: Icons.add_card_outlined,
              expand: false,
              onPressed: widget.onOrderCard,
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final selected = deck[_index.clamp(0, deck.length - 1)];
        // A 420pt card stage and a readable roster need desktop room.
        final content = constraints.maxWidth >= 1180
            ? _desktop(context, deck, selected)
            : _mobile(context, constraints.maxWidth, deck, selected);
        // One sheen clock per screen, so the living card's edge (and any host
        // added later) shares a schedule instead of starting its own ticker.
        if (ExampleSheenScope.existsAbove(context)) return content;
        return ExampleSheenScope(child: content);
      },
    );
  }

  // -- mobile ---------------------------------------------------------------

  Widget _mobile(
    BuildContext context,
    double width,
    List<PaymentCard> deck,
    PaymentCard selected,
  ) {
    if (width < 820 && widget.openCards.length > 1) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          _roster(context, listOnly: true),
          if (deck.any((card) => card.isEqualsMoney))
            const SafeguardingStatementButton(),
          const SizedBox(height: AppSpacing.lg),
          _orderPanel(context),
        ],
      );
    }
    // 92 % of the viewport: wide enough to be the subject, narrow enough that
    // the next card in the wallet shows its edge. The list keeps no horizontal
    // padding of its own so the deck can run wider than the text column.
    final cardWidth = (width * .92).clamp(0.0, 440.0);
    Widget inset(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: child,
        );
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.xxs, bottom: 110),
      children: [
        _CardDeck(
          cards: deck,
          index: _index,
          cardWidth: cardWidth,
          viewportFraction: ((cardWidth + 12) / width).clamp(.5, 1.0),
          onPageChanged: (value) => setState(() => _index = value),
          onOpenCard: widget.onOpenCard,
        ),
        if (deck.length > 1) _DeckIndicator(count: deck.length, index: _index),
        const SizedBox(height: AppSpacing.lg),
        inset(_ledger(context, selected)),
        if (deck.any((card) => card.isEqualsMoney))
          inset(const SafeguardingStatementButton()),
        const SizedBox(height: AppSpacing.lg),
        inset(_roster(context)),
        const SizedBox(height: AppSpacing.sm),
        inset(_orderPanel(context)),
      ],
    );
  }

  // -- desktop --------------------------------------------------------------

  Widget _desktop(
    BuildContext context,
    List<PaymentCard> deck,
    PaymentCard selected,
  ) {
    const stageWidth = 420.0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
      children: [
        if (deck.any((card) => card.isEqualsMoney))
          const SafeguardingStatementButton(),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: stageWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CardDeck(
                        cards: deck,
                        index: _index,
                        // 12 pt of gutter each side of a 420 pt stage: the
                        // deck's viewport clips, and at full width the card's
                        // ambient would be shaved flush with its own edge.
                        cardWidth: stageWidth - 24,
                        viewportFraction: 1,
                        onPageChanged: (value) =>
                            setState(() => _index = value),
                        onOpenCard: widget.onOpenCard,
                      ),
                      if (deck.length > 1)
                        _DeckIndicator(count: deck.length, index: _index),
                      const SizedBox(height: AppSpacing.lg),
                      _ledger(context, selected),
                      const SizedBox(height: AppSpacing.lg),
                      _orderPanel(context),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: _roster(context)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // -- shared pieces --------------------------------------------------------

  /// The ledger for [card], cross-faded when the deck moves to another card.
  ///
  /// The swipe is the user's action, so the numbers under the stage answer it
  /// rather than cutting. [ExampleStateSwitch] is the vocabulary's preset for
  /// exactly this — a component changing state in place — so the swap is
  /// spelled once there instead of re-derived here: the incoming ledger fades
  /// in and rises 2 pt over [ExampleMotion.state] on [ExampleMotion.arrive], the
  /// outgoing one leaves over three quarters of that ([ExampleMotion.exitOf])
  /// on [ExampleMotion.exit], and both collapse to [Duration.zero] under
  /// reduced motion because the preset reads its duration through
  /// [ExampleMotion.of]. A hand-rolled `AnimatedSwitcher` reuses `duration` for
  /// the reverse, which lets the outgoing ledger take as long to leave as the
  /// incoming one takes to arrive.
  ///
  /// Pinned to the top edge rather than the preset's centred default:
  /// [CardSpendMeter] collapses to the spend line alone on a card with no
  /// limit, so the two ledgers overlapping during the fade can be different
  /// heights. Centred, both would travel vertically for the length of the
  /// swap; topped, the label row stays where the reader left it.
  ///
  /// Keyed on the card's id and not on [_index], so a refresh that reorders
  /// the wallet without changing which card is on stage swaps nothing.
  ///
  /// This is not a second arrival moment: the switcher only ever runs when
  /// [_index] changes, and `_index` only changes on a page or a tap. On the
  /// first build the child arrives with the page, at rest.
  Widget _ledger(BuildContext context, PaymentCard card) => ExampleStateSwitch(
        alignment: Alignment.topCenter,
        child: _CardLedger(key: ValueKey(card.id), card: card),
      );

  Widget _roster(BuildContext context, {bool listOnly = false}) {
    final closed = widget.closedCards;
    final onStage = _deckCards;
    // Whether the closed cards are the wallet or an archive of it. Once every
    // card has been closed they are all there is: the deck stages one of them
    // (see [_deckCards]), so folding them behind a "Closed cards" disclosure
    // would leave the roster empty under a card that is plainly on screen, and
    // would break the invariant this group is built on — exactly one row
    // carries the level-3 fill, because exactly one card is on the stage.
    final closedAreTheWallet = widget.openCards.isEmpty && closed.isNotEmpty;
    // A row that knows whether it is the one on stage. Identity and not
    // equality: `onStage` is the very List instance `_deckCards` handed back,
    // so this asks "is the deck paging *this* list", which two equal lists of
    // cards would answer wrongly.
    Widget rowFor(List<PaymentCard> cards, int i) => _CardRosterRow(
          card: cards[i],
          current: !listOnly && identical(onStage, cards) && i == _index,
          showCurrency: listOnly,
          onTap: () => widget.onOpenCard(cards[i]),
        );
    return ExampleListGroup(
      title: context.tr('Your cards'),
      action: context.tr('Order card'),
      onAction: widget.onOrderCard,
      children: [
        for (var i = 0; i < widget.openCards.length; i++)
          rowFor(widget.openCards, i),
        if (closedAreTheWallet)
          for (var i = 0; i < closed.length; i++) rowFor(closed, i)
        else if (closed.isNotEmpty) ...[
          ExampleRow(
            leading: ExampleIconTile(
              icon: Icons.history_rounded,
              color: ExampleInk.accent(context, ExampleColors.lavender),
            ),
            title: _showClosed
                ? context.tr('Hide closed cards')
                : context.tr('Closed cards'),
            subtitle: closed.length == 1
                ? context.tr('1 card')
                : context.tr('{p0} cards', {'p0': closed.length}),
            trailing: Icon(
              _showClosed
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 20,
              color: ExampleInk.tertiary(context),
            ),
            semanticsLabel: _showClosed
                ? context.tr('Hide closed cards')
                : context.tr('Show {p0} closed cards', {'p0': closed.length}),
            onTap: () => setState(() => _showClosed = !_showClosed),
          ),
          if (_showClosed)
            // Never the current row: the deck is paging the open cards, so
            // the highlighted one is above, inside the first loop.
            for (final card in closed)
              _CardRosterRow(
                card: card,
                current: false,
                showCurrency: listOnly,
                onTap: () => widget.onOpenCard(card),
              ),
        ],
      ],
    );
  }

  Widget _orderPanel(BuildContext context) {
    return ExampleDashedPanel(
      onTap: widget.onOrderCard,
      child: Row(
        children: [
          Icon(
            Icons.add_rounded,
            size: 18,
            color: ExamplePalette.of(context).accent,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            context.tr('Order a new card'),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: ExampleInk.primary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pager. One page per card, each face at the ISO ratio, each one press
/// target announcing a single semantics node.
class _CardDeck extends StatefulWidget {
  const _CardDeck({
    required this.cards,
    required this.index,
    required this.cardWidth,
    required this.viewportFraction,
    required this.onPageChanged,
    required this.onOpenCard,
  });

  final List<PaymentCard> cards;
  final int index;
  final double cardWidth;
  final double viewportFraction;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<PaymentCard> onOpenCard;

  @override
  State<_CardDeck> createState() => _CardDeckState();
}

class _CardDeckState extends State<_CardDeck> {
  PageController? _controller;

  @override
  void didUpdateWidget(covariant _CardDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportFraction != widget.viewportFraction) {
      // A resize (rotation, or crossing the desktop breakpoint) changes the
      // viewport geometry, which a PageController fixes at construction.
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  PageController _pageController() => _controller ??= PageController(
        initialPage: widget.index,
        viewportFraction: widget.viewportFraction,
      );

  /// Room above and below the face for its own shadow.
  ///
  /// A `PageView` clips to its viewport, and the deck used to be exactly one
  /// card tall — so the living card's daylight seat (a contact shadow at y+2
  /// and the ambient at y+12 under a 26 pt blur) was sliced off flush with the
  /// artwork, and a dark card on paper went straight back to looking pasted
  /// on. 14 above covers the blur that reaches up past the offset; 40 below
  /// carries the full fall. On Twilight the same room lets the violet bloom
  /// finish instead of ending at a hard edge.
  static const double _shadowTop = 14;
  static const double _shadowBottom = 40;

  Widget _stage(Widget child) => Center(
        child: Padding(
          padding: const EdgeInsets.only(
            top: _shadowTop,
            bottom: _shadowBottom,
          ),
          child: SizedBox(width: widget.cardWidth, child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final height = CardFace.heightFor(widget.cardWidth);
    final stageHeight = height + _shadowTop + _shadowBottom;
    if (widget.cards.length == 1) {
      return SizedBox(
        height: stageHeight,
        child: _stage(
          _DeckCard(
            card: widget.cards.first,
            position: 1,
            total: 1,
            height: height,
            onTap: () => widget.onOpenCard(widget.cards.first),
          ),
        ),
      );
    }
    return SizedBox(
      height: stageHeight,
      child: PageView.builder(
        controller: _pageController(),
        itemCount: widget.cards.length,
        onPageChanged: widget.onPageChanged,
        itemBuilder: (context, index) {
          final card = widget.cards[index];
          return _stage(
            _DeckCard(
              card: card,
              position: index + 1,
              total: widget.cards.length,
              height: height,
              // Only the card the screen arrives on greets the user.
              sweepOnArrival: index == widget.index,
              onTap: () => widget.onOpenCard(card),
            ),
          );
        },
      ),
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.card,
    required this.position,
    required this.total,
    required this.height,
    required this.onTap,
    this.sweepOnArrival = true,
  });

  final PaymentCard card;
  final int position;
  final int total;
  final double height;
  final VoidCallback onTap;
  final bool sweepOnArrival;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ExamplePressable(
        onTap: onTap,
        // A 361 pt face travels too far at the button scale; .985 is the same
        // press the list rows use.
        pressedScale: .985,
        borderRadius: BorderRadius.circular(AppRadii.md),
        semanticsLabel: _deckSemantics(card, position, total),
        child: ExampleTiltCard(
          child: CardFace(
            showBalance: true,
            card: card,
            height: height,
            status: card.status,
            frozen: card.status == CardStatus.frozen,
            sweepOnArrival: sweepOnArrival,
            enableHoverTilt: false,
          ),
        ),
      ),
    );
  }
}

String _deckSemantics(PaymentCard card, int position, int total) {
  final parts = <String>[
    card.displayLabel,
    if (card.last4.isNotEmpty) 'ending ${card.last4.split('').join(' ')}',
    card.statusLabel.toLowerCase(),
    card.hasReportedBalance
        ? 'balance ${card.balance.formatted} ${card.balance.currency}'
        : 'Balance unavailable',
    if (total > 1) 'card $position of $total',
  ];
  return '${parts.join(', ')}. Open card';
}

/// Visible page markers for every card, with a longer accent marker for the
/// current selection and contrasting dots for the remaining cards.
class _DeckIndicator extends StatelessWidget {
  const _DeckIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return Semantics(
      label: context.tr('Card {p0} of {p1}', {'p0': index + 1, 'p1': count}),
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                Container(
                  key: ValueKey('card-deck-indicator-$i'),
                  width: i == index ? 22 : 6,
                  height: 6,
                  margin: EdgeInsets.symmetric(horizontal: count > 10 ? 2 : 4),
                  decoration: BoxDecoration(
                    color: i == index
                        ? ExampleInk.accent(context, palette.accent)
                        : ExampleInk.secondary(context),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
          if (count > 5) ...[
            const SizedBox(height: 8),
            Text(
              context.tr('{p0} of {p1}', {'p0': index + 1, 'p1': count}),
              style: TextStyle(
                fontSize: 12,
                color: ExampleInk.secondary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The ledger for the card on stage: who it is, what it holds, and how far
/// through its month it is. No panel — the numbers rest on the page, which is
/// what keeps a card from sitting inside a card.
class _CardLedger extends StatelessWidget {
  /// [key] carries the staged card's id so [_ExampleCardsViewState._ledger]'s
  /// switcher can tell one card's ledger from the next one's.
  const _CardLedger({required this.card, super.key});

  final PaymentCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `Active` is the state a card is in, so saying it here says nothing: the
    // artwork 60 pt above already prints its own status pill, and a screen
    // that repeats the default twice in one column has spent an accent on
    // silence. The pill appears only when the status is an exception — and
    // then it is the one coloured object under the card.
    final exceptional = card.status != CardStatus.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                card.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ExampleInk.primary(context),
                ),
              ),
            ),
            if (exceptional) ...[
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ExamplePill(
                  label: card.statusLabel,
                  color: _statusColor(context, card.status),
                  dot: true,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          cardMetaLine(card, context: context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          semanticsLabel: cardMetaSemantics(card, context: context),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.3,
            color: ExampleInk.secondary(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(context.tr('CARD BALANCE'),
            style: ExampleTextStyles.label(context)),
        const SizedBox(height: AppSpacing.xxs),
        ExampleAmount(
          amount: card.balance.minorUnits / 100,
          currency: card.balance.currency,
        ),
        const SizedBox(height: AppSpacing.md),
        CardSpendMeter(
          spent: card.spendThisMonth.minorUnits.abs() / 100,
          limit: card.limit.minorUnits / 100,
          currency: card.spendThisMonth.currency,
        ),
      ],
    );
  }
}

/// One card in the roster. A row, not a tile: the artwork already has a stage.
///
/// Reachable only from [_ExampleCardsView], so everything here is Example by
/// construction and carries no `isExample` gate; the white-label roster is
/// `_CardRow` further down and is untouched.
class _CardRosterRow extends StatelessWidget {
  const _CardRosterRow({
    this.showCurrency = false,
    required this.card,
    required this.current,
    required this.onTap,
  });

  final PaymentCard card;
  final bool showCurrency;

  /// True for the card the deck is showing. Marks the row, and is the only
  /// thing on the screen that ties the roster to the stage.
  final bool current;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final frozen = card.status == CardStatus.frozen;
    final status = card.status == CardStatus.active ? null : card.statusLabel;
    // Both facts, in the order they matter, on the one caption line the row
    // has. They are not mutually exclusive: a frozen card is an open card, so
    // it sits in the deck like any other and the wallet can be paged straight
    // to it — at which point the row is the current one *and* the exception.
    // Dropping either would lie. Losing the status would put a warning on a
    // card that reads as usable; losing "On screen" would leave the level-3
    // fill with nothing explaining it, and that word is the only thing tying
    // the roster to the stage for a reader who is not counting fills.
    //
    // The status leads because it is what changes what the card can do. The
    // separator is the one `cardMetaLine` joins with, so the halves of a
    // caption read the way the halves of an identity line do.
    final caption = [
      if (showCurrency) card.balance.currency,
      if (status != null) status,
      if (current) 'On screen',
    ].join(' · ');
    Widget row = ExampleRow(
      leading: _CardMark(card: card),
      title: card.displayLabel,
      subtitle: context.tr(_metaLine(card)),
      trailing: ExampleRowValue(
        value: card.hasReportedBalance
            ? card.balance.formatted
            : context.tr('Balance unavailable'),
        // Money on a frozen card is there and cannot move, so it is stated at
        // the secondary volume rather than the primary one — still body-grade
        // on both grounds this row ever paints on: 7.79:1 on the group's
        // level-1 surface and 7.09:1 on the level-3 fill in daylight, 7.63:1
        // and 6.74:1 on Twilight. Those four are the resting figures; the row
        // paints `ExampleInk.hover` over whichever of them it is on while a
        // pointer rests on it, and the quietest of the eight is 6.29:1
        // (Twilight, hovered level-3 fill). `ExampleInk.secondary` is one of the
        // values `accentFor` returns untouched, so passing it here is a no-op
        // on both branches instead of a hue the palette would try to deepen.
        color: frozen ? ExampleInk.secondary(context) : null,
        // A row that is neither an exception nor on stage prints nothing,
        // which is what makes the ones that do print legible.
        caption: caption.isEmpty ? null : caption,
        // The ink follows what the caption *is*, not only what it says.
        //
        // Every ratio below is WCAG 2.1 on the ground this row actually
        // paints, composited in paint order — group fill, then the level-3
        // `ColoredBox` when the row is current, then `ExampleInk.hover` (the
        // theme's ink at .04) while a pointer rests on the row, then the text.
        // The hovered figure is quoted beside the resting one everywhere,
        // because a caption is most likely to be read exactly when a pointer
        // is on its row, and the wash is not negligible: on the level-3 fill
        // in Twilight it costs the tertiary volume 0.23 of a ratio point,
        // which is more than the 0.16 of headroom that volume had.
        //
        // A lone status word is a one-word label, and it can only appear on a
        // row that is *not* current — a current row's caption always carries
        // "On screen" as well — so its ground is the group's own level-1
        // surface, which every non-current row sits on (the closed ones
        // included: they are children of the same `ExampleListGroup`, whether
        // listed outright or opened out of the disclosure). All three statuses
        // that can reach this line — frozen, pending, cancelled; `active`
        // prints no word at all — clear the body floor on that surface in both
        // themes, hovered as well as at rest. The tightest of the six figures
        // is daylight `frozen` hovered at 4.87:1; the tightest at rest is
        // daylight `cancelled` at 5.09:1.
        //
        // The composed caption is not a label. `Frozen · On screen` is
        // eighteen characters of 12 pt regular — normal-size body text, which
        // owes 4.5:1 — and it exists only on a current row, which is exactly
        // the row wearing the level-3 fill below. Two of the inks it could
        // take are ruled out on that fill:
        //
        // * the status hue, because daylight `warning` on it is 4.42:1
        //   (#8F5E0C on #EAE1FC, the figure `lightWarning` records for itself)
        //   before the row is hovered at all;
        // * the tertiary volume, because Twilight tertiary is 4.66:1 on the
        //   resting fill but 4.43:1 once the hover wash is over it — pearl .53
        //   over pearl .04 over #221C56 — so the phrase would fall under the
        //   floor for exactly as long as the pointer is on the row. Daylight
        //   survives the same wash at 4.65:1, which is why this is a Twilight
        //   defect and a both-themes repair.
        //
        // So it takes the secondary volume: of the three ink volumes it is the
        // quietest one that clears on that fill in both themes *and* in both
        // hover states — 6.74:1 / 6.29:1 Twilight and 7.09:1 / 6.79:1 daylight,
        // resting / hovered. One rule for both themes, because a row that reads
        // differently per theme is a rule nobody can hold. The state is not
        // lost with the colour: the word still leads the line, the mark
        // carries the frost, and the balance beside it is at this same volume.
        //
        // Secondary is also what a row that is *only* current takes, because
        // there the fill is the signal and a positional note must not read as
        // a status. `ExampleRowValue` resolves a null `captionColor` to this
        // same volume, so naming it changes no pixel; it is named so the
        // choice is the thing under test rather than an inherited default, and
        // it is one of the values `accentFor` returns untouched, so it
        // resolves to itself in both themes.
        captionColor: status == null || current
            ? ExampleInk.secondary(context)
            : _statusColor(context, card.status),
      ),
      semanticsLabel:
          '${card.displayLabel}, ${cardMetaSemantics(card, context: context)}, '
          '${card.statusLabel.toLowerCase()}, balance ${card.hasReportedBalance ? '${card.balance.formatted} ${card.balance.currency}' : 'Balance unavailable'}'
          '${current ? ', showing on screen' : ''}',
      onTap: onTap,
    );
    if (current) {
      // Depth spent by role rather than stamped on every block: exactly one
      // row in the roster is the card on the stage, and level 3 is the step
      // the ladder reserves for "the one selected or highlighted element …
      // the current card". The group clips it to its own corners, and the
      // row's hover wash still paints over the top of it — which is why the
      // caption above is measured on the hovered composite of this fill and
      // not on the fill alone.
      row = ColoredBox(color: ExampleSurface.of(context, 3), child: row);
    }
    return row;
  }

  /// The roster's identity line: the last four digits, and nothing else.
  ///
  /// The ledger keeps [cardMetaLine]'s full form — digits, material, network —
  /// because it is the one place the card on the stage is described in words,
  /// and it has the whole column to say it in. The roster does not: between a
  /// 40 pt mark and a balance, the subtitle is the narrowest thing on the
  /// screen, and at a 1.3 text scale on a 375 pt phone the full line
  /// ellipsised — which is the failure mode a screenshot hides.
  ///
  /// So the row keeps the one string that identifies a card and drops the two
  /// that are drawn or printed elsewhere. The material is now in the
  /// [_CardMark] itself — a chip for a physical card, the contactless arcs for
  /// a virtual one — and the network is stamped on the artwork directly above
  /// (`MASTERCARD · METAL`) and stated again on the detail screen. Repeating
  /// either in 12 pt prose spends the row's tightest column on something the
  /// reader can already see.
  ///
  /// A card that has no digits yet is the one case where that leaves nothing
  /// at all, so it falls back to its material. An unissued card — the shape
  /// this screen's own placeholder takes, `last4: ''` and `CardStatus.pending`
  /// — would otherwise print a nickname over a blank line, which reads as a
  /// row that failed to load rather than a card that has not been made yet.
  /// The rule above still holds: the material is only repeated in words when
  /// it is the sole thing left to say.
  ///
  /// The screen-reader label is untouched: [cardMetaSemantics] still says
  /// "virtual" or "physical" and names the network, because a mark is not
  /// something a screen reader can look at.
  static String _metaLine(PaymentCard card) => card.last4.isEmpty
      ? (card.virtual ? 'Virtual' : 'Physical')
      : '•••• ${card.last4}';
}

/// Provider artwork in the roster's compact card slot. Missing or failed
/// images use a neutral placeholder, never a substitute card design.
class _CardMark extends StatelessWidget {
  const _CardMark({required this.card});

  final PaymentCard card;

  /// [ExampleRow.leadingSize]. The height comes from [CardFace.aspectRatio], so
  /// the roster and the stage agree on the shape of a card.
  static const double _width = ExampleRow.leadingSize;
  static const double _radius = 5;

  @override
  Widget build(BuildContext context) {
    final status = card.status;
    final artworkUrl = card.cardThumbnailUrl.trim().isNotEmpty
        ? card.cardThumbnailUrl
        : card.artworkUrl;
    final placeholder = ColoredBox(
      color: ExampleSurface.of(context, 2),
      child: Center(
        child: Icon(
          Icons.credit_card_outlined,
          size: 15,
          color: ExampleInk.tertiary(context),
        ),
      ),
    );
    // Structural edges, not control boundaries — the row is the control, and
    // `ExampleBorders` is explicit that its hairlines sit under 3:1 by design.
    // Frozen borrows the .30 the artwork's own status pill uses for its edge.
    final edge = switch (status) {
      CardStatus.frozen => context.brandDesign
          .color(Theme.of(context).brightness, 'warning',
              fallback: ExampleColors.warning)
          .withValues(alpha: .30),
      CardStatus.pending => context.brandDesign.color(
          Theme.of(context).brightness, 'borderEmphasis',
          fallback: ExampleColors.borderEmphasis),
      CardStatus.cancelled => context.brandDesign
          .color(Theme.of(context).brightness, 'borderSubtle',
              fallback: ExampleColors.lavender)
          .withValues(alpha: .14),
      CardStatus.active => context.brandDesign
          .color(Theme.of(context).brightness, 'borderSubtle',
              fallback: ExampleColors.lavender)
          .withValues(alpha: .30),
    };

    Widget mark = ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (artworkUrl.trim().isEmpty)
            placeholder
          else
            Image.network(
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              artworkUrl,
              key: ValueKey('example-roster-artwork-$artworkUrl'),
              fit: BoxFit.cover,
              semanticLabel: card.cardImageAlt.isEmpty
                  ? context.tr('Card design')
                  : card.cardImageAlt,
              excludeFromSemantics: true,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : placeholder,
              errorBuilder: (_, __, ___) => placeholder,
            ),
          if (status == CardStatus.frozen) const _FrostPass(),
        ],
      ),
    );
    mark = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: edge),
      ),
      child: mark,
    );
    if (status == CardStatus.cancelled) {
      mark = Opacity(opacity: ExampleOpacity.disabled, child: mark);
    }
    return RepaintBoundary(
      child: SizedBox(
        width: _width,
        height: CardFace.heightFor(_width),
        child: mark,
      ),
    );
  }
}

/// The freeze, at row scale: the living card's wash, hatched.
class _FrostPass extends StatelessWidget {
  const _FrostPass();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          // The same two stops `ExampleLivingCard` lays over frozen artwork —
          // pearl .13 into lavender .08 — which turns the indigo cold without
          // introducing a second hue.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              context.brandDesign
                  .color(Theme.of(context).brightness, 'cardForeground',
                      fallback: ExampleColors.pearl)
                  .withValues(alpha: .13),
              context.brandDesign
                  .color(Theme.of(context).brightness, 'cardDecoration',
                      fallback: ExampleColors.lavender)
                  .withValues(alpha: .08),
            ],
          ),
        ),
        child: CustomPaint(
            painter: _FrostHatchPainter(
                color: context.brandDesign
                    .color(Theme.of(context).brightness, 'cardForeground',
                        fallback: ExampleColors.pearl)
                    .withValues(alpha: .22))),
      );
}

/// Diagonal hairlines on a 9 pt pitch. Static, and clipped by the mark's own
/// [ClipRRect], so it never repaints and allocates nothing per frame.
class _FrostHatchPainter extends CustomPainter {
  const _FrostHatchPainter({required this.color});

  final Color color;

  static const double _pitch = 9;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      // Pearl .22 on the frosted roll: bright enough to read as ice at 40 pt,
      // quiet enough that the mark is still a card and not a warning sign.
      ..color = color;
    for (var x = -size.height; x < size.width; x += _pitch) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FrostHatchPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// White-label: unchanged rendering.
// ---------------------------------------------------------------------------

class _LegacyCardsView extends StatefulWidget {
  const _LegacyCardsView({
    required this.cards,
    required this.openCards,
    required this.closedCards,
    required this.onOpenCard,
    required this.onOrderCard,
  });

  final List<PaymentCard> cards;
  final List<PaymentCard> openCards;
  final List<PaymentCard> closedCards;
  final ValueChanged<PaymentCard> onOpenCard;
  final VoidCallback? onOrderCard;

  @override
  State<_LegacyCardsView> createState() => _LegacyCardsViewState();
}

class _LegacyCardsViewState extends State<_LegacyCardsView> {
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final openCards = widget.openCards;
    final closedCards = widget.closedCards;
    final summaryCard = openCards.firstWhere(
      (card) => card.status == CardStatus.active,
      orElse: () =>
          openCards.firstOrNull ??
          widget.cards.firstOrNull ??
          PaymentCard(
            id: '',
            label: context.tr('Card'),
            last4: '',
            network: '',
            currency: 'USD',
            status: CardStatus.pending,
            balance: const Money(currency: 'USD', minorUnits: 0),
            spendThisMonth: const Money(currency: 'USD', minorUnits: 0),
            limit: const Money(currency: 'USD', minorUnits: 0),
            virtual: true,
          ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        110,
      ),
      children: [
        if (widget.cards.any((card) => card.isEqualsMoney))
          const SafeguardingStatementButton(),
        if (widget.cards.isEmpty)
          EmptyState(
            title: context.tr('No cards yet'),
            message: context.tr('Order a card when your account is ready.'),
            icon: Icons.credit_card_off_outlined,
            action: FilledButton.icon(
              onPressed: widget.onOrderCard,
              icon: const Icon(Icons.add_card_outlined),
              label: Text(context.tr('Order card')),
            ),
          )
        else ...[
          _SpendingSummary(card: summaryCard, cards: openCards),
          const SizedBox(height: AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: context.tr('Your cards'),
                actionLabel: context.tr('Order card'),
                onAction: widget.onOrderCard,
              ),
              const SizedBox(height: AppSpacing.sm),
              NeoGroupedCard(
                children: [
                  for (final card in openCards)
                    _CardRow(
                      card: card,
                      onTap: () => widget.onOpenCard(card),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onOrderCard,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.tr('Order a new card')),
                ),
              ),
              if (closedCards.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showClosed = !_showClosed),
                    icon: Icon(
                      _showClosed
                          ? Icons.expand_less_rounded
                          : Icons.history_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _showClosed
                          ? context.tr('Hide closed cards')
                          : context.tr('View closed cards'),
                    ),
                  ),
                ),
                if (_showClosed)
                  NeoGroupedCard(
                    children: [
                      for (final card in closedCards)
                        _CardRow(
                          card: card,
                          onTap: () => widget.onOpenCard(card),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _SpendingSummary extends StatelessWidget {
  const _SpendingSummary({required this.card, required this.cards});

  final PaymentCard card;
  final List<PaymentCard> cards;

  @override
  Widget build(BuildContext context) {
    final active =
        cards.where((item) => item.status == CardStatus.active).length;
    final frozen =
        cards.where((item) => item.status == CardStatus.frozen).length;
    return NeoSurfaceCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Card spending'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  card.spendThisMonth.formatted,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  context.tr('this month'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          _CountMetric(value: active.toString(), label: context.tr('Active')),
          const SizedBox(width: AppSpacing.md),
          _CountMetric(value: frozen.toString(), label: context.tr('Frozen')),
        ],
      ),
    );
  }
}

class _CountMetric extends StatelessWidget {
  const _CountMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.card, required this.onTap});

  final PaymentCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 66,
        height: 42,
        child: Container(
          decoration: BoxDecoration(
            color: _statusColor(context, card.status).withValues(alpha: .13),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          clipBehavior: Clip.antiAlias,
          child: card.artworkUrl.isEmpty
              ? Icon(
                  card.virtual
                      ? Icons.wifi_tethering_rounded
                      : Icons.credit_card_rounded,
                  color: _statusColor(context, card.status),
                )
              : Image.network(
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  card.cardThumbnailUrl.isNotEmpty
                      ? card.cardThumbnailUrl
                      : card.artworkUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.credit_card_rounded,
                    color: _statusColor(context, card.status),
                  ),
                ),
        ),
      ),
      title: Text(fallbackText(card.label, 'Card')),
      isThreeLine: true,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '•••• ${card.last4.isEmpty ? '—' : card.last4}',
                  maxLines: 1,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                card.balance.formatted,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          Text(
            [
              card.providerLabel,
              context.tr(card.virtual ? 'Virtual' : 'Physical'),
              if (card.network.trim().isNotEmpty) cardNetworkName(card.network),
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(
            label: card.statusLabel,
            tone: _statusTone(card.status),
          ),
          const SizedBox(width: AppSpacing.xs),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _BankingRequired extends StatelessWidget {
  const _BankingRequired({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          title: context.tr('Card verification pending'),
          message: context.tr(
              'Interlace must approve your verification before you can order a card.'),
          icon: Icons.verified_user_outlined,
          action: FilledButton(
            onPressed: onContinue,
            child: Text(context.tr('View verification status')),
          ),
        ),
      ),
    );
  }
}

FinanceStatusTone _statusTone(CardStatus status) {
  return switch (status) {
    CardStatus.active => FinanceStatusTone.success,
    CardStatus.frozen => FinanceStatusTone.warning,
    CardStatus.pending => FinanceStatusTone.info,
    CardStatus.cancelled => FinanceStatusTone.neutral,
  };
}

/// Status ink for the active theme. Twilight keeps today's tokens; daylight
/// takes the re-darkened pair from the palette, so a status never reads as
/// neon on paper.
Color _statusColor(BuildContext context, CardStatus status) {
  if (context.isExampleTheme) return exampleStatusInk(context, status);
  return context.brandDesign.color(
    Theme.of(context).brightness,
    switch (status) {
      CardStatus.active => 'success',
      CardStatus.frozen => 'warning',
      CardStatus.pending => 'warning',
      CardStatus.cancelled => 'textSecondary',
    },
    fallback: HoppaColors.statusColor(_statusTone(status)),
  );
}
