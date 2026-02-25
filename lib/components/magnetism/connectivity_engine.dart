class ConnectivityEngine {
  Set<(int, int)> findOrphans(Set<(int, int)> occupiedCells) {
    if (occupiedCells.isEmpty) return {};

    final connected = <(int, int)>{(0, 0)};
    final queue = <(int, int)>[(0, 0)];

    Iterable<(int, int)> neighbors((int, int) cell) sync* {
      yield (cell.$1 + 1, cell.$2);
      yield (cell.$1 - 1, cell.$2);
      yield (cell.$1, cell.$2 + 1);
      yield (cell.$1, cell.$2 - 1);
    }

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final neighbor in neighbors(current)) {
        if (occupiedCells.contains(neighbor) && !connected.contains(neighbor)) {
          connected.add(neighbor);
          queue.add(neighbor);
        }
      }
    }

    final orphans = <(int, int)>{};
    for (final cell in occupiedCells) {
      if (!connected.contains(cell)) {
        orphans.add(cell);
      }
    }
    orphans.remove((0, 0));
    return orphans;
  }
}
