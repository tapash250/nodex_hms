/// Tests for the medical icon repository (Module 51).
///
/// The repository is a contract: a screen asks for a symbol by its name and
/// gets the same symbol every time. These tests pin that the names are
/// unique, that every icon is reachable by name, and that the set is a
/// constant, because a constant is what makes it tree-shaken.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/icons/medical_icons.dart';

void main() {
  group('the repository', () {
    test('holds icons', () {
      expect(MedicalIcons.length, greaterThan(20));
    });

    test('every icon is reachable by its name', () {
      for (final MapEntry<String, IconData> entry
          in MedicalIcons.registry.entries) {
        expect(MedicalIcons.byName(entry.key), entry.value);
      }
    });

    test('the names are unique', () {
      final Set<String> names = MedicalIcons.registry.keys.toSet();
      expect(names.length, MedicalIcons.registry.length);
    });

    test('an unknown name finds nothing', () {
      expect(MedicalIcons.byName('no_such_icon'), isNull);
    });

    test('the names are snake case', () {
      for (final String name in MedicalIcons.registry.keys) {
        expect(name, matches(RegExp(r'^[a-z0-9_]+$')));
      }
    });

    test('the registry is a constant, which is what makes it tree-shaken', () {
      // A constant map of constant icons lets the icon tree-shaker see which
      // symbols the build actually reaches.
      const Map<String, IconData> registry = MedicalIcons.registry;
      expect(registry, isNotEmpty);
    });

    test('the icons are distinct enough to tell apart on a screen', () {
      final Set<int> codes = MedicalIcons.registry.values
          .map((IconData icon) => icon.codePoint)
          .toSet();
      // A handful of symbols legitimately share a glyph (a blood sample and a
      // blood product are the same mark), so this is a lower bound rather
      // than an equality.
      expect(codes.length, greaterThan(MedicalIcons.length - 4));
    });
  });
}
