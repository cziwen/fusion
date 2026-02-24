import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'components/player.dart';
import 'components/collectable_square.dart';

class FusionGame extends FlameGame with HasKeyboardHandlerComponents, HasCollisionDetection {
  late Player player;
  late TextComponent massText;

  static const double minSpawnRadius = 300.0;
  static const double chunkSize = 500.0;
  static const int activeRadius = 5;

  bool enableAutoZoom = true;
  double zoomSensitivity = 0.15; // 0.0 到 1.0 之间，越高缩放越明显
  double minZoom = 0.15;
  double maxZoom = 1.0;
  double zoomSpeed = 2.0;

  final Map<Point<int>, List<CollectableSquare>> _chunks = {};
  Point<int>? _currentChunk;

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    player = Player()
      ..position = Vector2.zero()
      ..anchor = Anchor.center;
    world.add(player);

    camera.viewfinder.anchor = Anchor.center;
    camera.follow(player);

    // UI
    massText = TextComponent(
      text: 'Mass: 1',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontFamily: 'monospace',
        ),
      ),
      position: Vector2(20, 20),
    );
    camera.viewport.add(massText);

    _updateChunks();
  }

  @override
  void update(double dt) {
    super.update(dt);
    massText.text = 'Mass: ${player.children.whereType<CollectableSquare>().length + 1}';
    _updateCameraZoom(dt);
    _updateChunks();
  }

  void _updateCameraZoom(double dt) {
    if (!enableAutoZoom) return;

    final bounds = player.clusterBounds;
    final clusterSize = max(bounds.width, bounds.height);
    const double initialSize = 20.0; // 核心方块的大小

    // 使用幂函数来实现非线性缩放效果，使缩放更平滑
    double targetZoom = pow(initialSize / clusterSize, zoomSensitivity).toDouble();
    targetZoom = targetZoom.clamp(minZoom, maxZoom);

    // 平滑过渡到目标缩放值
    camera.viewfinder.zoom += (targetZoom - camera.viewfinder.zoom) * zoomSpeed * dt;
  }

  void _updateChunks() {
    final playerPos = player.position;
    final chunkX = (playerPos.x / chunkSize).floor();
    final chunkY = (playerPos.y / chunkSize).floor();
    final currentChunk = Point(chunkX, chunkY);

    if (currentChunk != _currentChunk) {
      _currentChunk = currentChunk;
      _generateNearbyChunks(currentChunk);
      _cleanupFarChunks(currentChunk);
    }
  }

  void _generateNearbyChunks(Point<int> center) {
    for (int x = -activeRadius; x <= activeRadius; x++) {
      for (int y = -activeRadius; y <= activeRadius; y++) {
        final chunkPoint = Point(center.x + x, center.y + y);
        if (!_chunks.containsKey(chunkPoint)) {
          _generateChunk(chunkPoint);
        }
      }
    }
  }

  void _generateChunk(Point<int> chunkPoint) {
    final squares = <CollectableSquare>[];
    // Deterministic seed based on chunk coordinates
    final random = Random(chunkPoint.x * 10000 + chunkPoint.y);
    
    // Number of squares per chunk
    final count = 5 + random.nextInt(10);

    for (int i = 0; i < count; i++) {
      final pos = Vector2(
        chunkPoint.x * chunkSize + random.nextDouble() * chunkSize,
        chunkPoint.y * chunkSize + random.nextDouble() * chunkSize,
      );

      // Skip if too close to starting point
      if (pos.length < minSpawnRadius) continue;

      final square = CollectableSquare(position: pos)
        ..angle = random.nextDouble() * pi * 2;
      world.add(square);
      squares.add(square);
    }
    _chunks[chunkPoint] = squares;
  }

  void _cleanupFarChunks(Point<int> center) {
    final chunksToRemove = <Point<int>>[];
    for (final chunkPoint in _chunks.keys) {
      final dist = (chunkPoint.x - center.x).abs().toDouble() + 
                   (chunkPoint.y - center.y).abs().toDouble();
      
      // Use a slightly larger radius for cleanup to avoid flickering at boundaries
      if (dist > activeRadius + 2) {
        chunksToRemove.add(chunkPoint);
      }
    }

    for (final chunkPoint in chunksToRemove) {
      final squares = _chunks.remove(chunkPoint);
      if (squares != null) {
        for (final square in squares) {
          if (!square.isAttached) {
            square.removeFromParent();
          }
        }
      }
    }
  }

  void onSquareAttached(CollectableSquare square) {
    // Remove from chunk tracking when attached to player
    for (final squares in _chunks.values) {
      if (squares.remove(square)) break;
    }
  }

  List<CollectableSquare> getNearbySquares() {
    return _chunks.values
        .expand((list) => list)
        .where((s) => !s.isAttached)
        .toList();
  }

  Rect getExpandedVisibleWorldRect({double margin = 0}) {
    final rect = camera.visibleWorldRect;
    if (margin <= 0) return rect;
    return Rect.fromLTRB(
      rect.left - margin,
      rect.top - margin,
      rect.right + margin,
      rect.bottom + margin,
    );
  }

  bool isWorldPositionInExpandedView(Vector2 worldPosition, {double margin = 0}) {
    final rect = getExpandedVisibleWorldRect(margin: margin);
    return rect.contains(Offset(worldPosition.x, worldPosition.y));
  }
}
