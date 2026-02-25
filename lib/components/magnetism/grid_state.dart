import '../collectable_square.dart';

class GridState {
  final Set<(int, int)> _occupiedCells = {(0, 0)};
  final Map<(int, int), CollectableSquare> _attachedSquares = {};
  final Map<(int, int), CollectableSquare> _reservedCells = {};
  int _topologyVersion = 0;

  int get topologyVersion => _topologyVersion;
  Iterable<(int, int)> get occupiedCells => _occupiedCells;
  Iterable<(int, int)> get attachedCells => _attachedSquares.keys;
  Iterable<CollectableSquare> get attachedSquares => _attachedSquares.values;

  bool isOccupied((int, int) cell) => _occupiedCells.contains(cell);

  CollectableSquare? attachedAt((int, int) cell) => _attachedSquares[cell];

  Iterable<(int, int)> neighbors((int, int) cell) sync* {
    yield (cell.$1 + 1, cell.$2);
    yield (cell.$1 - 1, cell.$2);
    yield (cell.$1, cell.$2 + 1);
    yield (cell.$1, cell.$2 - 1);
  }

  bool hasCardinalOccupiedNeighbor((int, int) cell) {
    for (final neighbor in neighbors(cell)) {
      if (_occupiedCells.contains(neighbor)) {
        return true;
      }
    }
    return false;
  }

  bool isAttachCellValid((int, int) cell, {CollectableSquare? requester}) {
    if (_occupiedCells.contains(cell)) return false;
    if (!hasCardinalOccupiedNeighbor(cell)) return false;
    final owner = _reservedCells[cell];
    if (owner == null) return true;
    return owner == requester;
  }

  List<(int, int)> collectAttachCandidates({CollectableSquare? requester}) {
    final candidates = <(int, int)>{};
    for (final cell in _occupiedCells) {
      for (final neighbor in neighbors(cell)) {
        if (isAttachCellValid(neighbor, requester: requester)) {
          candidates.add(neighbor);
        }
      }
    }
    return candidates.toList();
  }

  bool reserveCell((int, int) cell, CollectableSquare square) {
    final owner = _reservedCells[cell];
    if (owner != null && owner != square) {
      return false;
    }
    _reservedCells[cell] = square;
    return true;
  }

  void releaseReservation(CollectableSquare square) {
    final locked = square.lockedTargetCell;
    if (locked != null && _reservedCells[locked] == square) {
      _reservedCells.remove(locked);
      return;
    }
    _reservedCells.removeWhere((_, owner) => owner == square);
  }

  void addAttached((int, int) cell, CollectableSquare square) {
    _occupiedCells.add(cell);
    _attachedSquares[cell] = square;
  }

  CollectableSquare? removeAttached((int, int) cell) {
    _occupiedCells.remove(cell);
    return _attachedSquares.remove(cell);
  }

  bool containsSquare(CollectableSquare square) {
    return _attachedSquares.containsValue(square);
  }

  void bumpTopology() {
    _topologyVersion += 1;
  }

  /// 检查并修复网格状态的一致性，防止内存泄漏或幽灵占位
  void validateAndRepair() {
    // 1. 确保 _attachedSquares 与 _occupiedCells 同步（核心 (0,0) 除外）
    final attachedKeys = _attachedSquares.keys.toSet();
    final occupiedWithoutCore = _occupiedCells.where((c) => c != (0, 0)).toSet();

    if (attachedKeys.length != occupiedWithoutCore.length ||
        !attachedKeys.containsAll(occupiedWithoutCore) ||
        !occupiedWithoutCore.containsAll(attachedKeys)) {
      _occupiedCells.clear();
      _occupiedCells.add((0, 0));
      _occupiedCells.addAll(attachedKeys);
    }

    // 2. 清理失效的预约
    _reservedCells.removeWhere((cell, owner) {
      // 如果预约者已经挂载到了网格，且挂载点不是当前预约点，则预约失效
      if (owner.isAttached) {
        final actualCell = _attachedSquares.entries
            .where((e) => e.value == owner)
            .map((e) => e.key)
            .firstOrNull;
        if (actualCell != null && actualCell != cell) return true;
      }
      return false;
    });
  }
}
