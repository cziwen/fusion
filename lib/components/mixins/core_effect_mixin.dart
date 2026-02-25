import 'dart:math' as math;
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart' hide Image;

/// A mixin that provides visual effects for the core block.
mixin CoreEffectMixin on PositionComponent {
  double _coreEffectTimer = 0;
  final List<_CoreParticle> _coreParticles = [];
  final math.Random _coreRandom = math.Random();

  /// Returns a breathing factor between 0.0 and 1.0.
  double get coreBreathingValue => (math.sin(_coreEffectTimer * 3.0) + 1) / 2;

  /// Updates the core effects.
  void updateCoreEffects(double dt) {
    _coreEffectTimer += dt;
    _coreParticles.removeWhere((p) {
      p.update(dt);
      return p.isDead;
    });

    // Occasionally spawn particles
    if (_coreRandom.nextDouble() < 0.15) {
      _spawnCoreParticle();
    }
  }

  void _spawnCoreParticle() {
    // Spawn at the edge of the core
    final angle = _coreRandom.nextDouble() * math.pi * 2;
    final dist = 10.0; 
    final pos = Vector2(math.cos(angle) * dist, math.sin(angle) * dist);
    final speed = 5.0 + _coreRandom.nextDouble() * 15.0;
    
    _coreParticles.add(_CoreParticle(
      position: pos,
      velocity: Vector2(math.cos(angle), math.sin(angle)) * speed,
      lifeSpan: 0.8 + _coreRandom.nextDouble() * 0.6,
    ));
  }

  /// Renders the core effects that appear behind the core.
  void renderCoreBackgroundEffects(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    
    // 1. Core Glow (Radial Background Glow)
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, size.x * 0.8, glowPaint);

    // 2. Pulsing Aura Rings
    // These are rounded rectangles that "breathe"
    for (int i = 0; i < 2; i++) {
      final auraProgress = (_coreEffectTimer * 0.4 + i * 0.5) % 1.0;
      final auraScale = 1.0 + auraProgress * 0.6;
      final auraOpacity = (1.0 - auraProgress) * 0.4;
      final auraSize = size.x * auraScale;
      
      final auraPaint = Paint()
        ..color = Colors.white.withValues(alpha: auraOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: auraSize, height: auraSize),
          Radius.circular(auraSize * 0.2),
        ),
        auraPaint,
      );
    }
  }

  /// Renders the core effects that appear in front of the core.
  void renderCoreForegroundEffects(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);

    // 3. Energy Particles
    for (final p in _coreParticles) {
      final pPaint = Paint()
        ..color = Colors.white.withValues(alpha: p.opacity * 0.7)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center + p.position.toOffset(), 1.0, pPaint);
    }

    // 4. Scanning "Pulse" Line
    // A vertical/horizontal line that sweeps across the core
    final scanProgress = (_coreEffectTimer * 0.8) % 2.0;
    if (scanProgress < 1.0) {
      final scanPaint = Paint()
        ..color = Colors.white.withValues(alpha: (1.0 - scanProgress).clamp(0, 0.5))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      
      final y = (scanProgress - 0.5) * size.y;
      canvas.drawLine(
        center + Offset(-size.x / 2, y),
        center + Offset(size.x / 2, y),
        scanPaint,
      );
    }
  }
}

class _CoreParticle {
  Vector2 position;
  Vector2 velocity;
  double lifeSpan;
  double _elapsed = 0;

  _CoreParticle({
    required this.position,
    required this.velocity,
    required this.lifeSpan,
  });

  void update(double dt) {
    _elapsed += dt;
    position += velocity * dt;
    // Slight deceleration
    velocity *= 0.97;
  }

  double get opacity => (1.0 - _elapsed / lifeSpan).clamp(0.0, 1.0);
  bool get isDead => _elapsed >= lifeSpan;
}
