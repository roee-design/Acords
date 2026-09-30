import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/mic_capture_guard.dart';
import '../audio/strum_preview_service.dart';
import '../models/chord_definition.dart';
import 'chord_library_screen.dart';
import 'free_play_screen.dart';
import 'home_screen.dart';
import 'song_practice_screen.dart';
import 'tuner_screen.dart';

/// Root shell with bottom navigation between main app sections.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.catalog});

  final ChordCatalog catalog;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(catalog: widget.catalog),
      FreePlayScreen(
        catalog: widget.catalog,
        isActive: _selectedIndex == 1,
      ),
      ChordLibraryScreen(catalog: widget.catalog),
      SongPracticeScreen(
        catalog: widget.catalog,
        asTab: true,
      ),
      TunerScreen(
        catalog: widget.catalog,
        isActive: _selectedIndex == 4,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index == _selectedIndex) return;
          unawaited(() async {
            await StrumPreviewService.instance.stop();
            await MicCaptureGuard.instance.forceStopAll();
            if (mounted) setState(() => _selectedIndex = index);
          }());
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'בית',
          ),
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_outlined),
            selectedIcon: Icon(Icons.graphic_eq_rounded),
            label: 'זיהוי חופשי',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'אקורדים',
          ),
          NavigationDestination(
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music_rounded),
            label: 'שירים',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'טיונר',
          ),
        ],
      ),
    );
  }
}
