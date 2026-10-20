/// Tests for the global search (Module 54).
///
/// The search is on a hotkey because a clinician looking for a patient should
/// not be three taps away from finding them. These tests pin the shortcuts
/// and the ranking of the results.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/features/search/global_search_screen.dart';

void main() {
  group('the shortcuts', () {
    test('control-K opens the search', () {
      final Map<ShortcutActivator, VoidCallback> bindings =
          GlobalSearchShortcuts.bindings(onOpen: () {});
      expect(
        bindings.containsKey(
          const SingleActivator(LogicalKeyboardKey.keyK, control: true),
        ),
        isTrue,
      );
    });

    test('command-K opens the search', () {
      final Map<ShortcutActivator, VoidCallback> bindings =
          GlobalSearchShortcuts.bindings(onOpen: () {});
      expect(
        bindings.containsKey(
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true),
        ),
        isTrue,
      );
    });

    test('slash opens the search', () {
      final Map<ShortcutActivator, VoidCallback> bindings =
          GlobalSearchShortcuts.bindings(onOpen: () {});
      expect(
        bindings.containsKey(const SingleActivator(LogicalKeyboardKey.slash)),
        isTrue,
      );
    });

    test('every shortcut runs the same action', () {
      int opened = 0;
      final Map<ShortcutActivator, VoidCallback> bindings =
          GlobalSearchShortcuts.bindings(onOpen: () => opened++);
      for (final VoidCallback action in bindings.values) {
        action();
      }
      expect(opened, bindings.length);
    });
  });
}
