/// Tests for the adaptive component system (Module 46).
///
/// The system has two promises: the layout changes at the widths the
/// specification names, and a clinician in gloves can hit every control. Both
/// are checked here against the widths rather than against a picture.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/adaptive/adaptive_breaks.dart';
import 'package:nodex_hms/app/adaptive/adaptive_components.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Gives the test the surface it is pretending to be.
///
/// A phone is 400dp wide; a clinical tablet is 1280dp. The default test
/// surface is neither, so every widget test states the device it means.
Future<void> _device(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A 6" phone.
Future<void> _phone(WidgetTester tester) =>
    _device(tester, const Size(400, 800));

/// An 11-13" clinical tablet.
Future<void> _tablet(WidgetTester tester) =>
    _device(tester, const Size(1280, 800));

void main() {
  group('size classes', () {
    test('a 6" phone is compact', () {
      expect(AdaptiveSizeClass.fromWidth(400), AdaptiveSizeClass.compact);
      expect(AdaptiveSizeClass.fromWidth(599), AdaptiveSizeClass.compact);
    });

    test('an 8" tablet is medium', () {
      expect(AdaptiveSizeClass.fromWidth(600), AdaptiveSizeClass.medium);
      expect(AdaptiveSizeClass.fromWidth(999), AdaptiveSizeClass.medium);
    });

    test('an 11-13" clinical tablet is expanded', () {
      expect(AdaptiveSizeClass.fromWidth(1000), AdaptiveSizeClass.expanded);
      expect(AdaptiveSizeClass.fromWidth(1366), AdaptiveSizeClass.expanded);
    });

    test('only the clinical tablet has room for side-by-side columns', () {
      expect(AdaptiveSizeClass.compact.hasSideBySideColumns, isFalse);
      expect(AdaptiveSizeClass.medium.hasSideBySideColumns, isFalse);
      expect(AdaptiveSizeClass.expanded.hasSideBySideColumns, isTrue);
    });

    test('the class names are stable', () {
      expect(
        AdaptiveSizeClass.values.map((AdaptiveSizeClass c) => c.wireValue),
        <String>['compact', 'medium', 'expanded'],
      );
    });
  });

  group('touch targets', () {
    testWidgets('a small control is given a full 48dp target', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const MinTouchTarget(child: SizedBox(width: 16, height: 16))),
      );
      final Size size = tester.getSize(find.byType(MinTouchTarget));
      expect(size.width, greaterThanOrEqualTo(nodexMinTouchTarget));
      expect(size.height, greaterThanOrEqualTo(nodexMinTouchTarget));
    });

    testWidgets('a control that is already large is left alone', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const MinTouchTarget(child: SizedBox(width: 96, height: 96))),
      );
      expect(tester.getSize(find.byType(MinTouchTarget)).width, 96);
    });

    testWidgets('the control is expanded to fill the target', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const MinTouchTarget(child: SizedBox(width: 16, height: 16))),
      );
      final Size child = tester.getSize(find.byType(SizedBox).first);
      expect(child.width, greaterThanOrEqualTo(nodexMinTouchTarget));
      expect(child.height, greaterThanOrEqualTo(nodexMinTouchTarget));
    });

    test('the minimum is 48dp', () {
      expect(nodexMinTouchTarget, 48);
    });
  });

  group('the split view', () {
    testWidgets('a phone stacks the panes', (WidgetTester tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _host(
          const AdaptiveSplitView(
            primary: Text('Primary'),
            secondary: Text('Secondary'),
          ),
        ),
      );
      final Offset primary = tester.getTopLeft(find.text('Primary'));
      final Offset secondary = tester.getTopLeft(find.text('Secondary'));
      expect(secondary.dy, greaterThan(primary.dy));
      expect(secondary.dx, closeTo(primary.dx, 0.01));
    });

    testWidgets('a clinical tablet puts the panes side by side', (
      WidgetTester tester,
    ) async {
      await _tablet(tester);
      await tester.pumpWidget(
        _host(
          const AdaptiveSplitView(
            primary: Text('Primary'),
            secondary: Text('Secondary'),
          ),
        ),
      );
      final Offset primary = tester.getTopLeft(find.text('Primary'));
      final Offset secondary = tester.getTopLeft(find.text('Secondary'));
      expect(secondary.dx, greaterThan(primary.dx));
      expect(secondary.dy, closeTo(primary.dy, 0.01));
    });

    testWidgets('the secondary pane can come first when they stack', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AdaptiveSplitView(
            primary: Text('Primary'),
            secondary: Text('Secondary'),
            secondaryFirst: true,
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Secondary')).dy,
        lessThan(tester.getTopLeft(find.text('Primary')).dy),
      );
    });
  });

  group('the adaptive card', () {
    testWidgets('a wide card runs two columns', (WidgetTester tester) async {
      await _tablet(tester);
      await tester.pumpWidget(
        _host(
          const AdaptiveCard(primary: Text('Left'), secondary: Text('Right')),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Right')).dx,
        greaterThan(tester.getTopLeft(find.text('Left')).dx),
      );
    });

    testWidgets('a narrow card stacks its columns', (
      WidgetTester tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _host(
          const AdaptiveCard(primary: Text('Left'), secondary: Text('Right')),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Right')).dy,
        greaterThan(tester.getTopLeft(find.text('Left')).dy),
      );
    });

    testWidgets('a card with one column is one column', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const AdaptiveCard(primary: Text('Only'))));
      expect(find.text('Only'), findsOneWidget);
    });
  });

  group('the field grid', () {
    testWidgets('a phone runs one column', (WidgetTester tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _host(
          const AdaptiveFieldGrid(children: <Widget>[Text('One'), Text('Two')]),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Two')).dy,
        greaterThan(tester.getTopLeft(find.text('One')).dy),
      );
    });

    testWidgets('a clinical tablet runs two columns', (
      WidgetTester tester,
    ) async {
      await _tablet(tester);
      await tester.pumpWidget(
        _host(
          const AdaptiveFieldGrid(children: <Widget>[Text('One'), Text('Two')]),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Two')).dx,
        greaterThan(tester.getTopLeft(find.text('One')).dx),
      );
    });

    testWidgets('an odd field keeps its place in the first column', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AdaptiveFieldGrid(
            children: <Widget>[Text('One'), Text('Two'), Text('Three')],
          ),
        ),
      );
      expect(find.text('Three'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Three')).dx,
        closeTo(tester.getTopLeft(find.text('One')).dx, 0.01),
      );
    });
  });
}
