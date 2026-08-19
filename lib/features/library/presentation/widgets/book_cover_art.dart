import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/library_books.dart';

/// A generated book-jacket cover: gradient ground, a faint decorative
/// pattern keyed off [LibraryBookMeta.pattern], a large watermark icon,
/// a spine highlight, and the title/subtitle/author typeset like a
/// real cover. Used both as the library tile thumbnail (small) and the
/// reader screen's hero (large) -- same widget, different [width].
class BookCoverArt extends StatelessWidget {
  const BookCoverArt({
    super.key,
    required this.meta,
    this.width = 64,
    this.borderRadius = 10,
    this.showText = true,
  });

  final LibraryBookMeta meta;
  final double width;
  final double borderRadius;

  /// False renders just the art (no title text) -- used when the
  /// caller places its own title text beside/below the cover instead.
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final scale = width / 64;
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: meta.accentColor.withValues(alpha: 0.25),
              blurRadius: 12 * scale,
              offset: Offset(0, 4 * scale),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  meta.bgColor,
                  Color.lerp(meta.bgColor, meta.accentColor, 0.32)!,
                ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _CoverPatternPainter(
                    color: meta.accentColor,
                    pattern: meta.pattern,
                  ),
                ),
                Positioned(
                  right: -width * 0.22,
                  bottom: -width * 0.1,
                  child: Icon(meta.heroIcon,
                      size: width * 1.35,
                      color: meta.accentColor.withValues(alpha: 0.12)),
                ),
                // Spine highlight
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: math.max(2, 3 * scale),
                    color: meta.accentColor.withValues(alpha: 0.55),
                  ),
                ),
                // Top-edge sheen
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: width * 0.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white.withValues(alpha: 0.06), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      10 * scale, 10 * scale, 8 * scale, 9 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(meta.emoji, style: TextStyle(fontSize: 15 * scale)),
                      if (showText)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              meta.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5 * scale,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            SizedBox(height: 3 * scale),
                            Container(
                              width: 16 * scale,
                              height: 1.5,
                              color: meta.accentColor.withValues(alpha: 0.8),
                            ),
                            SizedBox(height: 3 * scale),
                            Text(
                              meta.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: meta.accentColor,
                                fontSize: 7.5 * scale,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverPatternPainter extends CustomPainter {
  _CoverPatternPainter({required this.color, required this.pattern});

  final Color color;
  final BookCoverPattern pattern;

  @override
  void paint(Canvas canvas, Size size) {
    switch (pattern) {
      case BookCoverPattern.circuit:
        _paintCircuit(canvas, size);
      case BookCoverPattern.matrix:
        _paintMatrix(canvas, size);
    }
  }

  void _paintCircuit(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = color.withValues(alpha: 0.22);

    final rng = math.Random(7);
    const rows = 7;
    final rowH = size.height / rows;
    for (var r = 0; r < rows; r++) {
      final y = rowH * r + rowH * 0.5;
      final startX = rng.nextDouble() * size.width * 0.5;
      final midX = startX + size.width * (0.2 + rng.nextDouble() * 0.25);
      final path = Path()
        ..moveTo(startX, y)
        ..lineTo(midX, y)
        ..lineTo(midX, y - rowH * 0.5)
        ..lineTo(midX + size.width * 0.18, y - rowH * 0.5);
      canvas.drawPath(path, paint);
      canvas.drawCircle(Offset(startX, y), 2.2, dot);
      canvas.drawCircle(Offset(midX + size.width * 0.18, y - rowH * 0.5), 2.2, dot);
    }
  }

  void _paintMatrix(Canvas canvas, Size size) {
    final rng = math.Random(11);
    const cols = 9;
    final colW = size.width / cols;
    for (var c = 0; c < cols; c++) {
      final x = colW * c + colW * 0.5;
      final glyphCount = 4 + rng.nextInt(4);
      final startY = rng.nextDouble() * size.height * 0.6;
      for (var g = 0; g < glyphCount; g++) {
        final y = startY + g * (size.height / (glyphCount + 2));
        final alpha = (0.22 - g * 0.03).clamp(0.03, 0.22);
        final paint = Paint()..color = color.withValues(alpha: alpha);
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, y), width: 2.6, height: 6),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CoverPatternPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pattern != pattern;
}
