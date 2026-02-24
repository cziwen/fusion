import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../game.dart';
import 'collectable_square.dart';
import 'mixins/magnetic_effect_mixin.dart';

class Player extends RectangleComponent
    with HasGameReference<FusionGame>, CollisionCallbacks, MagneticEffectMixin {
  static const double cellSize = 20.0;
  double attractionRadius = 200.0;
  double attractionForce = 600.0;
  double candidateRefreshInterval = 0.15;
  int magnetBatchSize = 48;
  bool enableVisibleCandidateFilter = true;
  double visibleCandidateMargin = 100.0;
  static const double lockTimeoutSeconds = 1.2;
  static const double snapDistance = 6.0;

  final Set<(int, int)> _occupiedCells = {(0, 0)};
  final Map<(int, int), CollectableSquare> _attachedSquares = {}; // 新增：用于快速查找已挂载方块
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
  final Paint _controlRingPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  final Paint _controlTickPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.55)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  Player()
      : super(
          size: Vector2.all(20),
          paint: Paint()..color = Colors.white,
        ) {
    add(RectangleHitbox());
  }

  // Keep control zone radius fully aligned with attraction radius.
  double get controlRadius => attractionRadius;
  set controlRadius(double value) => attractionRadius = value;

  @override
  void update(double dt) {
    super.update(dt);

    _activeAttractionTargets.clear();
    updatePulses(dt);

    // 同步玩家角度，使其在屏幕上保持正向
    angle = game.worldRotation;

    _refreshMagnetCandidates(dt);
    _updateMagnetismBatch(dt);
  }

  @override
  void render(Canvas canvas) {
    _renderControlZone(canvas);
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

  void _renderControlZone(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    canvas.drawCircle(center, controlRadius, _controlRingPaint);

    const tickCount = 4;
    const tickLength = 10.0;
    for (var i = 0; i < tickCount; i++) {
      final angle = (math.pi / 2) * i;
      final dir = Vector2(math.cos(angle), math.sin(angle));
      final inner = center + Offset(dir.x * (controlRadius - tickLength), dir.y * (controlRadius - tickLength));
      final outer = center + Offset(dir.x * controlRadius, dir.y * controlRadius);
      canvas.drawLine(inner, outer, _controlTickPaint);
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

  void requestAttach(CollectableSquare square) {
    if (square.isAttached || square.magnetState == MagnetState.attaching) return;
    attachSquare(square);
  }

  void attachSquare(CollectableSquare square) {
    if (square.isAttached || square.magnetState == MagnetState.attaching) return;
    
    // 1. 预解析目标格子
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

    // 2. 更新逻辑状态
    square.magnetState = MagnetState.attaching;
    _occupiedCells.add(targetCell);
    _attachedSquares[targetCell] = square;
    square.isAttached = true;

    // 3. 立即触发消除和连通性检查
    _checkMatches();
    _checkConnectivity();

    // 4. 检查方块是否仍然属于 Player 集群
    if (!_attachedSquares.containsValue(square)) {
      // 方块已被消除或脱离，释放预约并重置状态
      _releaseReservation(square);
      square.clearMagnetLock();
      square.attachRequestedThisFrame = false;
      return;
    }

    // 5. 如果仍然存在，执行视觉挂载
    final finalLocalPos = _cellToLocal(targetCell);
    final targetWorldPos = absolutePositionOf(finalLocalPos);

    _releaseReservation(square);
    square.attachRequestedThisFrame = false;
    square.magnetState = MagnetState.attached;

    // 保持世界坐标一致直到下一次渲染
    square.position = targetWorldPos;
    square.pendingLocalPosition = finalLocalPos;
    
    final localAngle = square.angle - angle;
    final snappedLocalAngle = (localAngle / (math.pi / 2)).round() * (math.pi / 2);
    square.pendingLocalAngle = snappedLocalAngle;

    square.removeFromParent();
    add(square);

    // 6. 装饰性逻辑
    for (final neighbor in _neighbors(targetCell)) {
      if (_occupiedCells.contains(neighbor)) {
        final isVerticalConnection = neighbor.$1 == targetCell.$1;
        Vector2 pulseCenter;
        if (isVerticalConnection) {
          final y = math.max(neighbor.$2, targetCell.$2);
          pulseCenter = Vector2((targetCell.$1 + 0.5) * cellSize, y * cellSize);
        } else {
          final x = math.max(neighbor.$1, targetCell.$1);
          pulseCenter = Vector2(x * cellSize, (targetCell.$2 + 0.5) * cellSize);
        }
        addImpactPulse(pulseCenter, !isVerticalConnection, duration: pulseDuration);
      }
    }

    square.clearMagnetLock();
    _topologyVersion += 1;
    game.onSquareAttached(square);
    game.triggerCameraShake();
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

  bool hasAttachedSquareOutsideControlZone() {
    final localCenter = Vector2(size.x / 2, size.y / 2);
    final halfDiagonal = math.sqrt(2) * (cellSize / 2);
    final limit = controlRadius - halfDiagonal;

    for (final cell in _attachedSquares.keys) {
      final localPos = _cellToLocal(cell);
      final distance = localPos.distanceTo(localCenter);
      if (distance > limit) {
        return true;
      }
    }
    return false;
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

    // 控制环逻辑：进入 controlRadius 后，强制方块的角度位置与玩家网格对齐
    if (distance <= controlRadius) {
      // 计算方块相对于玩家的当前世界角度
      final currentAngle = math.atan2(
        square.absolutePosition.y - absolutePosition.y,
        square.absolutePosition.x - absolutePosition.x,
      );

      // 玩家当前的旋转（即网格的基准角度）
      final baseAngle = angle;
      
      // 找到最接近的 90 度倍数
      final relAngle = currentAngle - baseAngle;
      final targetRelAngle = (relAngle / (math.pi / 2)).round() * (math.pi / 2);
      final targetAngle = baseAngle + targetRelAngle;

      // 平滑或强制同步角度位置
      // 我们通过重新计算 position 来实现角位置同步
      final newPos = absolutePosition + 
          Vector2(math.cos(targetAngle), math.sin(targetAngle)) * distance;
      
      // 平滑过渡到对齐位置
      square.position.lerp(newPos, 10.0 * dt);
    }
    
    // direction = _tempVec1 / distance
    _tempVec1.scale(1.0 / distance); 
    square.position.addScaled(_tempVec1, strength * attractionForce * dt);

    // Smoothly rotate the square to align with the nearest 90-degree face of the Player.
    final relAngle = square.angle - angle;
    final targetRelAngle = (relAngle / (math.pi / 2)).round() * (math.pi / 2);
    final targetWorldAngle = angle + targetRelAngle;

    final angleDiff = targetWorldAngle - square.angle;
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

  void _checkMatches() {
    final toRemove = <(int, int)>{};

    // Helper to check if a cell is occupied (either core or attached square)
    bool isOccupied((int, int) cell) => _occupiedCells.contains(cell);

    // 1. Check Match 5 (Horizontal and Vertical)
    for (final cell in _occupiedCells) {
      // Horizontal
      var horizontalMatch = <(int, int)>{cell};
      // Check forward
      for (int i = 1; i < 5; i++) {
        final nextCell = (cell.$1 + i, cell.$2);
        if (isOccupied(nextCell)) {
          horizontalMatch.add(nextCell);
        } else {
          break;
        }
      }
      if (horizontalMatch.length >= 5) toRemove.addAll(horizontalMatch);

      // Vertical
      var verticalMatch = <(int, int)>{cell};
      // Check forward
      for (int i = 1; i < 5; i++) {
        final nextCell = (cell.$1, cell.$2 + i);
        if (isOccupied(nextCell)) {
          verticalMatch.add(nextCell);
        } else {
          break;
        }
      }
      if (verticalMatch.length >= 5) toRemove.addAll(verticalMatch);
    }

    // 2. Check Pyramid 6 (1-2-3 structure)
    final pyramidOffsets = [
      // Right-bottom staircase
      [(0,0), (1,0), (2,0), (0,1), (1,1), (0,2)],
      [(0,0), (-1,0), (-2,0), (0,1), (-1,1), (0,2)],
      [(0,0), (1,0), (2,0), (0,-1), (1,-1), (0,-2)],
      [(0,0), (-1,0), (-2,0), (0,-1), (-1,-1), (0,-2)],
      // Right-top staircase
      [(0,0), (0,1), (0,2), (1,0), (1,1), (2,0)],
      [(0,0), (0,-1), (0,-2), (1,0), (1,-1), (2,0)],
      [(0,0), (0,1), (0,2), (-1,0), (-1,1), (-2,0)],
      [(0,0), (0,-1), (0,-2), (-1,0), (-1,-1), (-2,0)],
    ];

    for (final cell in _occupiedCells) {
      for (final offsets in pyramidOffsets) {
        bool match = true;
        final currentPyramid = <(int, int)>{};
        for (final offset in offsets) {
          final target = (cell.$1 + offset.$1, cell.$2 + offset.$2);
          if (!isOccupied(target)) {
            match = false;
            break;
          }
          currentPyramid.add(target);
        }
        if (match) {
          toRemove.addAll(currentPyramid);
        }
      }
    }

    if (toRemove.isNotEmpty) {
      for (final cell in toRemove) {
        // 核心方块 (0,0) 不可被消除
        if (cell == (0, 0)) continue;
        
        final square = _attachedSquares.remove(cell);
        _occupiedCells.remove(cell);
        
        if (square != null) {
          square.isAttached = false;
          square.removeFromParent();
          // 注意：消除的方块不调用 game.onSquareDetached，因为我们不希望它们重新变为游离方块
        }
      }
      _topologyVersion++;
    }
  }

  void _checkConnectivity() {
    if (_occupiedCells.isEmpty) return;

    final connected = <(int, int)>{};
    final queue = <(int, int)>[(0, 0)];
    connected.add((0, 0));

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final neighbor in _neighbors(current)) {
        if (_occupiedCells.contains(neighbor) && !connected.contains(neighbor)) {
          connected.add(neighbor);
          queue.add(neighbor);
        }
      }
    }

    final orphans = <(int, int)>{};
    for (final cell in _occupiedCells) {
      if (!connected.contains(cell)) {
        orphans.add(cell);
      }
    }

    if (orphans.isNotEmpty) {
      for (final cell in orphans) {
        final square = _attachedSquares.remove(cell);
        _occupiedCells.remove(cell);
        if (square != null) {
          // 记录当前世界坐标和角度，脱离后保持位置
          final worldPos = square.absolutePosition;
          final worldAngle = square.absoluteAngle;

          // 将孤立方块释放回世界
          square.isAttached = false;
          square.magnetState = MagnetState.idle;
          
          if (square.parent != null) {
            square.removeFromParent();
          }
          
          // 设置回绝对坐标并添加到 game.world
          square.position = worldPos;
          square.angle = worldAngle;
          
          game.world.add(square);
          game.onSquareDetached(square);
        }
      }
      _topologyVersion++;
    }
  }
}
