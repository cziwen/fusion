import 'dart:math' as math;

import 'package:flame/components.dart';

import '../collectable_square.dart';
import 'connectivity_engine.dart';
import 'grid_state.dart';
import 'match_engine.dart';

class _PendingAttachment {
  final CollectableSquare square;
  final (int, int) targetCell;
  final Vector2 Function((int, int) cell) cellToLocal;
  final Vector2 Function(Vector2 localPos) absolutePositionOfLocal;
  final double playerAngle;
  final void Function(CollectableSquare square) moveUnderPlayer;
  final void Function((int, int) targetCell, (int, int) neighborCell) onNeighborConnection;
  final void Function(CollectableSquare square) onAttached;
  final void Function() onCameraShake;

  _PendingAttachment({
    required this.square,
    required this.targetCell,
    required this.cellToLocal,
    required this.absolutePositionOfLocal,
    required this.playerAngle,
    required this.moveUnderPlayer,
    required this.onNeighborConnection,
    required this.onAttached,
    required this.onCameraShake,
  });
}

class AttachPipeline {
  final GridState gridState;
  final MatchEngine matchEngine;
  final ConnectivityEngine connectivityEngine;

  final List<_PendingAttachment> _pending = [];

  AttachPipeline({
    required this.gridState,
    required this.matchEngine,
    required this.connectivityEngine,
  });

  /// Stages a square for attachment. Returns true if it was successfully added to the grid.
  /// The actual visual attachment and rule checks happen during [flush].
  bool stageAttach(
    CollectableSquare square, {
    required (int, int)? Function() resolveTargetCell,
    required Vector2 Function((int, int) cell) cellToLocal,
    required Vector2 Function(Vector2 localPos) absolutePositionOfLocal,
    required double playerAngle,
    required void Function(CollectableSquare square) moveUnderPlayer,
    required void Function((int, int) targetCell, (int, int) neighborCell) onNeighborConnection,
    required void Function(CollectableSquare square) onAttached,
    required void Function() onCameraShake,
  }) {
    if (square.isAttached || square.magnetState == MagnetState.attaching) return false;

    final targetCell = resolveTargetCell();
    if (targetCell == null || !gridState.isAttachCellValid(targetCell, requester: square)) {
      square.magnetState = MagnetState.idle;
      square.attachRequestedThisFrame = false;
      return false;
    }

    square.magnetState = MagnetState.attaching;
    gridState.addAttached(targetCell, square);
    square.isAttached = true;

    _pending.add(_PendingAttachment(
      square: square,
      targetCell: targetCell,
      cellToLocal: cellToLocal,
      absolutePositionOfLocal: absolutePositionOfLocal,
      playerAngle: playerAngle,
      moveUnderPlayer: moveUnderPlayer,
      onNeighborConnection: onNeighborConnection,
      onAttached: onAttached,
      onCameraShake: onCameraShake,
    ));

    return true;
  }

  /// Processes all staged attachments and existing grid state for matches and orphans.
  void flush({
    required void Function(CollectableSquare square) onDetachedToWorld,
  }) {
    if (_pending.isEmpty && gridState.occupiedCells.length <= 1) {
      // Nothing to check if only core is present and no new attachments
      return;
    }

    // 1. Build a single snapshot of the current state after all attachments
    final snapshot = gridState.occupiedCells.toSet();
    
    // 2. Find matches
    final matches = matchEngine.findMatches(snapshot);
    if (matches.isNotEmpty) {
      for (final cell in matches) {
        final removed = gridState.removeAttached(cell);
        if (removed != null) {
          removed.isAttached = false;
          removed.removeFromParent();
          // Note: clearMagnetLock and releaseReservation are handled by the square's own lifecycle or below
        }
        snapshot.remove(cell);
      }
      gridState.bumpTopology();
    }

    // 3. Find orphans based on the state AFTER matches were removed
    final orphans = connectivityEngine.findOrphans(snapshot);
    if (orphans.isNotEmpty) {
      for (final cell in orphans) {
        final orphan = gridState.removeAttached(cell);
        if (orphan == null) continue;

        final worldPos = orphan.absolutePosition;
        final worldAngle = orphan.absoluteAngle;

        orphan.isAttached = false;
        orphan.magnetState = MagnetState.idle;
        gridState.releaseReservation(orphan);
        orphan.clearMagnetLock();
        
        if (orphan.parent != null) {
          orphan.removeFromParent();
        }
        orphan.position = worldPos;
        orphan.angle = worldAngle;
        onDetachedToWorld(orphan);
      }
      gridState.bumpTopology();
    }

    // 4. Finalize survivors
    for (final pending in _pending) {
      final square = pending.square;
      
      // If the square was removed during match or orphan phase
      if (!gridState.containsSquare(square)) {
        gridState.releaseReservation(square);
        square.clearMagnetLock();
        square.attachRequestedThisFrame = false;
        continue;
      }

      // Finalize visual attachment
      final finalLocalPos = pending.cellToLocal(pending.targetCell);
      final targetWorldPos = pending.absolutePositionOfLocal(finalLocalPos);
      gridState.releaseReservation(square);
      square.attachRequestedThisFrame = false;
      square.magnetState = MagnetState.attached;

      square.position = targetWorldPos;
      square.pendingLocalPosition = finalLocalPos;
      final localAngle = square.angle - pending.playerAngle;
      final snappedLocalAngle = (localAngle / (math.pi / 2)).round() * (math.pi / 2);
      square.pendingLocalAngle = snappedLocalAngle;

      pending.moveUnderPlayer(square);

      for (final neighbor in gridState.neighbors(pending.targetCell)) {
        if (gridState.isOccupied(neighbor)) {
          pending.onNeighborConnection(pending.targetCell, neighbor);
        }
      }

      square.clearMagnetLock();
      pending.onAttached(square);
      pending.onCameraShake();
    }

    _pending.clear();
    gridState.validateAndRepair();
    gridState.bumpTopology();
  }
}
