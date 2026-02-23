import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'ui/debug_panel.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GameWidget<FusionGame>(
        game: FusionGame(),
        overlayBuilderMap: {
          'DebugPanel': (context, game) => Align(
                alignment: Alignment.topRight,
                child: DebugPanel(game: game),
              ),
        },
        initialActiveOverlays: const ['DebugPanel'],
      ),
    ),
  );
}
