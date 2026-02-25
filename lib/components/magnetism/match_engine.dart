class MatchEngine {
  Set<(int, int)> findMatches(Set<(int, int)> occupiedCells) {
    final toRemove = <(int, int)>{};

    bool isOccupied((int, int) cell) => occupiedCells.contains(cell);

    for (final cell in occupiedCells) {
      final horizontalMatch = <(int, int)>{cell};
      for (int i = 1; i < 5; i++) {
        final nextCell = (cell.$1 + i, cell.$2);
        if (isOccupied(nextCell)) {
          horizontalMatch.add(nextCell);
        } else {
          break;
        }
      }
      if (horizontalMatch.length >= 5) {
        toRemove.addAll(horizontalMatch);
      }

      final verticalMatch = <(int, int)>{cell};
      for (int i = 1; i < 5; i++) {
        final nextCell = (cell.$1, cell.$2 + i);
        if (isOccupied(nextCell)) {
          verticalMatch.add(nextCell);
        } else {
          break;
        }
      }
      if (verticalMatch.length >= 5) {
        toRemove.addAll(verticalMatch);
      }
    }

    final pyramidOffsets = [
      [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (0, 2)],
      [(0, 0), (-1, 0), (-2, 0), (0, 1), (-1, 1), (0, 2)],
      [(0, 0), (1, 0), (2, 0), (0, -1), (1, -1), (0, -2)],
      [(0, 0), (-1, 0), (-2, 0), (0, -1), (-1, -1), (0, -2)],
      [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (2, 0)],
      [(0, 0), (0, -1), (0, -2), (1, 0), (1, -1), (2, 0)],
      [(0, 0), (0, 1), (0, 2), (-1, 0), (-1, 1), (-2, 0)],
      [(0, 0), (0, -1), (0, -2), (-1, 0), (-1, -1), (-2, 0)],
    ];

    for (final cell in occupiedCells) {
      for (final offsets in pyramidOffsets) {
        var match = true;
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

    toRemove.remove((0, 0));
    return toRemove;
  }
}
