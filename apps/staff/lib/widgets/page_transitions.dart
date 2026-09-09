import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Container-transform-style page for go_router: the incoming page fades and
/// scales up from 92% with the emphasized curve (task card → checklist,
/// scan → review). Instant when motion is reduced (UX-004).
CustomTransitionPage<T> containerTransformPage<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: SparklingMotion.medium,
    reverseTransitionDuration: SparklingMotion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (SparklingMotion.reducedMotion(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: SparklingMotion.emphasized,
        reverseCurve: SparklingMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Shared-axis (fade-through) page for sibling destinations.
CustomTransitionPage<T> fadeThroughPage<T>({
  required Widget child,
  required GoRouterState state,
}) {
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
