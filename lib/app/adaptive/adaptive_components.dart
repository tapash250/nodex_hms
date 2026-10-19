/// Adaptive components (Module 46).
///
/// The components that change shape with the device: a split view that becomes
/// a master/detail workspace on a clinical tablet, a card that gains a second
/// column, a field grid that runs in two columns when there is room, and a
/// sheet that arrives from the side on a tablet and from the bottom on a
/// phone. Every decision is made from the width the component is actually
/// given, not from the width of the screen, so a component embedded in a
/// split view behaves like the space it was given.
library;

import 'package:flutter/material.dart';
import 'package:nodex_hms/app/adaptive/adaptive_breaks.dart';

/// Guarantees a control occupies at least [minimum] on both axes.
///
/// The control is expanded to the minimum rather than padded around, so it
/// fills the hit area: a guard that only enlarged the space around a button
/// would let the reader miss the button and hit the gap beside it. Wrap the
/// control itself — an icon button, a checkbox, a switch, a text button.
class MinTouchTarget extends StatelessWidget {
  /// Creates a touch-target guard.
  const MinTouchTarget({
    required this.child,
    this.minimum = nodexMinTouchTarget,
    super.key,
  });

  /// The control being guarded.
  final Widget child;

  /// The smallest hit area, in logical pixels.
  final double minimum;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minWidth: minimum, minHeight: minimum),
    child: child,
  );
}

/// Two panes that share the width, side by side when there is room.
///
/// On a wide surface the second pane sits beside the first, which is the
/// master/detail workspace a clinical tablet is for. On a narrow one the panes
/// stack, because a 400dp pane beside another 400dp pane is two unreadable
/// columns.
class AdaptiveSplitView extends StatelessWidget {
  /// Creates a split view.
  const AdaptiveSplitView({
    required this.primary,
    required this.secondary,
    this.secondaryWidth = 360,
    this.secondaryFirst = false,
    this.stackSpacing = 16,
    super.key,
  });

  /// The main pane.
  final Widget primary;

  /// The pane that moves beside the main one when there is room.
  final Widget secondary;

  /// How wide the secondary pane is when it moves beside the primary one.
  final double secondaryWidth;

  /// Whether the secondary pane comes first when the panes stack.
  final bool secondaryFirst;

  /// The gap between the panes when they stack.
  final double stackSpacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool sideBySide = constraints.maxWidth >= NodexBreakpoints.expanded;
      if (!sideBySide) {
        // Stacked, the secondary pane takes the height it needs and the
        // primary pane takes the rest, so a list inside it still scrolls.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: secondaryFirst
              ? <Widget>[
                  secondary,
                  SizedBox(height: stackSpacing),
                  Expanded(child: primary),
                ]
              : <Widget>[
                  Expanded(child: primary),
                  SizedBox(height: stackSpacing),
                  secondary,
                ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: primary),
          const VerticalDivider(width: 1),
          SizedBox(width: secondaryWidth, child: secondary),
        ],
      );
    },
  );
}

/// A card that gains a second column when there is room.
class AdaptiveCard extends StatelessWidget {
  /// Creates an adaptive card.
  const AdaptiveCard({required this.primary, this.secondary, super.key});

  /// The main content.
  final Widget primary;

  /// The content that moves into a second column on a wide surface.
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final Widget? side = secondary;
      if (side == null || constraints.maxWidth < NodexBreakpoints.expanded) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: side == null
                ? primary
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      primary,
                      const SizedBox(height: 12),
                      side,
                    ],
                  ),
          ),
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: primary),
              const SizedBox(width: 16),
              Expanded(child: side),
            ],
          ),
        ),
      );
    },
  );
}

/// A set of form fields that runs in two columns when there is room.
///
/// A single-column form is the rule on a phone: it is the only layout a
/// thumb can complete without a stylus. On a clinical tablet, the same form
/// runs in two columns so a long admission note fits on one screen.
class AdaptiveFieldGrid extends StatelessWidget {
  /// Creates a field grid.
  const AdaptiveFieldGrid({
    required this.children,
    this.spacing = 12,
    super.key,
  });

  /// The fields.
  final List<Widget> children;

  /// The gap between the fields.
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool twoColumns = constraints.maxWidth >= NodexBreakpoints.expanded;
      if (!twoColumns) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) SizedBox(height: spacing),
              children[i],
            ],
          ],
        );
      }
      final List<Widget> fields = <Widget>[];
      for (int i = 0; i < children.length; i += 2) {
        final Widget left = children[i];
        final Widget? right = i + 1 < children.length ? children[i + 1] : null;
        fields.add(
          Padding(
            padding: EdgeInsets.only(
              bottom: i + 2 < children.length ? spacing : 0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: left),
                if (right != null) ...<Widget>[
                  SizedBox(width: spacing),
                  Expanded(child: right),
                ],
              ],
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: fields,
      );
    },
  );
}

/// Shows a sheet that arrives from the side on a tablet and from the bottom on
/// a phone.
///
/// The content is the same in both cases; only the arrival changes, because
/// the difference is ergonomic: on a phone a side sheet is unreachable, and on
/// a clinical tablet a bottom sheet covers the record the clinician is
/// reading.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool scrollable = true,
}) {
  final double width = MediaQuery.sizeOf(context).width;
  if (width < NodexBreakpoints.expanded) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: scrollable,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black38,
    builder: (BuildContext context) => Dialog(
      alignment: Alignment.centerRight,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Material(
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(16),
          child: SingleChildScrollView(child: builder(context)),
        ),
      ),
    ),
  );
}
