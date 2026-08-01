import 'package:flutter/material.dart';

/// Fade + slight slide transition for pushed screens.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required Widget page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved);

            return FadeTransition(
              opacity: curved,
              child: SlideTransition(position: slide, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 260),
        );
}
