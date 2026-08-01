import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'models/chord_definition.dart';
import 'services/chord_catalog_service.dart';
import 'ui/app_theme.dart';
import 'ui/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ChordTrainerApp());
}

class ChordTrainerApp extends StatelessWidget {
  const ChordTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chord Trainer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      locale: const Locale('he', 'IL'),
      supportedLocales: const [
        Locale('he', 'IL'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _AppBootstrap(),
    );
  }
}

/// Loads [assets/chords.json] then shows [MainShell].
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  final ChordCatalogService _catalogService = ChordCatalogService();

  ChordCatalog? _catalog;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await _catalogService.load();
      if (mounted) {
        setState(() => _catalog = catalog);
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stackTrace),
      );
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'שגיאה בטעינת ספריית האקורדים',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _catalog = null;
                      });
                      _loadCatalog();
                    },
                    child: const Text('נסה שוב'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final catalog = _catalog;
    if (catalog == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'טוען אקורדים…',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MainShell(catalog: catalog);
  }
}
