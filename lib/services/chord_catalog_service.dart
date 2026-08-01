import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/chord_definition.dart';

/// Loads [assets/chords.json] from the Flutter asset bundle.
class ChordCatalogService {
  static const assetPath = 'assets/chords.json';

  Future<ChordCatalog> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return ChordCatalog.fromJson(json);
  }
}
