import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

abstract final class AppLayout {
  static const maxPageWidth = 1120.0;
  static const maxFormWidth = 720.0;
  static const cardGap = 16.0;
  static const maxCardWidth = 400.0;

  static double gutter(double width) => width >= 1000
      ? 40
      : width >= 600
      ? 32
      : 20;

  static double cardHeight(BuildContext context, {bool compact = false}) {
    final textGrowth = math.max(
      0.0,
      MediaQuery.textScalerOf(context).scale(14) - 14,
    );
    return (compact ? 188 : 224) + textGrowth * 14;
  }
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.canvas,
    child: CustomPaint(painter: const _GridPainter(), child: child),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = const Color(0x06A3A3A3)
      ..strokeWidth = .5;
    final major = Paint()
      ..color = const Color(0x12A3A3A3)
      ..strokeWidth = .5;
    for (double x = 5; x < size.width; x += 10) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        (x - 5) % 100 == 0 ? major : minor,
      );
    }
    for (double y = 5; y < size.height; y += 10) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        (y - 5) % 100 == 0 ? major : minor,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

class AppPageScroll extends StatelessWidget {
  const AppPageScroll({
    super.key,
    required this.child,
    this.topPadding = 24,
    this.maxWidth = AppLayout.maxPageWidth,
  });

  final Widget child;
  final double topPadding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            AppLayout.gutter(constraints.maxWidth),
            topPadding,
            AppLayout.gutter(constraints.maxWidth),
            28,
          ),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
  );
}

class AppCardGrid extends StatelessWidget {
  const AppCardGrid({super.key, required this.children, this.columns})
    : assert(columns == null || columns > 0);

  final List<Widget> children;
  final int? columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columnCount =
          columns ??
          (constraints.maxWidth >= 960
              ? 3
              : constraints.maxWidth >= 600
              ? 2
              : 1);
      final width = math.min(
        AppLayout.maxCardWidth,
        (constraints.maxWidth - AppLayout.cardGap * (columnCount - 1)) /
            columnCount,
      );
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width * columnCount + AppLayout.cardGap * (columnCount - 1),
          child: Wrap(
            spacing: AppLayout.cardGap,
            runSpacing: AppLayout.cardGap,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          ),
        ),
      );
    },
  );
}
