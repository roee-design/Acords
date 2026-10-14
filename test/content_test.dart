import 'dart:convert';
import 'dart:io';

import 'package:chord_trainer/models/chord_definition.dart';
import 'package:chord_trainer/models/song_definition.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog_loader.dart';

void main() {
  final catalog = loadChordCatalog();
  final songs = SongCatalog.fromJson(
    jsonDecode(File('assets/songs.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final patterns = [
    for (final p in (jsonDecode(
      File('assets/strum_patterns.json').readAsStringSync(),
    ) as Map<String, dynamic>)['patterns'] as List<dynamic>)
      StrummingPattern.fromJson(p as Map<String, dynamic>),
  ];

  test('chord ids are unique', () {
    final ids = catalog.chords.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('every chord note matches its string, fret and fingering', () {
    const openMidi = {6: 40, 5: 45, 4: 50, 3: 55, 2: 59, 1: 64};
    for (final chord in catalog.chords) {
      expect(chord.fingering.length, 6, reason: chord.id);
      expect(chord.difficulty, inInclusiveRange(1, 5), reason: chord.id);
      for (var s = 6; s >= 1; s--) {
        final symbol = chord.fingering[6 - s];
        final note = chord.noteForString(s);
        if (symbol.toLowerCase() == 'x') {
          expect(note, isNull, reason: '${chord.id} string $s is muted');
          continue;
        }
        expect(note, isNotNull, reason: '${chord.id} string $s');
        expect(note!.fret, int.parse(symbol), reason: '${chord.id} s$s');
        expect(note.midi, openMidi[s]! + note.fret, reason: '${chord.id} s$s');
        if (note.fret > 0) {
          expect(note.finger, inInclusiveRange(1, 4), reason: '${chord.id} s$s');
        }
      }
    }
  });

  test('songs reference existing chords and parse', () {
    expect(songs.songs, isNotEmpty);
    final ids = songs.songs.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate song id');
    for (final song in songs.songs) {
      expect(song.chordSequence, isNotEmpty, reason: song.id);
      expect(song.pattern.events, isNotEmpty, reason: song.id);
      for (final id in song.chordSequence) {
        expect(catalog.chordById(id), isNotNull, reason: '${song.id}: $id');
      }
    }
  });

  test('strumming patterns parse and reference existing chords', () {
    final ids = patterns.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate pattern id');
    for (final p in patterns) {
      // A pattern may be a whole bar or a repeating part of one (whole beats).
      expect(p.events.length % p.subdivision, 0, reason: p.id);
      for (final id in p.practiceChordIds) {
        expect(catalog.chordById(id), isNotNull, reason: '${p.id}: $id');
      }
      final example = p.exampleSongId;
      expect(example, isNotNull, reason: '${p.id} has no example song');
      expect(songs.byId(example!), isNotNull, reason: '${p.id}: $example');
    }
  });

  test('songs have a language and a known genre', () {
    for (final song in songs.songs) {
      expect(['he', 'en'], contains(song.language), reason: song.id);
      expect(SongGenres.labels.keys, contains(song.genre), reason: song.id);
      expect(song.isHebrew, song.rtl, reason: '${song.id}: language vs rtl');
    }
  });

  test('same-sound voicings are recognised as such', () {
    ChordDefinition c(String id) => catalog.chordById(id)!;
    expect(c('a_major').soundsLike(c('a_major_barre')), isTrue);
    expect(c('a_sus4').soundsLike(c('d_sus2')), isFalse,
        reason: 'same notes, different bass');
  });
}
