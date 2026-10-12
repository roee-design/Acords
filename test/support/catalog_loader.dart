import 'dart:convert';
import 'dart:io';

import 'package:chord_trainer/models/chord_definition.dart';

ChordCatalog loadChordCatalog() {
  final json = jsonDecode(File('assets/chords.json').readAsStringSync());
  return ChordCatalog.fromJson(json as Map<String, dynamic>);
}
