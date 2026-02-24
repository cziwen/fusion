import 'dart:ui';
import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

enum AttractionStyle { none, solid, waves, streaks }

/// A mixin that provides functionality to draw attraction effects and impact pulses.
mixin MagneticEffectMixin on PositionComponent {
  final Paint _linePaint = Paint()
    ..color = Colors.white
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  final List<ImpactPulse> _pulses = [];
  double _totalTime = 0;

  /// Renders an attraction effect between [start] and [end] with [strength].
  void drawAttractionEffect(
    Canvas canvas,
    Vector2 start,
    Vector2 end,
    double strength, {
    AttractionStyle style = AttractionStyle.waves,
  }) {
    if (strength <= 0 || style == AttractionStyle.none) return;

    final opacity = strength.clamp(0.0, 1.0);
    _linePaint.color = Colors.white.withOpacity(opacity);
    _linePaint.strokeWidth = 1.0;

    switch (style) {
      case AttractionStyle.solid:
        canvas.drawLine(start.toOffset(), end.toOffset(), _linePaint);
        break;
      case AttractionStyle.waves:
        _drawGravityWaves(canvas, start, end, opacity);
        break;
      case AttractionStyle.streaks:
        _drawFieldStreaks(canvas, start, end, opacity);
        break;
      case AttractionStyle.none:
        break;
    }
  }

  void _drawGravityWaves(Canvas canvas, Vector2 start, Vector2 end, double opacity) {
    final diff = end - start;
    final dist = diff.length;
    if (dist < 5.0) return;

    final dir = diff.normalized();
    final perp = Vector2(-dir.y, dir.x);

    // Number of waves based on distance
    final waveCount = 3;
    final speed = 80.0;
    final spacing = dist / waveCount;

    for (int i = 0; i < waveCount; i++) {
      // Travel from Target (end/square) towards Source (start/cell)
      // Progress of each wave traveling
      double waveProgress = ((_totalTime * speed + i * spacing) % dist) / dist;
      
      // Wave position along the line
      final pos = end - (dir * (waveProgress * dist));
      
      // Fade out at ends of the path
      final waveOpacity = opacity * math.sin(waveProgress * math.pi);
      _linePaint.color = Colors.white.withOpacity(waveOpacity);
      _linePaint.strokeWidth = 1.5 * (1.0 - waveProgress * 0.4);

      // Wave width (length of the perpendicular line)
      final waveWidth = 12.0 * (1.0 + waveProgress * 1.5);
      
      // Draw a small arc/curve instead of a straight line for a more "field" feel
      final path = Path();
      final p1 = pos + perp * (waveWidth / 2);
      final p2 = pos - perp * (waveWidth / 2);
      final control = pos - dir * (waveWidth * 0.3); // Curve towards direction of travel

      path.moveTo(p1.x, p1.y);
      path.quadraticBezierTo(control.x, control.y, p2.x, p2.y);
      
      canvas.drawPath(path, _linePaint);
    }
  }

  void _drawFieldStreaks(Canvas canvas, Vector2 start, Vector2 end, double opacity) {
    final diff = start - end; // From Square (end) to Target (start)
    final dist = diff.length;
    if (dist < 5.0) return;

    final dirToTarget = diff.normalized();
    final targetPos = end; // Square local position

    final streakCount = 5;
    for (int i = 0; i < streakCount; i++) {
      // Use i to create pseudo-random stable properties for each streak
      final angle = (i * 137.5) * math.pi / 180; // Golden angle for distribution
      final sideOffsetDir = Vector2(math.cos(angle), math.sin(angle));
      
      // Animation cycle for each streak
      final speed = 1.5 + (i % 3) * 0.5;
      final cycleProgress = ((_totalTime * speed) + (i * 0.2)) % 1.0;
      
      final spawnDist = 15.0 + (i % 2) * 5.0;
      final currentDist = spawnDist * (1.0 - cycleProgress);
      
      final streakStart = targetPos + sideOffsetDir * 15.0 + dirToTarget * currentDist;
      final streakLen = 6.0 + cycleProgress * 8.0;
      final streakEnd = streakStart + dirToTarget * streakLen;

      final streakOpacity = opacity * math.sin(cycleProgress * math.pi);
      _linePaint.color = Colors.white.withOpacity(streakOpacity);
      _linePaint.strokeWidth = 0.8 + (1.0 - cycleProgress) * 0.8;

      canvas.drawLine(streakStart.toOffset(), streakEnd.toOffset(), _linePaint);
    }
  }

  /// Adds a new impact pulse at the specified [center].
  /// [isVertical] determines the orientation of the pulse line.
  void addImpactPulse(Vector2 center, bool isVertical, {double duration = 0.4}) {
    _pulses.add(ImpactPulse(center: center, isVertical: isVertical, duration: duration));
  }

  /// Updates all active pulses and internal animation time.
  void updatePulses(double dt) {
    _totalTime += dt;
    _pulses.removeWhere((pulse) {
      pulse.update(dt);
      return pulse.isFinished;
    });
  }

  /// Renders all active pulses.
  void renderPulses(Canvas canvas) {
    for (final pulse in _pulses) {
      final progress = pulse.progress;
      final opacity = 1.0 - progress;
      final length = 24.0 + (progress * 26.0); // Expand from 24 to 50
      final strokeWidth = 2.5 * (1.0 - progress * 0.75); // Fade from 2.5 to 0.6

      _linePaint.color = Colors.white.withOpacity(opacity);
      _linePaint.strokeWidth = strokeWidth;

      final halfLength = length / 2;
      if (pulse.isVertical) {
        canvas.drawLine(
          Offset(pulse.center.x, pulse.center.y - halfLength),
          Offset(pulse.center.x, pulse.center.y + halfLength),
          _linePaint,
        );
      } else {
        canvas.drawLine(
          Offset(pulse.center.x - halfLength, pulse.center.y),
          Offset(pulse.center.x + halfLength, pulse.center.y),
          _linePaint,
        );
      }
    }
  }
}

class AttractionTarget {
  final Vector2 source;
  final Vector2 target;
  final double strength;

  AttractionTarget({
    required this.source,
    required this.target,
    required this.strength,
  });
}

class ImpactPulse {
  final Vector2 center;
  final bool isVertical;
  final double duration;
  double _elapsed = 0;

  ImpactPulse({
    required this.center,
    required this.isVertical,
    this.duration = 0.4,
  });

  void update(double dt) {
    _elapsed += dt;
  }

  double get progress => (_elapsed / duration).clamp(0.0, 1.0);
  bool get isFinished => _elapsed >= duration;
}
