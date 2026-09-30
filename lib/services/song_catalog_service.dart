import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/song_definition.dart';

/// Loads [assets/songs.json] from the Flutter asset bundle.
class SongCatalogService {
  static const assetPath = 'assets/songs.json';

  Future<SongCatalog> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return SongCatalog.fromJson(json);
  }
}
