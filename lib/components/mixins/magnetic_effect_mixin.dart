import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// A mixin that provides functionality to draw attraction lines and impact pulses.
mixin MagneticEffectMixin on PositionComponent {
  final Paint _linePaint = Paint()
    ..color = Colors.white
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  final List<ImpactPulse> _pulses = [];

  /// Renders an attraction line between [start] and [end] with [strength].
  void drawAttractionLine(Canvas canvas, Vector2 start, Vector2 end, double strength) {
    if (strength <= 0) return;

    _linePaint.color = Colors.white.withOpacity(strength.clamp(0.0, 1.0));
    _linePaint.strokeWidth = 1.0;
    canvas.drawLine(
      start.toOffset(),
      end.toOffset(),
      _linePaint,
    );
  }

  /// Adds a new impact pulse at the specified [center].
  /// [isVertical] determines the orientation of the pulse line.
  void addImpactPulse(Vector2 center, bool isVertical, {double duration = 0.4}) {
    _pulses.add(ImpactPulse(center: center, isVertical: isVertical, duration: duration));
  }

  /// Updates all active pulses.
  void updatePulses(double dt) {
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
      final length = 20.0 + (progress * 20.0); // Expand from 20 to 40
      final strokeWidth = 2.0 * (1.0 - progress * 0.75); // Fade from 2.0 to 0.5

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
