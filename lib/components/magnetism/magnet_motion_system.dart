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
    // Calculate distance to player core for range check and strength
    final distToPlayer = square.absolutePosition.distanceTo(playerWorldPosition);
    final maxDistance = attractionRadius;
    
    if (distToPlayer > maxDistance) {
      return const MagnetMotionResult(
        outOfRange: true,
        shouldAttach: false,
        strength: 0,
      );
    }

    // Direction vector towards the specific target slot
    tempDirection
      ..setFrom(targetWorld)
      ..sub(square.absolutePosition);
    final distanceToTargetSquared = tempDirection.length2;
    
    if (distanceToTargetSquared == 0) {
      return MagnetMotionResult(
        outOfRange: false,
        shouldAttach: attachRequestedThisFrame,
        strength: 1.0,
      );
    }

    // Strength is now based on distance to player core
    final strength = 1.0 - (distToPlayer / attractionRadius);

    // Use a velocity-based approach for smoother, more organic movement.
    // Instead of forcing position, we calculate a desired velocity and apply it.
    final velocity = Vector2.zero();
    final baseFactor = attractionForce / 100.0; // Scale user's force to a manageable factor

    if (distToPlayer <= controlRadius) {
      // Orbital Alignment: Guide the square towards the ray of its target slot
      final targetAngle = math.atan2(
        targetWorld.y - playerWorldPosition.y,
        targetWorld.x - playerWorldPosition.x,
      );
      final orbitalPoint = playerWorldPosition +
          Vector2(math.cos(targetAngle), math.sin(targetAngle)) * distToPlayer;
      
      final orbitalDiff = orbitalPoint - square.absolutePosition;
      // Orbital force is stronger to ensure it reaches the correct "lane"
      velocity.addScaled(orbitalDiff, baseFactor * 1.5 * strength);
    }

    // Radial Attraction: Pull the square towards the actual target center
    final radialDiff = targetWorld - square.absolutePosition;
    velocity.addScaled(radialDiff, baseFactor * 1.0 * strength);

    // Apply the combined movement
    square.position.addScaled(velocity, dt);

    // Smoothly align square rotation with player rotation
    final angleDiff = playerWorldAngle - square.angle;
    final normalizedDiff = (angleDiff + math.pi) % (2 * math.pi) - math.pi;
    square.angle += normalizedDiff * (strength * 5.0) * dt;

    return MagnetMotionResult(
      outOfRange: false,
      shouldAttach: attachRequestedThisFrame || distanceToTargetSquared <= snapDistance * snapDistance,
      strength: strength,
    );
  }
}
