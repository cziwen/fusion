import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../game.dart';
import 'collectable_square.dart';
import 'mixins/magnetic_effect_mixin.dart';

class Player extends RectangleComponent
    with HasGameReference<FusionGame>, KeyboardHandler, CollisionCallbacks, MagneticEffectMixin {
  static const double speed = 200.0;
  static const double rotationSpeed = 3.0;
  static const double cellSize = 20.0;
  double attractionRadius = 150.0;
  double attractionForce = 500.0;
  double candidateRefreshInterval = 0.2;
  int magnetBatchSize = 24;
  bool enableVisibleCandidateFilter = true;
  double visibleCandidateMargin = 100.0;
  static const double lockTimeoutSeconds = 1.2;
  static const double snapDistance = 6.0;

  Vector2 velocity = Vector2.zero();
  final Set<LogicalKeyboardKey> _keysPressed = {};
  final Set<(int, int)> _occupiedCells = {(0, 0)};
  final Map<(int, int), CollectableSquare> _reservedCells = {};
  final List<CollectableSquare> _magnetCandidates = [];
  final Map<(int, int), Vector2> _cellLocalPositionCache = {};
  
  // Reusable vectors for optimization to reduce GC pressure on Web.
  final Vector2 _tempVec1 = Vector2.zero();
  
  int _magnetBatchCursor = 0;
  double _candidateRefreshElapsed = 0;
  int _topologyVersion = 0;

  bool showAttractionLines = true;
  bool showImpactPulses = true;
  double pulseDuration = 0.4;
  AttractionStyle attractionStyle = AttractionStyle.streaks;

  final List<AttractionTarget> _activeAttractionTargets = [];

  Player()
      : super(
          size: Vector2.all(20),
          paint: Paint()..color = Colors.white,
        ) {
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);

    _activeAttractionTargets.clear();
    updatePulses(dt);

    // Movement logic.
    velocity.x = 0;
    velocity.y = 0;

    if (_keysPressed.contains(LogicalKeyboardKey.keyW) || _keysPressed.contains(LogicalKeyboardKey.arrowUp)) velocity.y -= 1;
    if (_keysPressed.contains(LogicalKeyboardKey.keyS) || _keysPressed.contains(LogicalKeyboardKey.arrowDown)) velocity.y += 1;
    if (_keysPressed.contains(LogicalKeyboardKey.keyA) || _keysPressed.contains(LogicalKeyboardKey.arrowLeft)) velocity.x -= 1;
    if (_keysPressed.contains(LogicalKeyboardKey.keyD) || _keysPressed.contains(LogicalKeyboardKey.arrowRight)) velocity.x += 1;

    if (!velocity.isZero()) {
      velocity.normalize();
      position += velocity * speed * dt;
    }

    // Rotation logic.
    double rotationDir = 0;
    if (_keysPressed.contains(LogicalKeyboardKey.keyQ) || _keysPressed.contains(LogicalKeyboardKey.comma)) {
      rotationDir -= 1;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.keyE) || _keysPressed.contains(LogicalKeyboardKey.period)) {
      rotationDir += 1;
    }
    if (rotationDir != 0) {
      angle += rotationDir * rotationSpeed * dt;
    }

    _refreshMagnetCandidates(dt);
    _updateMagnetismBatch(dt);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (showAttractionLines) {
      for (final target in _activeAttractionTargets) {
        drawAttractionEffect(
          canvas,
          target.source,
          target.target,
          target.strength,
          style: attractionStyle,
        );
      }
    }
    if (showImpactPulses) {
      renderPulses(canvas);
    }
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is CollectableSquare && !other.isAttached) {
      requestAttach(other);
    }
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (event is KeyDownEvent) {
      _keysPressed.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _keysPressed.remove(event.logicalKey);
    }
    return true;
  }

  void requestAttach(CollectableSquare square) {
    if (square.isAttached || square.magnetState == MagnetState.attaching) return;
    attachSquare(square);
  }

  void attachSquare(CollectableSquare square) {
    if (square.isAttached || square.magnetState == MagnetState.attaching) return;
    square.magnetState = MagnetState.attaching;

    final targetCell = _resolveOrLockTargetCell(
      square,
      forceRelock: true,
      worldPos: square.absolutePosition,
    );
    if (targetCell == null || !_isAttachCellValid(targetCell, requester: square)) {
      square.magnetState = MagnetState.idle;
      square.attachRequestedThisFrame = false;
      return;
    }
    final finalLocalPos = _cellToLocal(targetCell);
    // Calculate the target world position to maintain visual continuity during the transition frame.
    // Use absolutePositionOf to account for Player's current rotation and anchor.
    final targetWorldPos = absolutePositionOf(finalLocalPos);

    _releaseReservation(square);
    square.isAttached = true;
    square.magnetState = MagnetState.attached;
    square.attachRequestedThisFrame = false;

    // Temporarily set the world position so it doesn't jump during the remainder of this frame
    // while it is still technically a child of the World or in transition.
    square.position = targetWorldPos;
    // Queue the local position and angle for when it mounts to the Player.
    square.pendingLocalPosition = finalLocalPos;
    square.pendingLocalAngle = 0;

    square.removeFromParent();
    add(square);

    _occupiedCells.add(targetCell);

    // Trigger impact pulse for each shared edge with an occupied cell.
    for (final neighbor in _neighbors(targetCell)) {
      if (_occupiedCells.contains(neighbor)) {
        final isVerticalConnection = neighbor.$1 == targetCell.$1;
        Vector2 pulseCenter;
        if (isVerticalConnection) {
          // Top or Bottom
          final y = math.max(neighbor.$2, targetCell.$2);
          pulseCenter = Vector2((targetCell.$1 + 0.5) * cellSize, y * cellSize);
        } else {
          // Left or Right
          final x = math.max(neighbor.$1, targetCell.$1);
          pulseCenter = Vector2(x * cellSize, (targetCell.$2 + 0.5) * cellSize);
        }
        addImpactPulse(pulseCenter, !isVerticalConnection, duration: pulseDuration);
      }
    }

    square.clearMagnetLock();
    _topologyVersion += 1;

    // Notify game to stop tracking this square in chunks
    game.onSquareAttached(square);
  }

  (int, int)? _findNearestAttachCell(Vector2 worldPos, {CollectableSquare? requester}) {
    final localPos = toLocal(worldPos);
    final candidates = _collectAttachCandidates(requester: requester);
    if (candidates.isEmpty) return null;

    (int, int)? bestCell;
    var bestDistanceSquared = double.infinity;
    for (final cell in candidates) {
      final cellLocal = _cellToLocal(cell);
      final distanceSquared = localPos.distanceToSquared(cellLocal);
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        bestCell = cell;
      }
    }
    return bestCell;
  }

  List<(int, int)> _collectAttachCandidates({CollectableSquare? requester}) {
    final candidates = <(int, int)>{};
    for (final cell in _occupiedCells) {
      for (final neighbor in _neighbors(cell)) {
        if (_isAttachCellValid(neighbor, requester: requester)) {
          candidates.add(neighbor);
        }
      }
    }
    return candidates.toList();
  }

  bool _isAttachCellValid((int, int) cell, {CollectableSquare? requester}) {
    if (_occupiedCells.contains(cell)) return false;
    if (!_hasCardinalOccupiedNeighbor(cell)) return false;
    final owner = _reservedCells[cell];
    if (owner == null) return true;
    return owner == requester;
  }

  bool _hasCardinalOccupiedNeighbor((int, int) cell) {
    for (final neighbor in _neighbors(cell)) {
      if (_occupiedCells.contains(neighbor)) {
        return true;
      }
    }
    return false;
  }

  (int, int)? _resolveOrLockTargetCell(
    CollectableSquare square, {
    required bool forceRelock,
    required Vector2 worldPos,
  }) {
    final currentLock = square.lockedTargetCell;
    final canReuseCurrentLock = !forceRelock &&
        currentLock != null &&
        square.lockedTopologyVersion == _topologyVersion &&
        square.lockElapsed <= lockTimeoutSeconds &&
        _isAttachCellValid(currentLock, requester: square) &&
        _reserveCell(currentLock, square);
    if (canReuseCurrentLock) {
      return currentLock;
    }

    _releaseReservation(square);
    final candidate = _findNearestAttachCell(worldPos, requester: square);
    if (candidate == null) {
      square.clearMagnetLock();
      return null;
    }
    if (!_reserveCell(candidate, square)) {
      square.clearMagnetLock();
      return null;
    }

    square.lockedTargetCell = candidate;
    square.lockedTopologyVersion = _topologyVersion;
    square.lockElapsed = 0;
    square.magnetState = MagnetState.attracted;
    return candidate;
  }

  bool _reserveCell((int, int) cell, CollectableSquare square) {
    final currentOwner = _reservedCells[cell];
    if (currentOwner != null && currentOwner != square) {
      return false;
    }
    _reservedCells[cell] = square;
    return true;
  }

  void _releaseReservation(CollectableSquare square) {
    final locked = square.lockedTargetCell;
    if (locked != null && _reservedCells[locked] == square) {
      _reservedCells.remove(locked);
    } else {
      _reservedCells.removeWhere((_, owner) => owner == square);
    }
  }

  void _refreshMagnetCandidates(double dt) {
    _candidateRefreshElapsed += dt;
    if (_candidateRefreshElapsed < candidateRefreshInterval) return;
    _candidateRefreshElapsed = 0;

    final rawSquares = game.getNearbySquares();
    _magnetCandidates.clear();
    final playerPos = absolutePosition;
    final expandedEdgeBounds = _buildExpandedEdgeCandidateWorldBounds(attractionRadius);

    for (final s in rawSquares) {
      if (!_isWithinRect(s.absolutePosition, expandedEdgeBounds)) continue;
      if (enableVisibleCandidateFilter &&
          !game.isWorldPositionInExpandedView(
            s.absolutePosition,
            margin: visibleCandidateMargin,
          )) {
        continue;
      }
      _magnetCandidates.add(s);
    }

    // Sort by distance squared ascending to prioritize closest squares.
    _magnetCandidates.sort((a, b) {
      return a.absolutePosition
          .distanceToSquared(playerPos)
          .compareTo(b.absolutePosition.distanceToSquared(playerPos));
    });

    if (_magnetCandidates.isEmpty) {
      _magnetBatchCursor = 0;
      return;
    }
    _magnetBatchCursor %= _magnetCandidates.length;
  }

  Rect _buildExpandedEdgeCandidateWorldBounds(double padding) {
    final rawBounds = _buildAttachCandidateWorldBounds();
    if (rawBounds == null) {
      final center = Offset(absolutePosition.x, absolutePosition.y);
      return Rect.fromCenter(center: center, width: padding * 2, height: padding * 2);
    }
    return Rect.fromLTRB(
      rawBounds.left - padding,
      rawBounds.top - padding,
      rawBounds.right + padding,
      rawBounds.bottom + padding,
    );
  }

  Rect? _buildAttachCandidateWorldBounds() {
    final candidates = _collectAttachCandidates();
    if (candidates.isEmpty) return null;

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    for (final cell in candidates) {
      final worldCenter = absolutePositionOf(_cellToLocal(cell));
      if (worldCenter.x < minX) minX = worldCenter.x;
      if (worldCenter.y < minY) minY = worldCenter.y;
      if (worldCenter.x > maxX) maxX = worldCenter.x;
      if (worldCenter.y > maxY) maxY = worldCenter.y;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _isWithinRect(Vector2 point, Rect rect) {
    return rect.contains(Offset(point.x, point.y));
  }

  void _updateMagnetismBatch(double dt) {
    if (_magnetCandidates.isEmpty) return;

    final count = math.min(magnetBatchSize, _magnetCandidates.length);
    for (var i = 0; i < count; i++) {
      final index = (_magnetBatchCursor + i) % _magnetCandidates.length;
      _processMagnetismForSquare(_magnetCandidates[index], dt);
    }
    _magnetBatchCursor = (_magnetBatchCursor + count) % _magnetCandidates.length;
  }

  Rect get clusterBounds {
    if (_occupiedCells.isEmpty) return Rect.zero;

    int minX = _occupiedCells.first.$1;
    int maxX = _occupiedCells.first.$1;
    int minY = _occupiedCells.first.$2;
    int maxY = _occupiedCells.first.$2;

    for (final cell in _occupiedCells) {
      if (cell.$1 < minX) minX = cell.$1;
      if (cell.$1 > maxX) maxX = cell.$1;
      if (cell.$2 < minY) minY = cell.$2;
      if (cell.$2 > maxY) maxY = cell.$2;
    }

    return Rect.fromLTRB(
      minX * cellSize,
      minY * cellSize,
      (maxX + 1) * cellSize,
      (maxY + 1) * cellSize,
    );
  }

  void _processMagnetismForSquare(CollectableSquare square, double dt) {
    if (square.isAttached) {
      _releaseReservation(square);
      return;
    }

    square.lockElapsed += dt;
    final targetCell = _resolveOrLockTargetCell(
      square,
      forceRelock: false,
      worldPos: square.absolutePosition,
    );
    if (targetCell == null) {
      square.attachRequestedThisFrame = false;
      return;
    }

    // Calculate target world position relative to Player's center, accounting for rotation.
    final targetWorld = absolutePositionOf(_cellToLocal(targetCell));
    _tempVec1.setFrom(targetWorld);
    _tempVec1.sub(square.absolutePosition);
    final distanceSquared = _tempVec1.length2;
    final maxAttractionDistanceSquared = attractionRadius * attractionRadius;
    if (distanceSquared > maxAttractionDistanceSquared) {
      _releaseReservation(square);
      square.clearMagnetLock();
      square.attachRequestedThisFrame = false;
      return;
    }
    if (distanceSquared == 0) {
      if (square.attachRequestedThisFrame) {
        requestAttach(square);
      }
      square.attachRequestedThisFrame = false;
      return;
    }

    final distance = math.sqrt(distanceSquared);
    final strength = 1.0 - (distance / attractionRadius);
    
    // direction = _tempVec1 / distance
    _tempVec1.scale(1.0 / distance); 
    square.position.addScaled(_tempVec1, strength * attractionForce * dt);

    // Smoothly rotate the square to align with the Player's orientation.
    final angleDiff = angle - square.angle;
    final normalizedDiff = (angleDiff + math.pi) % (2 * math.pi) - math.pi;
    square.angle += normalizedDiff * (strength * 5.0) * dt;

    // Add to attraction targets for visual effect.
    _activeAttractionTargets.add(AttractionTarget(
      source: _cellToLocal(targetCell),
      target: toLocal(square.absolutePosition),
      strength: strength,
    ));

    if (square.attachRequestedThisFrame || distanceSquared <= snapDistance * snapDistance) {
      requestAttach(square);
    }
    square.attachRequestedThisFrame = false;
  }

  Iterable<(int, int)> _neighbors((int, int) cell) sync* {
    yield (cell.$1 + 1, cell.$2);
    yield (cell.$1 - 1, cell.$2);
    yield (cell.$1, cell.$2 + 1);
    yield (cell.$1, cell.$2 - 1);
  }

  Vector2 _cellToLocal((int, int) cell) {
    return _cellLocalPositionCache.putIfAbsent(
      cell,
      () => Vector2(cell.$1 * cellSize + cellSize / 2, cell.$2 * cellSize + cellSize / 2),
    );
  }
}
