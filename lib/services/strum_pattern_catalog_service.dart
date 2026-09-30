import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/strumming_pattern.dart';

/// Loads core strumming / arpeggio patterns for the learning path.
class StrumPatternCatalogService {
  static const assetPath = 'assets/strum_patterns.json';

  Future<List<StrummingPattern>> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['patterns'] as List<dynamic>? ?? const [])
        .map((e) => StrummingPattern.fromJson(e as Map<String, dynamic>))
        .toList();
    return list;
  }
}
