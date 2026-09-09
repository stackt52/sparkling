import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// M3 shared-axis (X) page — used between booking steps and pushed detail
/// screens. Collapses to an instant switch when motion is reduced (UX-004).
CustomTransitionPage<T> sharedAxisPage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: SparklingMotion.medium,
    reverseTransitionDuration: SparklingMotion.medium,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (SparklingMotion.reducedMotion(context)) return child;
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.horizontal,
        fillColor: Theme.of(context).colorScheme.surface,
        child: child,
      );
    },
  );
}

/// Fade-through page — used for top-level tab pages and full-screen
/// takeovers (scanner, confirmation).
CustomTransitionPage<T> fadeThroughPage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: SparklingMotion.medium,
    reverseTransitionDuration: SparklingMotion.medium,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (SparklingMotion.reducedMotion(context)) return child;
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        fillColor: Theme.of(context).colorScheme.surface,
        child: child,
      );
    },
  );
}

/// Simple fade — used for the auth screens and shell tabs.
CustomTransitionPage<T> fadePage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: SparklingMotion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (SparklingMotion.reducedMotion(context)) return child;
      return FadeTransition(opacity: animation, child: child);
    },
  );
}
