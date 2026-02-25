import 'package:flame/components.dart';

import '../collectable_square.dart';
import 'grid_state.dart';

class MagnetTargetingService {
  (int, int)? findNearestAttachCell(
    GridState gridState,
    Vector2 worldPos,
    Vector2 Function(Vector2 worldPos) toLocal,
    Vector2 Function((int, int) cell) cellToLocal, {
    CollectableSquare? requester,
  }) {
    final localPos = toLocal(worldPos);
    final candidates = gridState.collectAttachCandidates(requester: requester);
    if (candidates.isEmpty) return null;

    (int, int)? bestCell;
    var bestDistanceSquared = double.infinity;
    for (final cell in candidates) {
      final cellLocal = cellToLocal(cell);
      final distanceSquared = localPos.distanceToSquared(cellLocal);
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        bestCell = cell;
      }
    }
    return bestCell;
  }

  (int, int)? resolveOrLockTargetCell(
    GridState gridState,
    CollectableSquare square, {
    required bool forceRelock,
    required Vector2 worldPos,
    required double lockTimeoutSeconds,
    required Vector2 Function(Vector2 worldPos) toLocal,
    required Vector2 Function((int, int) cell) cellToLocal,
  }) {
    final currentLock = square.lockedTargetCell;
    final canReuseCurrent = !forceRelock &&
        currentLock != null &&
        square.lockedTopologyVersion == gridState.topologyVersion &&
        square.lockElapsed <= lockTimeoutSeconds &&
        gridState.isAttachCellValid(currentLock, requester: square) &&
        gridState.reserveCell(currentLock, square);
    if (canReuseCurrent) {
      return currentLock;
    }

    gridState.releaseReservation(square);
    final candidate = findNearestAttachCell(
      gridState,
      worldPos,
      toLocal,
      cellToLocal,
      requester: square,
    );
    if (candidate == null) {
      square.clearMagnetLock();
      return null;
    }
    if (!gridState.reserveCell(candidate, square)) {
      square.clearMagnetLock();
      return null;
    }

    square.lockedTargetCell = candidate;
    square.lockedTopologyVersion = gridState.topologyVersion;
    square.lockElapsed = 0;
    square.magnetState = MagnetState.attracted;
    return candidate;
  }
}
