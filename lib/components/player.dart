import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../game.dart';
import 'collectable_square.dart';
import 'magnetism/attach_pipeline.dart';
import 'magnetism/connectivity_engine.dart';
import 'magnetism/grid_state.dart';
import 'magnetism/magnet_motion_system.dart';
import 'magnetism/magnet_targeting_service.dart';
import 'magnetism/match_engine.dart';
import 'mixins/magnetic_effect_mixin.dart';
import 'mixins/core_effect_mixin.dart';

class Player extends RectangleComponent
    with HasGameReference<FusionGame>, CollisionCallbacks, MagneticEffectMixin, CoreEffectMixin {
  static const double cellSize = 20.0;
  double attractionRadius = 200.0;
  double attractionForce = 450.0;
  double candidateRefreshInterval = 0.0; // 禁用刷新间隔，每帧刷新
  int magnetBatchSize = 999; // 实际上在 _updateMagnetismBatch 中将全量处理
  bool enableVisibleCandidateFilter = false; // 禁用可见性过滤
  double visibleCandidateMargin = 100.0;
  static const double lockTimeoutSeconds = 1.2;
  static const double snapDistance = 6.0;

  final GridState _gridState = GridState();
  final MagnetTargetingService _targetingService = MagnetTargetingService();
  final MagnetMotionSystem _motionSystem = const MagnetMotionSystem();
  late final AttachPipeline _attachPipeline;
  MatchEngine get matchEngine => _attachPipeline.matchEngine;
  final List<CollectableSquare> _magnetCandidates = [];
  final Map<(int, int), Vector2> _cellLocalPositionCache = {};
  final Vector2 _tempVec1 = Vector2.zero();
  double _candidateRefreshElapsed = 0;

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
    _attachPipeline = AttachPipeline(
      gridState: _gridState,
      matchEngine: MatchEngine(),
      connectivityEngine: ConnectivityEngine(),
    );
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
    updateCoreEffects(dt);

    // 应用核心方块的呼吸特效（透明度微调）
    paint.color = Colors.white.withValues(alpha: 0.8 + coreBreathingValue * 0.2);

    // 同步玩家角度，使其在屏幕上保持正向
    angle = game.worldRotation;

    _refreshMagnetCandidates(dt);
    _updateMagnetismBatch(dt);

    // 每一帧结束前统一处理所有挂载事务与消除逻辑
    _attachPipeline.flush(
      onDetachedToWorld: (target) {
        game.world.add(target);
        game.onSquareDetached(target);
      },
      onMatch: (positions) {
        addMatchAbsorptionEffect(positions);
      },
      cellToLocal: _cellToLocal,
    );
  }

  @override
  void render(Canvas canvas) {
    _renderControlZone(canvas);
    renderCoreBackgroundEffects(canvas);
    super.render(canvas);
    renderCoreForegroundEffects(canvas);
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
    _attachPipeline.stageAttach(
      square,
      resolveTargetCell: () => _targetingService.resolveOrLockTargetCell(
        _gridState,
        square,
        forceRelock: true,
        worldPos: square.absolutePosition,
        lockTimeoutSeconds: lockTimeoutSeconds,
        toLocal: toLocal,
        cellToLocal: _cellToLocal,
      ),
      cellToLocal: _cellToLocal,
      absolutePositionOfLocal: absolutePositionOf,
      playerAngle: angle,
      moveUnderPlayer: (target) {
        target.removeFromParent();
        add(target);
      },
      onNeighborConnection: _onNeighborConnectionPulse,
      onAttached: game.onSquareAttached,
      onCameraShake: game.triggerCameraShake,
    );
  }

  void _refreshMagnetCandidates(double dt) {
    _candidateRefreshElapsed += dt;
    if (candidateRefreshInterval > 0 && _candidateRefreshElapsed < candidateRefreshInterval) return;
    _candidateRefreshElapsed = 0;

    final rawSquares = game.getNearbySquares();
    final previousCandidates = Set<CollectableSquare>.from(_magnetCandidates);
    _magnetCandidates.clear();
    
    // 移除所有空间和可见性过滤逻辑，全量处理游离方块
    for (final s in rawSquares) {
      _magnetCandidates.add(s);
    }

    // 清理那些不再是候选人的方块的预约信息（例如被移除或过远的方块）
    final currentCandidatesSet = _magnetCandidates.toSet();
    for (final oldSquare in previousCandidates) {
      if (!currentCandidatesSet.contains(oldSquare)) {
        _gridState.releaseReservation(oldSquare);
        oldSquare.clearMagnetLock();
      }
    }

    final playerPos = absolutePosition;
    // 按距离排序以保持逻辑确定性
    _magnetCandidates.sort((a, b) {
      return a.absolutePosition
          .distanceToSquared(playerPos)
          .compareTo(b.absolutePosition.distanceToSquared(playerPos));
    });

    if (_magnetCandidates.isEmpty) {
      return;
    }
  }

  void _updateMagnetismBatch(double dt) {
    if (_magnetCandidates.isEmpty) return;

    // 全量处理所有候选方块，忽略 magnetBatchSize 限制
    for (final square in _magnetCandidates) {
      _processMagnetismForSquare(square, dt);
    }
  }

  Rect get clusterBounds {
    final occupied = _gridState.occupiedCells.toList();
    if (occupied.isEmpty) return Rect.zero;

    int minX = occupied.first.$1;
    int maxX = occupied.first.$1;
    int minY = occupied.first.$2;
    int maxY = occupied.first.$2;

    for (final cell in occupied) {
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

    for (final cell in _gridState.attachedCells) {
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
      _gridState.releaseReservation(square);
      return;
    }

    // 防御性清理：如果拓扑版本不匹配，或者锁超时，强制清理预约
    if (square.lockedTargetCell != null &&
        (square.lockedTopologyVersion != _gridState.topologyVersion || square.lockElapsed > lockTimeoutSeconds)) {
      _gridState.releaseReservation(square);
      square.clearMagnetLock();
    }

    square.lockElapsed += dt;
    final targetCell = _targetingService.resolveOrLockTargetCell(
      _gridState,
      square,
      forceRelock: false,
      worldPos: square.absolutePosition,
      lockTimeoutSeconds: lockTimeoutSeconds,
      toLocal: toLocal,
      cellToLocal: _cellToLocal,
    );
    if (targetCell == null) {
      square.attachRequestedThisFrame = false;
      return;
    }

    final targetWorld = absolutePositionOf(_cellToLocal(targetCell));
    final motion = _motionSystem.apply(
      square: square,
      attachRequestedThisFrame: square.attachRequestedThisFrame,
      targetWorld: targetWorld,
      playerWorldPosition: absolutePosition,
      playerWorldAngle: angle,
      attractionRadius: attractionRadius,
      attractionForce: attractionForce,
      controlRadius: controlRadius,
      snapDistance: snapDistance,
      dt: dt,
      tempDirection: _tempVec1,
    );

    if (motion.outOfRange) {
      _gridState.releaseReservation(square);
      square.clearMagnetLock();
      square.attachRequestedThisFrame = false;
      return;
    }

    _activeAttractionTargets.add(AttractionTarget(
      source: _cellToLocal(targetCell),
      target: toLocal(square.absolutePosition),
      strength: motion.strength,
    ));

    if (motion.shouldAttach) {
      requestAttach(square);
    }
    square.attachRequestedThisFrame = false;
  }

  Vector2 _cellToLocal((int, int) cell) {
    return _cellLocalPositionCache.putIfAbsent(
      cell,
      () => Vector2(cell.$1 * cellSize + cellSize / 2, cell.$2 * cellSize + cellSize / 2),
    );
  }

  void _onNeighborConnectionPulse((int, int) targetCell, (int, int) neighbor) {
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
