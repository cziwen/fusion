enum EliminationRule {
  match5,
  pyramid531,
  square3x3,
}

class MatchEngine {
  final Set<EliminationRule> enabledRules = {
    EliminationRule.match5,
    EliminationRule.pyramid531,
    EliminationRule.square3x3,
  };

  Set<(int, int)> findMatches(Set<(int, int)> occupiedCells) {
    final toRemove = <(int, int)>{};

    if (enabledRules.contains(EliminationRule.match5)) {
      toRemove.addAll(_findMatch5(occupiedCells));
    }
    if (enabledRules.contains(EliminationRule.pyramid531)) {
      toRemove.addAll(_findPyramid531(occupiedCells));
    }
    if (enabledRules.contains(EliminationRule.square3x3)) {
      toRemove.addAll(_findSquare3x3(occupiedCells));
    }

    return toRemove;
  }

  Set<(int, int)> _findMatch5(Set<(int, int)> occupiedCells) {
    final matches = <(int, int)>{};
    bool isOccupied((int, int) cell) => occupiedCells.contains(cell);

    for (final cell in occupiedCells) {
      if (cell == (0, 0)) continue;

      // Horizontal
      final horizontalMatch = <(int, int)>{cell};
      for (int i = 1; i < 5; i++) {
        final nextCell = (cell.$1 + i, cell.$2);
        if (nextCell != (0, 0) && isOccupied(nextCell)) {
          horizontalMatch.add(nextCell);
        } else {
          break;
        }
      }
      if (horizontalMatch.length >= 5) {
        matches.addAll(horizontalMatch);
      }

      // Vertical
      final verticalMatch = <(int, int)>{cell};
      for (int i = 1; i < 5; i++) {
        final nextCell = (cell.$1, cell.$2 + i);
        if (nextCell != (0, 0) && isOccupied(nextCell)) {
          verticalMatch.add(nextCell);
        } else {
          break;
        }
      }
      if (verticalMatch.length >= 5) {
        matches.addAll(verticalMatch);
      }
    }
    return matches;
  }

  Set<(int, int)> _findPyramid531(Set<(int, int)> occupiedCells) {
    final matches = <(int, int)>{};
    bool isOccupied((int, int) cell) => occupiedCells.contains(cell);

    // Define 4 orientations for 5-3-1 pyramid
    final orientations = [
      // Up: base at y=0, middle at y=1, top at y=2
      [
        (-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0),
        (-1, 1), (0, 1), (1, 1),
        (0, 2)
      ],
      // Down: base at y=0, middle at y=-1, top at y=-2
      [
        (-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0),
        (-1, -1), (0, -1), (1, -1),
        (0, -2)
      ],
      // Right: base at x=0, middle at x=1, top at x=2
      [
        (0, -2), (0, -1), (0, 0), (0, 1), (0, 2),
        (1, -1), (1, 0), (1, 1),
        (2, 0)
      ],
      // Left: base at x=0, middle at x=-1, top at x=-2
      [
        (0, -2), (0, -1), (0, 0), (0, 1), (0, 2),
        (-1, -1), (-1, 0), (-1, 1),
        (-2, 0)
      ],
    ];

    for (final cell in occupiedCells) {
      if (cell == (0, 0)) continue;

      for (final offsets in orientations) {
        final currentMatch = <(int, int)>{};
        bool possible = true;
        for (final offset in offsets) {
          final target = (cell.$1 + offset.$1, cell.$2 + offset.$2);
          if (target == (0, 0) || !isOccupied(target)) {
            possible = false;
            break;
          }
          currentMatch.add(target);
        }
        if (possible) {
          matches.addAll(currentMatch);
        }
      }
    }
    return matches;
  }

  Set<(int, int)> _findSquare3x3(Set<(int, int)> occupiedCells) {
    final matches = <(int, int)>{};
    bool isOccupied((int, int) cell) => occupiedCells.contains(cell);

    final offsets = [
      (0, 0), (1, 0), (2, 0),
      (0, 1), (1, 1), (2, 1),
      (0, 2), (1, 2), (2, 2),
    ];

    for (final cell in occupiedCells) {
      if (cell == (0, 0)) continue;

      final currentMatch = <(int, int)>{};
      bool possible = true;
      for (final offset in offsets) {
        final target = (cell.$1 + offset.$1, cell.$2 + offset.$2);
        if (target == (0, 0) || !isOccupied(target)) {
          possible = false;
          break;
        }
        currentMatch.add(target);
      }
      if (possible) {
        matches.addAll(currentMatch);
      }
    }
    return matches;
  }
}
