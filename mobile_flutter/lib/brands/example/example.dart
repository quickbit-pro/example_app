/// The Example Twilight design system in one import.
///
/// Colours and material tokens ([ExampleColors], [ExampleBorders],
/// [ExampleShadows], [ExampleSurface], [ExampleOpacity], plus the shared
/// [AppSpacing] and [AppRadii]), motion ([ExampleMotion], [ExamplePressable],
/// [ExampleStateSwitch]), type ([ExampleFonts], [ExampleTypography],
/// [ExampleTextStyles], [ExampleAmountSize]), the component vocabulary in
/// `example_ui.dart`, the backdrop ([ExampleAtmosphere]), money and machine
/// strings ([ExampleAmount], [ExampleMono]), loading ([ExampleSkeleton]), empty
/// and error states ([ExampleEmptyState], [ExampleErrorState]), the alive layer
/// ([ExampleSheenScope], [ExampleSheen]), the brand mark and loader, and the
/// route handoff ([ExampleRouteTransition]).
///
/// Both themes ship from here. Twilight and Pearl daylight are resolved by
/// [ExamplePalette] and by the `of(context)` helpers on [ExampleSurface],
/// [ExampleInk], [ExampleBorders] and [ExampleShadows]; a screen never names a
/// brightness-specific literal.
///
/// Use this from screens written from wave 1 on. Screens that already import
/// `example_ui.dart` next to `example_colors.dart` or `app_spacing.dart` keep
/// those imports; swapping them for this barrel is a one-line change per
/// file, and mixing the two styles in one file only earns an
/// `unnecessary_import` hint.
///
/// Nothing here renders for another brand: every widget gates on
/// `context.isExampleTheme` or lives only inside Example screens, so importing
/// the barrel never changes a white-label build.
library;

export 'example_amount.dart';
export 'example_atmosphere.dart';
export 'example_colors.dart';
export 'example_glass_button.dart';
export 'example_mark.dart';
export 'example_motion.dart';
export 'example_route_transition.dart';
export 'example_sheen.dart';
export 'example_skeleton.dart';
export 'example_states.dart';
export 'example_tokens.dart';
export 'example_typography.dart';
export 'example_ui.dart';
