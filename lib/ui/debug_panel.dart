import 'package:flutter/material.dart';
import '../game.dart';
import '../components/mixins/magnetic_effect_mixin.dart';

class DebugPanel extends StatefulWidget {
  final FusionGame game;
  const DebugPanel({super.key, required this.game});

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  bool _isExpanded = false;
  bool _isMagnetismExpanded = false;
  bool _isVisualExpanded = true;
  bool _isCameraExpanded = false;

  @override
  Widget build(BuildContext context) {
    final player = widget.game.player;

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              child: Text(_isExpanded ? 'Hide Debug' : 'Show Debug'),
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 8),
              Container(
                width: 250,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isMagnetismExpanded = !_isMagnetismExpanded;
                        });
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Magnetism Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Icon(
                            _isMagnetismExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                    if (_isMagnetismExpanded) ...[
                      const SizedBox(height: 16),
                      _buildSlider(
                        label: 'Radius: ${player.attractionRadius.toStringAsFixed(0)}',
                        value: player.attractionRadius,
                        min: 0,
                        max: 500,
                        onChanged: (val) {
                          setState(() {
                            player.attractionRadius = val;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSlider(
                        label: 'Force: ${player.attractionForce.toStringAsFixed(0)}',
                        value: player.attractionForce,
                        min: 0,
                        max: 2000,
                        onChanged: (val) {
                          setState(() {
                            player.attractionForce = val;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSlider(
                        label: 'Batch Size: ${player.magnetBatchSize}',
                        value: player.magnetBatchSize.toDouble(),
                        min: 1,
                        max: 100,
                        divisions: 99,
                        onChanged: (val) {
                          setState(() {
                            player.magnetBatchSize = val.toInt();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSlider(
                        label: 'Refresh Intv: ${player.candidateRefreshInterval.toStringAsFixed(2)}s',
                        value: player.candidateRefreshInterval,
                        min: 0.01,
                        max: 1.0,
                        onChanged: (val) {
                          setState(() {
                            player.candidateRefreshInterval = val;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildCheckbox(
                        label: 'Visible Filter',
                        value: player.enableVisibleCandidateFilter,
                        onChanged: (val) {
                          setState(() {
                            player.enableVisibleCandidateFilter = val ?? true;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSlider(
                        label: 'Visible Margin: ${player.visibleCandidateMargin.toStringAsFixed(0)}',
                        value: player.visibleCandidateMargin,
                        min: 0,
                        max: 300,
                        onChanged: (val) {
                          setState(() {
                            player.visibleCandidateMargin = val;
                          });
                        },
                      ),
                    ],
                    const Divider(color: Colors.white24, height: 24),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isVisualExpanded = !_isVisualExpanded;
                        });
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Visual Effects',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Icon(
                            _isVisualExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                    if (_isVisualExpanded) ...[
                      const SizedBox(height: 16),
                      _buildCheckbox(
                        label: 'Show Lines',
                        value: player.showAttractionLines,
                        onChanged: (val) {
                          setState(() {
                            player.showAttractionLines = val!;
                          });
                        },
                      ),
                      _buildCheckbox(
                        label: 'Show Pulses',
                        value: player.showImpactPulses,
                        onChanged: (val) {
                          setState(() {
                            player.showImpactPulses = val!;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildDropdown<AttractionStyle>(
                        label: 'Gravity Style',
                        value: player.attractionStyle,
                        items: AttractionStyle.values,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              player.attractionStyle = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSlider(
                        label: 'Pulse Duration: ${player.pulseDuration.toStringAsFixed(2)}s',
                        value: player.pulseDuration,
                        min: 0.1,
                        max: 2.0,
                        onChanged: (val) {
                          setState(() {
                            player.pulseDuration = val;
                          });
                        },
                      ),
                    ],
                    const Divider(color: Colors.white24, height: 24),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isCameraExpanded = !_isCameraExpanded;
                        });
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Camera Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Icon(
                            _isCameraExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                    if (_isCameraExpanded) ...[
                      const SizedBox(height: 16),
                      _buildCheckbox(
                        label: 'Auto Zoom',
                        value: widget.game.enableAutoZoom,
                        onChanged: (val) {
                          setState(() {
                            widget.game.enableAutoZoom = val!;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSlider(
                        label: 'Sensitivity: ${widget.game.zoomSensitivity.toStringAsFixed(2)}',
                        value: widget.game.zoomSensitivity,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (val) {
                          setState(() {
                            widget.game.zoomSensitivity = val;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSlider(
                        label: 'Min Zoom: ${widget.game.minZoom.toStringAsFixed(2)}',
                        value: widget.game.minZoom,
                        min: 0.05,
                        max: 0.5,
                        onChanged: (val) {
                          setState(() {
                            widget.game.minZoom = val;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSlider(
                        label: 'Zoom Speed: ${widget.game.zoomSpeed.toStringAsFixed(1)}',
                        value: widget.game.zoomSpeed,
                        min: 0.5,
                        max: 10.0,
                        onChanged: (val) {
                          setState(() {
                            widget.game.zoomSpeed = val;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            side: const BorderSide(color: Colors.white70),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildDropdown<T extends Enum>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Theme(
          data: Theme.of(context).copyWith(
            canvasColor: Colors.grey[900],
          ),
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            underline: Container(height: 1, color: Colors.white24),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            items: items.map((T item) {
              return DropdownMenuItem<T>(
                value: item,
                child: Text(item.name),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: Colors.blueAccent,
          inactiveColor: Colors.white24,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
