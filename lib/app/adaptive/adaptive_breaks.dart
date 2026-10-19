/// Layout breakpoints and size classes (Module 46).
///
/// One place decides what "a phone" and "a clinical tablet" mean, so the
/// shell, the surfaces and the components all change their shape at the same
/// widths. The classes follow the target devices in the specification:
///
/// * compact — a 6" phone: bottom navigation, compact cards, one column.
/// * medium — an 8" tablet: a navigation rail, collapsible side sheets,
///   two-column cards.
/// * expanded — an 11–13" clinical tablet: a permanent rail, a master/detail
///   workspace, multi-column clinical sheets.
///
/// The ergonomic rule travels with them: nothing a clinician taps in gloves is
/// smaller than 48dp.
library;

/// The widths at which the layout changes.
abstract final class NodexBreakpoints {
  /// Below this width the layout is a phone layout.
  static const double compact = 600;

  /// At or above this width and below [expanded] the layout is a tablet
  /// layout.
  static const double medium = 600;

  /// At or above this width the layout is a clinical-tablet layout with room
  /// for a master/detail workspace.
  static const double expanded = 1000;
}

/// The smallest touch target a clinician can hit with a sterile glove.
const double nodexMinTouchTarget = 48;

/// The layout class a surface is rendered in.
enum AdaptiveSizeClass {
  /// A 6" phone.
  compact('compact'),

  /// An 8" tablet.
  medium('medium'),

  /// An 11–13" clinical tablet.
  expanded('expanded');

  const AdaptiveSizeClass(this.wireValue);

  /// Stable name of the class.
  final String wireValue;

  /// The class a width falls into.
  static AdaptiveSizeClass fromWidth(double width) {
    if (width < NodexBreakpoints.compact) return AdaptiveSizeClass.compact;
    if (width < NodexBreakpoints.expanded) return AdaptiveSizeClass.medium;
    return AdaptiveSizeClass.expanded;
  }

  /// Whether this is the phone layout.
  bool get isCompact => this == AdaptiveSizeClass.compact;

  /// Whether this is the clinical-tablet layout.
  bool get isExpanded => this == AdaptiveSizeClass.expanded;

  /// Whether the layout has room for a second column beside the first.
  bool get hasSideBySideColumns => this == AdaptiveSizeClass.expanded;
}
