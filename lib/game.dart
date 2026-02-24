import 'dart:async';
import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'components/player.dart';
import 'components/collectable_square.dart';

class FusionGame extends FlameGame with HasKeyboardHandlerComponents, HasCollisionDetection {
  late Player player;
  late TextComponent massText;
  TextComponent? gameOverText;

  static const double minSpawnRadius = 300.0;
  static const double spawnRadiusRange = 400.0;

  bool enableAutoZoom = false; // 禁用自动缩放
  double zoomSensitivity = 0.15;
  double minZoom = 0.15;
  double maxZoom = 1.0;
  double zoomSpeed = 2.0;
  double freeDriftSpeed = 18.0;
  double spawnIntervalSeconds = 1.2;
  int spawnCountPerTick = 3;

  double worldRotation = 0.0;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  final Set<CollectableSquare> _freeSquares = {};
  double _spawnElapsed = 0.0;

  final Set<LogicalKeyboardKey> _keysPressed = {};
  bool isGameOver = false;
  final Random _cameraShakeRandom = Random();
  final Random _random = Random();
  double _cameraShakeTimeRemaining = 0.0;
  double _cameraShakeDuration = 0.0;
  double _cameraShakeIntensity = 0.0;

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
    spawnNow();

    // 监听陀螺仪
    _gyroSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      // 在移动端，y 轴旋转通常对应手机的左右倾斜（水平旋转环境）
      // 这里的 0.05 是灵敏度系数，可以根据实际手感调整
      worldRotation += event.y * 0.05;
    });
  }

  @override
  void onRemove() {
    _gyroSubscription?.cancel();
    super.onRemove();
  }

  @override
  void update(double dt) {
    if (isGameOver) return;
    super.update(dt);
    
    // 键盘模拟旋转
    if (_keysPressed.contains(LogicalKeyboardKey.keyQ) || _keysPressed.contains(LogicalKeyboardKey.comma)) {
      worldRotation -= 3.0 * dt;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.keyE) || _keysPressed.contains(LogicalKeyboardKey.period)) {
      worldRotation += 3.0 * dt;
    }

    // 同步相机角度
    camera.viewfinder.angle = worldRotation;

    massText.text = 'Mass: ${player.children.whereType<CollectableSquare>().length + 1}';
    if (player.hasAttachedSquareOutsideControlZone()) {
      _triggerGameOver();
    }
    _updateSpawner(dt);
    _updateFreeSquareDrift(dt);
    _applyCameraShake(dt);
    _updateCameraZoom(dt);
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (isGameOver) return KeyEventResult.handled;
    if (event is KeyDownEvent) {
      _keysPressed.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _keysPressed.remove(event.logicalKey);
    }
    return super.onKeyEvent(event, keysPressed);
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

  void onSquareAttached(CollectableSquare square) {
    _freeSquares.remove(square);
  }

  void onSquareDetached(CollectableSquare square) {
    if (!square.isAttached) {
      _freeSquares.add(square);
    }
  }

  List<CollectableSquare> getNearbySquares() {
    _pruneFreeSquares();
    return _freeSquares
        .where((s) => !s.isAttached && s.isMounted)
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

  void _updateSpawner(double dt) {
    _spawnElapsed += dt;
    if (_spawnElapsed < spawnIntervalSeconds) return;
    _spawnElapsed = 0.0;
    spawnNow();
  }

  void spawnNow() {
    if (isGameOver) return;
    final center = player.absolutePosition;
    for (var i = 0; i < spawnCountPerTick; i++) {
      final theta = _random.nextDouble() * pi * 2;
      final radius = minSpawnRadius + _random.nextDouble() * spawnRadiusRange;
      final pos = Vector2(
        center.x + cos(theta) * radius,
        center.y + sin(theta) * radius,
      );
      final square = CollectableSquare(position: pos)..angle = _random.nextDouble() * pi * 2;
      world.add(square);
      _freeSquares.add(square);
    }
  }

  void _updateFreeSquareDrift(double dt) {
    if (_freeSquares.isEmpty) return;
    _pruneFreeSquares();
    final playerCenter = player.absolutePosition;
    for (final square in _freeSquares) {
      if (!square.isMounted) continue;
      final delta = playerCenter - square.absolutePosition;
      if (delta.length2 < 0.0001) continue;
      delta.normalize();
      square.position += delta * freeDriftSpeed * dt;
    }
  }

  void _pruneFreeSquares() {
    _freeSquares.removeWhere((square) {
      if (square.isAttached) return true;
      // Keep newly spawned squares that are pending mount; drop only detached stale references.
      return !square.isMounted && square.parent == null;
    });
  }

  void triggerCameraShake({double duration = 0.12, double intensity = 3.5}) {
    if (isGameOver) return;
    _cameraShakeDuration = duration;
    _cameraShakeTimeRemaining = duration;
    _cameraShakeIntensity = intensity;
  }

  void _triggerGameOver() {
    if (isGameOver) return;
    isGameOver = true;
    _keysPressed.clear();
    massText.text = '${massText.text}  |  GAME OVER';

    final viewportSize = camera.viewport.virtualSize;
    gameOverText = TextComponent(
      text: 'GAME OVER',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
      position: Vector2(viewportSize.x / 2, viewportSize.y / 2),
      anchor: Anchor.center,
    );
    camera.viewport.add(gameOverText!);
  }

  void _applyCameraShake(double dt) {
    if (_cameraShakeTimeRemaining <= 0) return;
    _cameraShakeTimeRemaining = (_cameraShakeTimeRemaining - dt).clamp(0.0, _cameraShakeDuration);

    final decay = (_cameraShakeDuration <= 0) ? 0.0 : (_cameraShakeTimeRemaining / _cameraShakeDuration);
    final amplitude = _cameraShakeIntensity * decay;
    final offsetX = (_cameraShakeRandom.nextDouble() * 2 - 1) * amplitude;
    final offsetY = (_cameraShakeRandom.nextDouble() * 2 - 1) * amplitude;
    camera.viewfinder.position.add(Vector2(offsetX, offsetY));
  }
}
