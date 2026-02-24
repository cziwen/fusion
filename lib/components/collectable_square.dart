import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import 'player.dart';

enum MagnetState { idle, attracted, attaching, attached }

class CollectableSquare extends RectangleComponent with CollisionCallbacks {
  Color color = Colors.white;
  bool isAttached = false;
  MagnetState magnetState = MagnetState.idle;
  (int, int)? lockedTargetCell;
  int lockedTopologyVersion = -1;
  double lockElapsed = 0;
  bool attachRequestedThisFrame = false;
  Vector2? pendingLocalPosition;
  double? pendingLocalAngle;

  CollectableSquare({super.position, this.color = Colors.white})
      : super(
          size: Vector2.all(20),
          anchor: Anchor.center,
          paint: Paint()..color = color,
        ) {
    add(RectangleHitbox());
  }

  @override
  void onMount() {
    super.onMount();
    if (pendingLocalPosition != null) {
      position.setFrom(pendingLocalPosition!);
      pendingLocalPosition = null;
    }
    if (pendingLocalAngle != null) {
      angle = pendingLocalAngle!;
      pendingLocalAngle = null;
    }
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);

    // Collision only requests attachment; Player owns final validation.
    if (!isAttached && magnetState != MagnetState.attaching) {
      attachRequestedThisFrame = true;
      if (other is Player) {
        other.requestAttach(this);
      } else if (other is CollectableSquare && other.isAttached) {
        final player = other.ancestors().whereType<Player>().firstOrNull;
        player?.requestAttach(this);
      }
    }
  }

  void clearMagnetLock() {
    lockedTargetCell = null;
    lockedTopologyVersion = -1;
    lockElapsed = 0;
    if (!isAttached) {
      magnetState = MagnetState.idle;
    }
  }
}
