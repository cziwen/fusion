import 'dart:math' as math;

import 'package:flame/components.dart';

class MagnetMotionResult {
  final bool outOfRange;
  final bool shouldAttach;
  final double strength;

  const MagnetMotionResult({
    required this.outOfRange,
    required this.shouldAttach,
    required this.strength,
  });
}

class MagnetMotionSystem {
  const MagnetMotionSystem();

  MagnetMotionResult apply({
    required PositionComponent square,
    required bool attachRequestedThisFrame,
    required Vector2 targetWorld,
    required Vector2 playerWorldPosition,
    required double playerWorldAngle,
    required double attractionRadius,
    required double attractionForce,
    required double controlRadius,
    required double snapDistance,
    required double dt,
    required Vector2 tempDirection,
  }) {
    tempDirection
      ..setFrom(targetWorld)
      ..sub(square.absolutePosition);
    final distanceSquared = tempDirection.length2;
    final maxDistanceSquared = attractionRadius * attractionRadius;
    if (distanceSquared > maxDistanceSquared) {
      return const MagnetMotionResult(
        outOfRange: true,
        shouldAttach: false,
        strength: 0,
      );
    }
    if (distanceSquared == 0) {
      return MagnetMotionResult(
        outOfRange: false,
        shouldAttach: attachRequestedThisFrame,
        strength: 1.0,
      );
    }

    final distance = math.sqrt(distanceSquared);
    final strength = 1.0 - (distance / attractionRadius);

    if (distance <= controlRadius) {
      final currentAngle = math.atan2(
        square.absolutePosition.y - playerWorldPosition.y,
        square.absolutePosition.x - playerWorldPosition.x,
      );
      final relAngle = currentAngle - playerWorldAngle;
      final targetRelAngle = (relAngle / (math.pi / 2)).round() * (math.pi / 2);
      final targetAngle = playerWorldAngle + targetRelAngle;
      final newPos = playerWorldPosition +
          Vector2(math.cos(targetAngle), math.sin(targetAngle)) * distance;
      square.position.lerp(newPos, 10.0 * dt);
    }

    tempDirection.scale(1.0 / distance);
    square.position.addScaled(tempDirection, strength * attractionForce * dt);

    final relAngle = square.angle - playerWorldAngle;
    final targetRelAngle = (relAngle / (math.pi / 2)).round() * (math.pi / 2);
    final targetWorldAngle = playerWorldAngle + targetRelAngle;
    final angleDiff = targetWorldAngle - square.angle;
    final normalizedDiff = (angleDiff + math.pi) % (2 * math.pi) - math.pi;
    square.angle += normalizedDiff * (strength * 5.0) * dt;

    return MagnetMotionResult(
      outOfRange: false,
      shouldAttach: attachRequestedThisFrame || distanceSquared <= snapDistance * snapDistance,
      strength: strength,
    );
  }
}
