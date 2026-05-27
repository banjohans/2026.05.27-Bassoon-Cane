import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/cane.dart';
import '../models/reed.dart';
import '../services/prediction_engine.dart';
import '../services/resonance_capture_service.dart';
import '../state/app_controller.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        if (controller.isLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final pages = [
          _DashboardTab(controller: controller),
          _BehaviorTab(controller: controller),
          _CaneTab(controller: controller),
          _ReedTab(controller: controller),
        ];

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('ReedLab'),
            actions: [
              if (controller.errorMessage != null)
                IconButton(
                  icon: const Icon(Icons.warning_amber_rounded),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(controller.errorMessage!)),
                    );
                  },
                ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE5E2D8), Color(0xFFE7EFE9), Color(0xFFD8E2E6)],
              ),
            ),
            child: SafeArea(child: pages[_tab]),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'Behavior'),
              NavigationDestination(icon: Icon(Icons.straighten), label: 'Cane'),
              NavigationDestination(icon: Icon(Icons.library_music), label: 'Reeds'),
            ],
          ),
        );
      },
    );
  }
}

enum _DashboardRange { month, threeMonths, sixMonths, year, all }

extension _DashboardRangeX on _DashboardRange {
  String get label {
    switch (this) {
      case _DashboardRange.month:
        return '1M';
      case _DashboardRange.threeMonths:
        return '3M';
      case _DashboardRange.sixMonths:
        return '6M';
      case _DashboardRange.year:
        return '1Y';
      case _DashboardRange.all:
        return 'All';
    }
  }

  String get longLabel {
    switch (this) {
      case _DashboardRange.month:
        return 'past month';
      case _DashboardRange.threeMonths:
        return 'past 3 months';
      case _DashboardRange.sixMonths:
        return 'past 6 months';
      case _DashboardRange.year:
        return 'past year';
      case _DashboardRange.all:
        return 'all time';
    }
  }

  Duration? get duration {
    switch (this) {
      case _DashboardRange.month:
        return const Duration(days: 30);
      case _DashboardRange.threeMonths:
        return const Duration(days: 91);
      case _DashboardRange.sixMonths:
        return const Duration(days: 182);
      case _DashboardRange.year:
        return const Duration(days: 365);
      case _DashboardRange.all:
        return null;
    }
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab({required this.controller});

  final AppController controller;

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  _DashboardRange _range = _DashboardRange.all;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canesById = {for (final c in controller.caneSamples) c.id: c};
    final allReeds = controller.reedEvaluations;

    final duration = _range.duration;
    final cutoff = duration == null ? null : DateTime.now().subtract(duration);
    final reeds = cutoff == null
        ? allReeds
        : allReeds.where((r) => r.createdAt.isAfter(cutoff)).toList();

    final linkedCanes = reeds
        .map((r) => canesById[r.caneId])
        .whereType<CaneSample>()
        .toList();

    double avg(Iterable<num> values) {
      final list = values.where((v) => v.isFinite).toList();
      if (list.isEmpty) return 0;
      return list.fold<double>(0, (sum, v) => sum + v) / list.length;
    }

    final successful = reeds.where((r) => r.isSuccessful).length;
    final unsuccessful = reeds.length - successful;
    final avgStiffness = avg(linkedCanes.map((c) => c.relativeStiffness).where((v) => v > 0));
    final avgFrequency = avg(linkedCanes.map((c) => c.naturalFrequencyHz).where((v) => v > 0));
    final avgFlex = avg(linkedCanes.map((c) => c.flexibilityDeg).where((v) => v > 0));
    final avgMass = avg(linkedCanes.map((c) => c.massG).where((v) => v > 0));
    final avgReedScore = avg(reeds.map((r) => r.overallScore));
    final successRate = reeds.isEmpty ? 0.0 : (successful / reeds.length) * 100;
    final avgGrade = reeds.isEmpty ? '-' : ReedEvaluation.gradeForScore(avgReedScore);

    // Top-performer profile: average cane characteristics of the highest
    // scoring reeds in the selected window.
    final ranked = [...reeds]..sort((a, b) => b.overallScore.compareTo(a.overallScore));
    final topCount = math.max(1, (ranked.length * 0.25).ceil()).clamp(1, ranked.length);
    final topReeds = ranked.take(topCount).toList();
    final topCanes = topReeds
        .map((r) => canesById[r.caneId])
        .whereType<CaneSample>()
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _PhilosophyHeader(),
        const SizedBox(height: 14),
        _RangeSelector(
          range: _range,
          onChanged: (value) => setState(() => _range = value),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Showing data from the ${_range.longLabel}.',
            style: TextStyle(color: Colors.black.withValues(alpha: 0.6), fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        if (reeds.isEmpty)
          _EmptyDashboardCta(range: _range)
        else ...[
          _CountRow(
            evaluations: reeds.length,
            successful: successful,
            unsuccessful: unsuccessful,
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Averages (${_range.longLabel})',
            child: _StatGrid(
              tiles: [
                _StatTileData('Avg stiffness', avgStiffness.toStringAsFixed(2), 'g/deg'),
                _StatTileData('Avg frequency', avgFrequency.toStringAsFixed(0), 'Hz'),
                _StatTileData('Avg flexibility', avgFlex.toStringAsFixed(1), 'deg'),
                _StatTileData('Avg mass', avgMass.toStringAsFixed(2), 'g'),
                _StatTileData('Avg reed score', avgReedScore.toStringAsFixed(2), '/10'),
                _StatTileData('Avg reed grade', avgGrade, ''),
                _StatTileData('Success rate', successRate.toStringAsFixed(0), '%'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _TopPerformerCard(
            range: _range,
            topReeds: topReeds,
            topCanes: topCanes,
          ),
        ],
      ],
    );
  }
}

class _EmptyDashboardCta extends StatelessWidget {
  const _EmptyDashboardCta({required this.range});

  final _DashboardRange range;

  @override
  Widget build(BuildContext context) {
    final isAll = range == _DashboardRange.all;
    final headline = isAll
        ? 'No data yet.'
        : 'No data from the ${range.longLabel}.';
    final body = isAll
        ? 'Start tracking your cane and reed work to unlock averages, trends, and the predicted top performer profile.'
        : 'Try a wider range above, or log a cane and a reed to populate this window.';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFE0E6E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined,
                  color: Color(0xFF16697A), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F3640),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: Colors.black.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AddCanePage(),
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Log a cane'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16697A),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AddReedEvaluationPage(),
                  ),
                ),
                icon: const Icon(Icons.music_note_outlined, size: 18),
                label: const Text('Log a reed'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF16697A),
                  side: const BorderSide(color: Color(0xFF16697A)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhilosophyHeader extends StatelessWidget {
  const _PhilosophyHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF16697A), Color(0xFF489FB5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ReedLab',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Predictable cane, not perfect cane.',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'A measurement journal for bassoon reed makers. Log every cane and reed, '
            'then let the app surface the physical fingerprint of the ones that play best for you.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Developed using the research and craft of professional bassoonist '
              'Are Bøen Lauritzen, who has made his own reeds throughout a long '
              'career as a working bassoon player.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.range, required this.onChanged});

  final _DashboardRange range;
  final ValueChanged<_DashboardRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_DashboardRange>(
      segments: _DashboardRange.values
          .map((r) => ButtonSegment<_DashboardRange>(value: r, label: Text(r.label)))
          .toList(),
      selected: {range},
      onSelectionChanged: (set) => onChanged(set.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.evaluations,
    required this.successful,
    required this.unsuccessful,
  });

  final int evaluations;
  final int successful;
  final int unsuccessful;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CountCard(
            label: 'Reed evaluations',
            value: '$evaluations',
            color: const Color(0xFF16697A),
            icon: Icons.assignment_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountCard(
            label: 'Successful',
            value: '$successful',
            color: const Color(0xFF2E7D32),
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountCard(
            label: 'Unsuccessful',
            value: '$unsuccessful',
            color: const Color(0xFFC0392B),
            icon: Icons.cancel_outlined,
          ),
        ),
      ],
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.black.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTileData {
  const _StatTileData(this.label, this.value, this.unit);
  final String label;
  final String value;
  final String unit;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<_StatTileData> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final columns = constraints.maxWidth >= 420 ? 3 : 2;
        final tileWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles
              .map((t) => SizedBox(width: tileWidth, child: _StatTile(data: t)))
              .toList(),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.data});

  final _StatTileData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF16697A).withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.label,
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.black.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  data.value,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (data.unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  data.unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TopPerformerCard extends StatelessWidget {
  const _TopPerformerCard({
    required this.range,
    required this.topReeds,
    required this.topCanes,
  });

  final _DashboardRange range;
  final List<ReedEvaluation> topReeds;
  final List<CaneSample> topCanes;

  @override
  Widget build(BuildContext context) {
    double avg(Iterable<num> values) {
      final list = values.where((v) => v.isFinite).toList();
      if (list.isEmpty) return 0;
      return list.fold<double>(0, (sum, v) => sum + v) / list.length;
    }

    final hasData = topReeds.isNotEmpty && topCanes.isNotEmpty;
    final avgScore = avg(topReeds.map((r) => r.overallScore));
    final stiffness = avg(topCanes.map((c) => c.relativeStiffness).where((v) => v > 0));
    final frequency = avg(topCanes.map((c) => c.naturalFrequencyHz).where((v) => v > 0));
    final flex = avg(topCanes.map((c) => c.flexibilityDeg).where((v) => v > 0));
    final mass = avg(topCanes.map((c) => c.massG).where((v) => v > 0));

    return _SectionCard(
      title: 'Your high-score profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rather than averaging every reed, this section looks only at your top-scoring '
            'reeds in the ${range.longLabel} and reports the cane characteristics they had in common. '
            'Use these numbers as a personal target the next time you select cane.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.black.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Text(
              'Log a few reeds (with linked cane measurements) to unlock your personal profile.',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.7)),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Top ${topReeds.length} reed${topReeds.length == 1 ? '' : 's'} · '
                'avg score ${avgScore.toStringAsFixed(2)}/10 '
                '(${ReedEvaluation.gradeForScore(avgScore)})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B5E20),
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _StatGrid(
              tiles: [
                _StatTileData('Target stiffness', stiffness.toStringAsFixed(2), 'g/deg'),
                _StatTileData('Target frequency', frequency.toStringAsFixed(0), 'Hz'),
                _StatTileData('Target flexibility', flex.toStringAsFixed(1), 'deg'),
                _StatTileData('Target mass', mass.toStringAsFixed(2), 'g'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BehaviorTab extends StatefulWidget {
  const _BehaviorTab({required this.controller});

  final AppController controller;

  @override
  State<_BehaviorTab> createState() => _BehaviorTabState();
}

class _BehaviorTabState extends State<_BehaviorTab> {
  double _graphZoom = 1;
  Offset _graphPan = Offset.zero;
  double _zoomAtScaleStart = 1;
  Offset _focusDataPointAtScaleStart = Offset.zero;
  Size _graphCanvasSize = const Size(0, 0);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canes = controller.caneSamples;

    if (canes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: const [
          _SectionCard(
            title: 'Behavioral Intelligence',
            child: Text('Add cane and reed data first. This view becomes active when frequency/flex history exists.'),
          ),
        ],
      );
    }

    final entries = _buildBehaviorEntries(controller);
    final successful = entries.where((entry) => entry.success).toList();
    final failed = entries.where((entry) => !entry.success).toList();

    final favored = _FavoredProfile.compute(successful);
    final model = _ZoneModel.fromSamples(successful.map((entry) => entry.cane).toList());

    final graphDataPoints = [
      ...successful.map((entry) => entry.point),
      ...failed.map((entry) => entry.point),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionCard(
          title: 'Behavioral Cane Mapping',
          child: Text(
            'Every reed you have logged, plotted by resonance (X) and flexibility (Y). Green = successful, red = unsuccessful. Tap any point to open and edit that reed.',
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'Success graph',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = Size(constraints.maxWidth, 380);
                  _graphCanvasSize = canvasSize;
                  final projection = _BehaviorGraphProjection.fromPoints(
                    size: canvasSize,
                    points: graphDataPoints,
                    zoom: _graphZoom,
                    pan: _graphPan,
                  );

                  final plottedEntries = [
                    ...failed.map(
                      (entry) => _PlottedBehaviorEntry(
                        entry: entry,
                        position: projection.project(entry.point),
                      ),
                    ),
                    ...successful.map(
                      (entry) => _PlottedBehaviorEntry(
                        entry: entry,
                        position: projection.project(entry.point),
                      ),
                    ),
                  ];
                  final clusters = _clusterPlottedEntries(plottedEntries);

                  return SizedBox(
                    height: 380,
                    width: double.infinity,
                    child: GestureDetector(
                      onScaleStart: (details) => _onGraphScaleStart(details, projection),
                      onScaleUpdate: (details) => _onGraphScaleUpdate(details, projection),
                      onDoubleTap: _resetGraphView,
                      onTapUp: (details) => _onGraphTap(details.localPosition, clusters),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _BehaviorMapPainter(
                                projection: projection,
                                clusters: clusters,
                                livePoint: null,
                                zoneModel: model,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Column(
                              children: [
                                IconButton.filledTonal(
                                  tooltip: 'Zoom in',
                                  onPressed: () => _stepZoom(1.2),
                                  icon: const Icon(Icons.add),
                                ),
                                const SizedBox(height: 6),
                                IconButton.filledTonal(
                                  tooltip: 'Zoom out',
                                  onPressed: () => _stepZoom(1 / 1.2),
                                  icon: const Icon(Icons.remove),
                                ),
                                const SizedBox(height: 6),
                                IconButton.filledTonal(
                                  tooltip: 'Reset view',
                                  onPressed: _resetGraphView,
                                  icon: const Icon(Icons.center_focus_strong),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: tap single points or clustered bubbles to inspect and edit each instance.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _FavoredCompromiseCard(
          profile: favored,
          successCount: successful.length,
        ),
        const SizedBox(height: 10),
        _MusicalResonanceWindowCard(
          profile: favored,
          successful: successful,
        ),
        const SizedBox(height: 10),
        _DynamicZonesCard(
          profile: favored,
          zoneModel: model,
          totalSuccess: successful.length,
        ),
      ],
    );
  }

  void _onGraphScaleStart(
    ScaleStartDetails details,
    _BehaviorGraphProjection projection,
  ) {
    _zoomAtScaleStart = _graphZoom;
    _focusDataPointAtScaleStart = projection.inverse(details.localFocalPoint);
  }

  void _onGraphScaleUpdate(
    ScaleUpdateDetails details,
    _BehaviorGraphProjection projection,
  ) {
    final nextZoom = (_zoomAtScaleStart * details.scale).clamp(0.8, 4.0);
    final plotCenter = projection.plotRect.center;
    final focus = details.localFocalPoint;
    final centerToFocusData = _focusDataPointAtScaleStart - plotCenter;

    var nextPan = Offset(
      focus.dx - (centerToFocusData.dx * nextZoom + plotCenter.dx),
      focus.dy - (centerToFocusData.dy * nextZoom + plotCenter.dy),
    );
    nextPan = _clampGraphPan(nextPan, projection.plotRect, nextZoom);

    setState(() {
      _graphZoom = nextZoom;
      _graphPan = nextPan;
    });
  }

  void _onGraphTap(Offset localPosition, List<_BehaviorCluster> clusters) {
    if (clusters.isEmpty) {
      return;
    }

    _BehaviorCluster? nearest;
    var nearestDistance = double.infinity;
    final tapRadius = (14 / _graphZoom).clamp(8, 18).toDouble();

    for (final cluster in clusters) {
      final distance = (cluster.center - localPosition).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = cluster;
      }
    }

    if (nearest == null || nearestDistance > tapRadius) {
      return;
    }
    if (nearest.items.length == 1) {
      _showGraphEntryPreview(nearest.items.first.entry);
      return;
    }
    _showClusterPicker(nearest);
  }

  List<_BehaviorCluster> _clusterPlottedEntries(List<_PlottedBehaviorEntry> plottedEntries) {
    if (plottedEntries.isEmpty) {
      return const [];
    }

    final mergeRadius = (22 / _graphZoom).clamp(10, 24).toDouble();
    final clusters = <_BehaviorCluster>[];

    for (final plotted in plottedEntries) {
      var merged = false;
      for (int i = 0; i < clusters.length; i++) {
        final cluster = clusters[i];
        if ((cluster.center - plotted.position).distance > mergeRadius) {
          continue;
        }

        final mergedItems = [...cluster.items, plotted];
        final x = mergedItems.map((item) => item.position.dx).reduce((a, b) => a + b) /
            mergedItems.length;
        final y = mergedItems.map((item) => item.position.dy).reduce((a, b) => a + b) /
            mergedItems.length;
        clusters[i] = _BehaviorCluster(items: mergedItems, center: Offset(x, y));
        merged = true;
        break;
      }

      if (!merged) {
        clusters.add(
          _BehaviorCluster(items: [plotted], center: plotted.position),
        );
      }
    }

    return clusters;
  }

  void _stepZoom(double factor) {
    final nextZoom = (_graphZoom * factor).clamp(0.8, 4.0);
    final projection = _BehaviorGraphProjection.fromPoints(
      size: _graphCanvasSize,
      points: const [],
      zoom: _graphZoom,
      pan: _graphPan,
    );
    setState(() {
      _graphZoom = nextZoom;
      _graphPan = _clampGraphPan(_graphPan, projection.plotRect, nextZoom);
    });
  }

  void _resetGraphView() {
    setState(() {
      _graphZoom = 1;
      _graphPan = Offset.zero;
    });
  }

  Offset _clampGraphPan(Offset pan, Rect plotRect, double zoom) {
    final xSlack = ((zoom - 1) * plotRect.width * 0.5) + 40;
    final ySlack = ((zoom - 1) * plotRect.height * 0.5) + 36;
    return Offset(
      pan.dx.clamp(-xSlack, xSlack),
      pan.dy.clamp(-ySlack, ySlack),
    );
  }

  Future<void> _showGraphEntryPreview(_BehaviorEntry entry) async {
    final allPhotos = [...entry.cane.photoPaths, ...entry.evaluation.photoPaths];
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${entry.cane.sampleName} - ${entry.cane.purchaseDateLabel}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: entry.success ? const Color(0xFF2E7D32) : const Color(0xFFD64545),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        entry.success ? 'Successful' : 'Unsuccessful',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Grade ${ReedEvaluation.gradeForScore(entry.score)} | ${entry.score.toStringAsFixed(1)}/10'),
                Text('Tone/Frequency: ${entry.cane.naturalFrequencyHz.toStringAsFixed(1)} Hz'),
                Text('Flexibility: ${entry.cane.flexibilityDeg.toStringAsFixed(2)} deg'),
                Text('ARI: ${entry.cane.ari?.toStringAsFixed(1) ?? 'n/a'}'),
                Text('Buoyancy: ${entry.cane.buoyancyPercent?.toStringAsFixed(1) ?? 'n/a'}%'),
                const SizedBox(height: 10),
                if (allPhotos.isNotEmpty)
                  _ThumbnailRow(paths: allPhotos)
                else
                  const Text('No photos attached for this instance.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AddReedEvaluationPage(
                          initialEvaluation: entry.evaluation,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Open and edit reed'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showClusterPicker(_BehaviorCluster cluster) async {
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              Text(
                '${cluster.items.length} instances in this area',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 8),
              ...cluster.items.map((item) {
                final entry = item.entry;
                final photos = [...entry.cane.photoPaths, ...entry.evaluation.photoPaths];
                final subtitle =
                    '${entry.cane.purchaseDateLabel} | ${ReedEvaluation.gradeForScore(entry.score)} | ${entry.cane.naturalFrequencyHz.toStringAsFixed(1)} Hz | Flex ${entry.cane.flexibilityDeg.toStringAsFixed(1)}';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: photos.isEmpty
                        ? const CircleAvatar(child: Icon(Icons.music_note))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(photos.first),
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const CircleAvatar(
                                child: Icon(Icons.broken_image),
                              ),
                            ),
                          ),
                    title: Text(entry.cane.sampleName),
                    subtitle: Text(subtitle),
                    trailing: Icon(
                      entry.success ? Icons.check_circle : Icons.cancel,
                      color: entry.success ? const Color(0xFF2E7D32) : const Color(0xFFD64545),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showGraphEntryPreview(entry);
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _BehaviorPoint {
  const _BehaviorPoint({required this.frequencyHz, required this.flexibilityDeg});

  final double frequencyHz;
  final double flexibilityDeg;
}

class _BehaviorEntry {
  const _BehaviorEntry({
    required this.cane,
    required this.evaluation,
    required this.success,
    required this.score,
  });

  final CaneSample cane;
  final ReedEvaluation evaluation;
  final bool success;
  final double score;

  _BehaviorPoint get point => _BehaviorPoint(
    frequencyHz: cane.naturalFrequencyHz,
    flexibilityDeg: cane.flexibilityDeg,
  );
}

class _ZoneModel {
  const _ZoneModel({
    required this.centerFrequency,
    required this.centerFlexibility,
    required this.bandFrequency,
    required this.bandFlexibility,
  });

  final double centerFrequency;
  final double centerFlexibility;
  final double bandFrequency;
  final double bandFlexibility;

  factory _ZoneModel.fromSamples(List<CaneSample> samples) {
    if (samples.isEmpty) {
      return const _ZoneModel(
        centerFrequency: 1200,
        centerFlexibility: 20,
        bandFrequency: 80,
        bandFlexibility: 4,
      );
    }

    double mean(Iterable<double> values) {
      final list = values.toList();
      return list.reduce((a, b) => a + b) / list.length;
    }

    double std(Iterable<double> values, double avg) {
      final list = values.toList();
      if (list.length < 2) {
        return 1;
      }
      final variance = list
              .map((value) => (value - avg) * (value - avg))
              .reduce((a, b) => a + b) /
          (list.length - 1);
      return math.sqrt(variance);
    }

    final freqAvg = mean(samples.map((sample) => sample.naturalFrequencyHz));
    final flexAvg = mean(samples.map((sample) => sample.flexibilityDeg));
    final freqStd = std(samples.map((sample) => sample.naturalFrequencyHz), freqAvg);
    final flexStd = std(samples.map((sample) => sample.flexibilityDeg), flexAvg);

    return _ZoneModel(
      centerFrequency: freqAvg,
      centerFlexibility: flexAvg,
      bandFrequency: math.max(30, freqStd),
      bandFlexibility: math.max(1.2, flexStd),
    );
  }
}

class _PlottedBehaviorEntry {
  const _PlottedBehaviorEntry({required this.entry, required this.position});

  final _BehaviorEntry entry;
  final Offset position;
}

class _BehaviorCluster {
  const _BehaviorCluster({required this.items, required this.center});

  final List<_PlottedBehaviorEntry> items;
  final Offset center;
}

class _BehaviorGraphProjection {
  const _BehaviorGraphProjection({
    required this.plotRect,
    required this.minFrequency,
    required this.maxFrequency,
    required this.minFlexibility,
    required this.maxFlexibility,
    required this.zoom,
    required this.pan,
  });

  factory _BehaviorGraphProjection.fromPoints({
    required Size size,
    required List<_BehaviorPoint> points,
    required double zoom,
    required Offset pan,
  }) {
    final minFrequency = points.isEmpty
      ? 1000.0
      : points.map((item) => item.frequencyHz).reduce(math.min).toDouble() - 40;
    final maxFrequency = points.isEmpty
      ? 1400.0
      : points.map((item) => item.frequencyHz).reduce(math.max).toDouble() + 40;
    final minFlexibility = points.isEmpty
      ? 10.0
      : points.map((item) => item.flexibilityDeg).reduce(math.min).toDouble() - 2;
    final maxFlexibility = points.isEmpty
      ? 30.0
      : points.map((item) => item.flexibilityDeg).reduce(math.max).toDouble() + 2;

    return _BehaviorGraphProjection(
      plotRect: Rect.fromLTWH(54, 18, size.width - 74, size.height - 54),
      minFrequency: minFrequency,
      maxFrequency: maxFrequency,
      minFlexibility: minFlexibility,
      maxFlexibility: maxFlexibility,
      zoom: zoom,
      pan: pan,
    );
  }

  final Rect plotRect;
  final double minFrequency;
  final double maxFrequency;
  final double minFlexibility;
  final double maxFlexibility;
  final double zoom;
  final Offset pan;

  Offset project(_BehaviorPoint point) {
    final freqRange = (maxFrequency - minFrequency).abs() < 0.001
        ? 1.0
        : (maxFrequency - minFrequency);
    final flexRange = (maxFlexibility - minFlexibility).abs() < 0.001
        ? 1.0
        : (maxFlexibility - minFlexibility);
    final xNorm = (point.frequencyHz - minFrequency) / freqRange;
    final yNorm = (point.flexibilityDeg - minFlexibility) / flexRange;

    final base = Offset(
      xNorm.clamp(0, 1) * plotRect.width + plotRect.left,
      (1 - yNorm.clamp(0, 1)) * plotRect.height + plotRect.top,
    );
    final center = plotRect.center;
    return Offset(
      (base.dx - center.dx) * zoom + center.dx + pan.dx,
      (base.dy - center.dy) * zoom + center.dy + pan.dy,
    );
  }

  Offset inverse(Offset viewPoint) {
    final center = plotRect.center;
    final unzoomed = Offset(
      (viewPoint.dx - pan.dx - center.dx) / zoom + center.dx,
      (viewPoint.dy - pan.dy - center.dy) / zoom + center.dy,
    );
    return unzoomed;
  }

  double get xScale => plotRect.width / ((maxFrequency - minFrequency).abs() < 0.001 ? 1 : (maxFrequency - minFrequency));

  double get yScale => plotRect.height / ((maxFlexibility - minFlexibility).abs() < 0.001 ? 1 : (maxFlexibility - minFlexibility));
}

class _BehaviorMapPainter extends CustomPainter {
  const _BehaviorMapPainter({
    required this.projection,
    required this.clusters,
    required this.livePoint,
    required this.zoneModel,
  });

  final _BehaviorGraphProjection projection;
  final List<_BehaviorCluster> clusters;
  final _BehaviorPoint? livePoint;
  final _ZoneModel zoneModel;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(0, 0, size.width, size.height);
    final background = Paint()..color = const Color(0xFFF4F7F6);
    canvas.drawRRect(RRect.fromRectAndRadius(frame, const Radius.circular(12)), background);

    final plotRect = projection.plotRect;
    final project = projection.project;

    final zoneCenter = project(
      _BehaviorPoint(
        frequencyHz: zoneModel.centerFrequency,
        flexibilityDeg: zoneModel.centerFlexibility,
      ),
    );
    final xScale = projection.xScale * projection.zoom;
    final yScale = projection.yScale * projection.zoom;

    final preferred = Rect.fromCenter(
      center: zoneCenter,
      width: (zoneModel.bandFrequency * 2 * xScale).clamp(30, size.width),
      height: (zoneModel.bandFlexibility * 2 * yScale).clamp(20, size.height),
    );
    final transition = Rect.fromCenter(
      center: zoneCenter,
      width: preferred.width * 1.6,
      height: preferred.height * 1.6,
    );
    final problematic = Rect.fromCenter(
      center: zoneCenter,
      width: preferred.width * 2.3,
      height: preferred.height * 2.3,
    );

    canvas.drawOval(problematic, Paint()..color = const Color(0x30D9534F));
    canvas.drawOval(transition, Paint()..color = const Color(0x35EBCB57));
    canvas.drawOval(preferred, Paint()..color = const Color(0x4066BB6A));

    final gridPaint = Paint()
      ..color = const Color(0x55677777)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final x = plotRect.left + (plotRect.width / 4) * i;
      final y = plotRect.top + (plotRect.height / 4) * i;
      canvas.drawLine(Offset(x, plotRect.top), Offset(x, plotRect.bottom), gridPaint);
      canvas.drawLine(Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);
    }

    final axisPaint = Paint()
      ..color = const Color(0xAA37474F)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(plotRect.left, plotRect.bottom),
      Offset(plotRect.right, plotRect.bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(plotRect.left, plotRect.bottom),
      Offset(plotRect.left, plotRect.top),
      axisPaint,
    );

    void drawLabel(String text, Offset offset, {bool center = false, double rotation = 0}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Color(0xFF37474F),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      if (rotation != 0) {
        canvas.rotate(rotation);
      }
      tp.paint(
        canvas,
        center ? Offset(-tp.width / 2, -tp.height / 2) : Offset.zero,
      );
      canvas.restore();
    }

    drawLabel(
      'Cane Tone: higher->lower',
      Offset(plotRect.center.dx, plotRect.bottom + 10),
      center: true,
    );
    drawLabel(
      'Flexibility: less->more',
      Offset(plotRect.left - 42, plotRect.center.dy),
      center: true,
      rotation: -math.pi / 2,
    );

    for (final cluster in clusters) {
      final successCount = cluster.items.where((item) => item.entry.success).length;
      final ratio = cluster.items.isEmpty ? 0.5 : successCount / cluster.items.length;
      final color = Color.lerp(const Color(0xFFD64545), const Color(0xFF2E7D32), ratio)!;
      final hasGoldStandard =
          cluster.items.any((item) => item.entry.evaluation.goldStandard);

      final radius = cluster.items.length == 1
          ? 4.0
          : (6 + math.sqrt(cluster.items.length) * 2).clamp(8, 16).toDouble();
      canvas.drawCircle(cluster.center, radius, Paint()..color = color);

      if (hasGoldStandard) {
        canvas.drawCircle(
          cluster.center,
          radius + 2,
          Paint()
            ..color = const Color(0xFFE0B22D)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      if (cluster.items.length > 1) {
        canvas.drawCircle(
          cluster.center,
          radius,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );

        final tp = TextPainter(
          text: TextSpan(
            text: '${cluster.items.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(cluster.center.dx - tp.width / 2, cluster.center.dy - tp.height / 2),
        );
      }
    }

    if (livePoint != null) {
      canvas.drawCircle(project(livePoint!), 6, Paint()..color = const Color(0xFF0D47A1));
    }
  }

  @override
  bool shouldRepaint(covariant _BehaviorMapPainter oldDelegate) {
    return oldDelegate.projection != projection ||
        oldDelegate.clusters != clusters ||
        oldDelegate.livePoint != livePoint ||
        oldDelegate.zoneModel != zoneModel;
  }
}

class _FavoredProfile {
  const _FavoredProfile({
    required this.frequency,
    required this.flexibility,
    required this.stiffness,
    required this.mass,
    required this.ari,
    required this.buoyancy,
    required this.freqMin,
    required this.freqMax,
    required this.flexMin,
    required this.flexMax,
    required this.avgScore,
    required this.sampleSize,
  });

  final double frequency;
  final double flexibility;
  final double? stiffness;
  final double? mass;
  final double? ari;
  final double? buoyancy;
  final double freqMin;
  final double freqMax;
  final double flexMin;
  final double flexMax;
  final double avgScore;
  final int sampleSize;

  static _FavoredProfile? compute(List<_BehaviorEntry> successful) {
    if (successful.isEmpty) {
      return null;
    }
    final weights =
        successful.map((entry) => math.max(0.001, entry.score)).toList();
    final wSum = weights.reduce((a, b) => a + b);

    double weighted(double Function(_BehaviorEntry) selector) {
      double total = 0;
      for (var i = 0; i < successful.length; i++) {
        total += selector(successful[i]) * weights[i];
      }
      return total / wSum;
    }

    double? weightedNullable(double? Function(_BehaviorEntry) selector) {
      double total = 0;
      double weightTotal = 0;
      for (var i = 0; i < successful.length; i++) {
        final value = selector(successful[i]);
        if (value == null) continue;
        total += value * weights[i];
        weightTotal += weights[i];
      }
      if (weightTotal == 0) return null;
      return total / weightTotal;
    }

    final freqs = successful.map((e) => e.cane.naturalFrequencyHz).toList();
    final flexes = successful.map((e) => e.cane.flexibilityDeg).toList();

    return _FavoredProfile(
      frequency: weighted((e) => e.cane.naturalFrequencyHz),
      flexibility: weighted((e) => e.cane.flexibilityDeg),
      stiffness: weightedNullable(
        (e) => e.cane.relativeStiffness > 0 ? e.cane.relativeStiffness : null,
      ),
      mass: weightedNullable(
        (e) => e.cane.massG > 0 ? e.cane.massG : null,
      ),
      ari: weightedNullable((e) => e.cane.ari),
      buoyancy: weightedNullable((e) => e.cane.buoyancyPercent),
      freqMin: freqs.reduce(math.min),
      freqMax: freqs.reduce(math.max),
      flexMin: flexes.reduce(math.min),
      flexMax: flexes.reduce(math.max),
      avgScore: successful
              .map((e) => e.score)
              .reduce((a, b) => a + b) /
          successful.length,
      sampleSize: successful.length,
    );
  }
}

class _FavoredCompromiseCard extends StatelessWidget {
  const _FavoredCompromiseCard({
    required this.profile,
    required this.successCount,
  });

  final _FavoredProfile? profile;
  final int successCount;

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const _SectionCard(
        title: 'Favored compromise',
        child: Text(
          'No successful reeds yet. As soon as you log a reed with a score of 8 or higher, the score-weighted target profile will appear here.',
        ),
      );
    }
    final p = profile!;
    final rows = <_TargetRowData>[
      _TargetRowData('Natural frequency', '${p.frequency.toStringAsFixed(0)} Hz'),
      _TargetRowData('Flexibility', '${p.flexibility.toStringAsFixed(1)} deg'),
      if (p.stiffness != null)
        _TargetRowData('Stiffness', '${p.stiffness!.toStringAsFixed(2)} g/deg'),
      if (p.mass != null)
        _TargetRowData('Mass', '${p.mass!.toStringAsFixed(2)} g'),
      if (p.ari != null)
        _TargetRowData('ARI', p.ari!.toStringAsFixed(1)),
      if (p.buoyancy != null)
        _TargetRowData('Buoyancy', '${p.buoyancy!.toStringAsFixed(1)}%'),
    ];

    return _SectionCard(
      title: 'Favored compromise',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Score-weighted target from your $successCount successful reed${successCount == 1 ? '' : 's'} (avg ${p.avgScore.toStringAsFixed(1)}/10).',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 12),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    row.value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16697A),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aim for these values when selecting and shaping new cane to maximize your chance of a successful reed.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.black.withValues(alpha: 0.6),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicalResonanceWindowCard extends StatelessWidget {
  const _MusicalResonanceWindowCard({
    required this.profile,
    required this.successful,
  });

  final _FavoredProfile? profile;
  final List<_BehaviorEntry> successful;

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const _SectionCard(
        title: 'Musical resonance window',
        child: Text(
          'Log a few successful reeds and this section will translate your sweet-spot frequency into pitch and a target Hz range.',
        ),
      );
    }
    final p = profile!;
    final pitch = _pitchFromFrequency(p.frequency);
    final centsLabel = pitch.cents == 0
        ? 'in tune'
        : '${pitch.cents > 0 ? '+' : ''}${pitch.cents} cents';

    return _SectionCard(
      title: 'Musical resonance window',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Centered on your highest-scoring reeds:',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${p.frequency.toStringAsFixed(0)} Hz',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F3640),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Pitch ${pitch.label} ($centsLabel)',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF16697A),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE9F3F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.unfold_more,
                    size: 18, color: Color(0xFF16697A)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Observed success range: '
                    '${p.freqMin.toStringAsFixed(0)} - ${p.freqMax.toStringAsFixed(0)} Hz',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F3640),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap new cane in the Cane tab. If its natural frequency lands inside this window, it is likely to produce a strong reed.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.black.withValues(alpha: 0.6),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DynamicZonesCard extends StatelessWidget {
  const _DynamicZonesCard({
    required this.profile,
    required this.zoneModel,
    required this.totalSuccess,
  });

  final _FavoredProfile? profile;
  final _ZoneModel zoneModel;
  final int totalSuccess;

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const _SectionCard(
        title: 'Dynamic behavior zones',
        child: Text(
          'Once you have a few successful reeds, this section shows the tolerance band around your favored compromise.',
        ),
      );
    }
    final p = profile!;
    final freqLo = (p.frequency - zoneModel.bandFrequency).round();
    final freqHi = (p.frequency + zoneModel.bandFrequency).round();
    final flexLo = (p.flexibility - zoneModel.bandFlexibility).toStringAsFixed(1);
    final flexHi = (p.flexibility + zoneModel.bandFlexibility).toStringAsFixed(1);

    return _SectionCard(
      title: 'Dynamic behavior zones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stay inside these corridors — derived from $totalSuccess successful reed${totalSuccess == 1 ? '' : 's'} — to repeat what has worked.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 12),
          _ZoneRow(
            label: 'Frequency',
            target: '${p.frequency.toStringAsFixed(0)} Hz',
            corridor: '$freqLo - $freqHi Hz',
          ),
          const SizedBox(height: 8),
          _ZoneRow(
            label: 'Flexibility',
            target: '${p.flexibility.toStringAsFixed(1)} deg',
            corridor: '$flexLo - $flexHi deg',
          ),
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.label,
    required this.target,
    required this.corridor,
  });

  final String label;
  final String target;
  final String corridor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F7F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBE0D4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 18, color: Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1B5E20),
                    )),
                const SizedBox(height: 2),
                Text(
                  'Aim for $target  •  stay within $corridor',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF0F3640),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetRowData {
  const _TargetRowData(this.label, this.value);
  final String label;
  final String value;
}

class _PitchValue {
  const _PitchValue({required this.label, required this.cents});

  final String label;
  final int cents;
}

class _MetricStatus {
  const _MetricStatus({required this.label, required this.color});

  final String label;
  final Color color;
}

List<_BehaviorEntry> _buildBehaviorEntries(AppController controller) {
  final caneById = {for (final sample in controller.caneSamples) sample.id: sample};
  return controller.reedEvaluations
      .map((evaluation) {
        final cane = caneById[evaluation.caneId];
        if (cane == null) {
          return null;
        }
        return _BehaviorEntry(
          cane: cane,
          evaluation: evaluation,
          success: evaluation.isSuccessful,
          score: evaluation.overallScore,
        );
      })
      .whereType<_BehaviorEntry>()
      .toList();
}

_PitchValue _pitchFromFrequency(double frequency) {
  final midi = 69 + 12 * (math.log(frequency / 440) / math.ln2);
  final nearestMidi = midi.round();
  final cents = ((midi - nearestMidi) * 100).round();
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final octave = (nearestMidi ~/ 12) - 1;
  final note = names[(nearestMidi % 12 + 12) % 12];
  return _PitchValue(label: '$note$octave', cents: cents);
}

_MetricStatus _ariStatus(double? ari) {
  if (ari == null) {
    return const _MetricStatus(label: 'No ARI (missing flexibility)', color: Color(0xFF6D6D6D));
  }
  if (ari <= -6) {
    return const _MetricStatus(label: 'A+ Excellent', color: Color(0xFF0B4D0E));
  }
  if (ari < 0) {
    return const _MetricStatus(label: 'A Very Good', color: Color(0xFF1B5E20));
  }
  if (ari <= 4) {
    return const _MetricStatus(label: 'B Acceptable', color: Color(0xFFF9A825));
  }
  if (ari < 10) {
    return const _MetricStatus(label: 'C Weak Match', color: Color(0xFFE67E22));
  }
  return const _MetricStatus(label: 'D Poor (+10 or more)', color: Color(0xFFC62828));
}

_MetricStatus _buoyancyStatus(double? percent) {
  if (percent == null) {
    return const _MetricStatus(label: 'No buoyancy data', color: Color(0xFF6D6D6D));
  }
  if (percent >= 81 && percent <= 85) {
    return const _MetricStatus(label: 'Excellent', color: Color(0xFF1B5E20));
  }
  if (percent >= 78 && percent <= 87) {
    return const _MetricStatus(label: 'Good', color: Color(0xFF2E7D32));
  }
  if ((percent >= 74 && percent < 78) || (percent > 87 && percent <= 90)) {
    return const _MetricStatus(label: 'Borderline', color: Color(0xFFF9A825));
  }
  return const _MetricStatus(label: 'Weak Candidate', color: Color(0xFFC62828));
}

String _combinedPredictionMessage(double ari, double buoyancyPercent) {
  final ariGood = ari < 0;
  final ariPoor = ari >= 10;
  final buoyancyGood = buoyancyPercent >= 81 && buoyancyPercent <= 85;

  if (ariPoor && !buoyancyGood) {
    return 'Weak candidate: ARI is in poor range (+10 or more) and density proxy is off target.';
  }
  if (ariPoor && buoyancyGood) {
    return 'Density is good, but ARI is in poor range (+10 or more). Proceed with caution.';
  }
  if (ariGood && buoyancyGood) {
    return 'Excellent candidate: ARI balance and density profile are both in target range.';
  }
  if (ariGood && !buoyancyGood) {
    return 'Excellent ARI balance, but density mismatch. Proceed with caution.';
  }
  if (!ariGood && buoyancyGood) {
    return 'Density is strong, but flexibility/resonance balance is weaker than target.';
  }
  return 'Both ARI and density are outside preferred range for this profile.';
}

class _CaneTab extends StatefulWidget {
  const _CaneTab({required this.controller});

  final AppController controller;

  @override
  State<_CaneTab> createState() => _CaneTabState();
}

class _CaneTabState extends State<_CaneTab> {
  DateTime? _fromDate;
  DateTime? _toDate;
  String _query = '';
  String _reviewFilter = 'all';
  String _sortOrder = 'newest';

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final reviewedCaneIds = controller.reedEvaluations.map((item) => item.caneId).toSet();

    final filteredCanes = controller.caneSamples.where((sample) {
      if (_fromDate != null && sample.purchaseDate.isBefore(_fromDate!)) {
        return false;
      }
      if (_toDate != null && sample.purchaseDate.isAfter(_toDate!)) {
        return false;
      }

      final reviewed = reviewedCaneIds.contains(sample.id);
      if (_reviewFilter == 'reviewed' && !reviewed) {
        return false;
      }
      if (_reviewFilter == 'pending' && reviewed) {
        return false;
      }

      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        final haystack = '${sample.sampleName} ${sample.source}'.toLowerCase();
        if (!haystack.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    filteredCanes.sort((a, b) {
      switch (_sortOrder) {
        case 'oldest':
          return a.purchaseDate.compareTo(b.purchaseDate);
        case 'name_az':
          return a.sampleName.toLowerCase().compareTo(b.sampleName.toLowerCase());
        case 'name_za':
          return b.sampleName.toLowerCase().compareTo(a.sampleName.toLowerCase());
        case 'newest':
        default:
          return b.purchaseDate.compareTo(a.purchaseDate);
      }
    });

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          children: [
            const Text(
              'Cane Measurement Log',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
            const SizedBox(height: 8),
            _SectionCard(
              title: 'Filters',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: true),
                          icon: const Icon(Icons.date_range),
                          label: Text(_fromDate == null
                              ? 'From date'
                              : 'From ${_formatDate(_fromDate!)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: false),
                          icon: const Icon(Icons.event),
                          label: Text(_toDate == null
                              ? 'To date'
                              : 'To ${_formatDate(_toDate!)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _reviewFilter,
                    decoration: const InputDecoration(labelText: 'Review status'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'reviewed', child: Text('Reviewed')),
                      DropdownMenuItem(value: 'pending', child: Text('Pending review')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _reviewFilter = value ?? 'all';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _sortOrder,
                    decoration: const InputDecoration(labelText: 'Sort order'),
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest first')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
                      DropdownMenuItem(value: 'name_az', child: Text('Name A->Z')),
                      DropdownMenuItem(value: 'name_za', child: Text('Name Z->A')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _sortOrder = value ?? 'newest';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search sample/source',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                        _query = '';
                        _reviewFilter = 'all';
                        _sortOrder = 'newest';
                      });
                    },
                    child: const Text('Reset filters'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (filteredCanes.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No cane samples match the current filters.'),
                ),
              )
            else
              ...filteredCanes.map(
                (sample) => _CaneCard(
                  sample: sample,
                  isReviewed: reviewedCaneIds.contains(sample.id),
                  onEdit: () => _editCane(context, sample),
                  onDelete: () => _deleteCane(context, sample),
                ),
              ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const AddCanePage()),
              );
              if (context.mounted && created == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cane sample saved.')),
                );
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Cane'),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_fromDate ?? DateTime.now())
          : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _editCane(BuildContext context, CaneSample sample) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddCanePage(initialSample: sample)),
    );
    if (context.mounted && updated == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cane sample updated.')),
      );
    }
  }

  Future<void> _deleteCane(BuildContext context, CaneSample sample) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete cane sample?'),
          content: const Text(
            'This deletes the cane entry and all linked reed evaluations.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await context.read<AppController>().deleteCaneSample(sample.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cane sample deleted.')),
      );
    }
  }
}

class _ReedTab extends StatefulWidget {
  const _ReedTab({required this.controller});

  final AppController controller;

  @override
  State<_ReedTab> createState() => _ReedTabState();
}

class _ReedTabState extends State<_ReedTab> {
  DateTime? _fromDate;
  DateTime? _toDate;
  RangeValues _scoreRange = const RangeValues(1, 10);
  String _statusFilter = 'all';
  String _query = '';
  String _sortOrder = 'newest';

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final reviewedCaneIds = controller.reedEvaluations.map((item) => item.caneId).toSet();
    final pendingCanes = controller.caneSamples
        .where((sample) => !reviewedCaneIds.contains(sample.id))
        .toList()
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

    final filteredEvaluations = controller.reedEvaluations.where((evaluation) {
      final evaluationDate = evaluation.createdAt;
      if (_fromDate != null && evaluationDate.isBefore(_fromDate!)) {
        return false;
      }
      if (_toDate != null && evaluationDate.isAfter(_toDate!)) {
        return false;
      }
      final score = evaluation.overallScore;
      if (score < _scoreRange.start || score > _scoreRange.end) {
        return false;
      }
      if (_statusFilter == 'pending') {
        return false;
      }

      if (_query.trim().isNotEmpty) {
        final cane = controller.findCane(evaluation.caneId);
        final q = _query.trim().toLowerCase();
        final haystack = '${cane?.sampleName ?? ''} ${cane?.source ?? ''} ${evaluation.comment} ${evaluation.goldStandard ? 'gold standard' : ''}'.toLowerCase();
        if (!haystack.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();

    filteredEvaluations.sort((a, b) {
      switch (_sortOrder) {
        case 'oldest':
          return a.createdAt.compareTo(b.createdAt);
        case 'score_high':
          return b.overallScore.compareTo(a.overallScore);
        case 'score_low':
          return a.overallScore.compareTo(b.overallScore);
        case 'gold_first':
          final goldOrder = (b.goldStandard ? 1 : 0) - (a.goldStandard ? 1 : 0);
          if (goldOrder != 0) {
            return goldOrder;
          }
          return b.createdAt.compareTo(a.createdAt);
        case 'newest':
        default:
          return b.createdAt.compareTo(a.createdAt);
      }
    });

    final filteredPendingCanes = pendingCanes.where((cane) {
      if (_statusFilter == 'reviewed') {
        return false;
      }
      if (_fromDate != null && cane.purchaseDate.isBefore(_fromDate!)) {
        return false;
      }
      if (_toDate != null && cane.purchaseDate.isAfter(_toDate!)) {
        return false;
      }
      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        final haystack = '${cane.sampleName} ${cane.source}'.toLowerCase();
        if (!haystack.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          children: [
            const Text(
              'Reed Outcome Tracking',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
            const SizedBox(height: 8),
            _SectionCard(
              title: 'Filters',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: true),
                          icon: const Icon(Icons.date_range),
                          label: Text(_fromDate == null
                              ? 'From date'
                              : 'From ${_formatDate(_fromDate!)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: false),
                          icon: const Icon(Icons.event),
                          label: Text(_toDate == null
                              ? 'To date'
                              : 'To ${_formatDate(_toDate!)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'reviewed', child: Text('Reviewed only')),
                      DropdownMenuItem(value: 'pending', child: Text('Pending review only')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _statusFilter = value ?? 'all';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _sortOrder,
                    decoration: const InputDecoration(labelText: 'Sort order'),
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest first')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
                      DropdownMenuItem(value: 'score_high', child: Text('Score high->low')),
                      DropdownMenuItem(value: 'score_low', child: Text('Score low->high')),
                      DropdownMenuItem(value: 'gold_first', child: Text('Gold Standard first')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _sortOrder = value ?? 'newest';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search sample/source/comment',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 10),
                  Text('Score range: ${_scoreRange.start.toStringAsFixed(1)} - ${_scoreRange.end.toStringAsFixed(1)}'),
                  RangeSlider(
                    values: _scoreRange,
                    min: 1,
                    max: 10,
                    divisions: 18,
                    labels: RangeLabels(
                      _scoreRange.start.toStringAsFixed(1),
                      _scoreRange.end.toStringAsFixed(1),
                    ),
                    onChanged: _statusFilter == 'pending'
                        ? null
                        : (value) => setState(() => _scoreRange = value),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                        _scoreRange = const RangeValues(1, 10);
                        _statusFilter = 'all';
                        _query = '';
                        _sortOrder = 'newest';
                      });
                    },
                    child: const Text('Reset filters'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (filteredPendingCanes.isNotEmpty) ...[
              const Text(
                'Pending Reviews',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...filteredPendingCanes.map(
                (sample) => _PendingReedCard(
                  sample: sample,
                  onTap: () => _openPendingStats(context, sample),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (filteredEvaluations.isEmpty && filteredPendingCanes.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No reeds match the current filters.'),
                ),
              )
            else
              ...filteredEvaluations.map((evaluation) {
                final cane = controller.findCane(evaluation.caneId);
                return _ReedCard(
                  evaluation: evaluation,
                  cane: cane,
                  onTap: () => _openReedStats(context, evaluation, cane),
                  onEdit: () => _editReed(context, evaluation),
                  onDelete: () => _deleteReed(context, evaluation),
                );
              }),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: controller.caneSamples.isEmpty
                ? null
                : () async {
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const AddReedEvaluationPage()),
                    );
                    if (context.mounted && created == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Reed evaluation saved.')),
                      );
                    }
                  },
            icon: const Icon(Icons.add),
            label: const Text('Rate Reed'),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_fromDate ?? DateTime.now())
          : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _editReed(BuildContext context, ReedEvaluation evaluation) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddReedEvaluationPage(initialEvaluation: evaluation),
      ),
    );
    if (context.mounted && updated == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reed evaluation updated.')),
      );
    }
  }

  Future<void> _deleteReed(BuildContext context, ReedEvaluation evaluation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete reed evaluation?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await context.read<AppController>().deleteReedEvaluation(evaluation.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reed evaluation deleted.')),
      );
    }
  }

  Future<void> _openReedStats(
    BuildContext context,
    ReedEvaluation evaluation,
    CaneSample? cane,
  ) async {
    if (cane == null) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Linked cane data is missing for this reed.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddReedEvaluationPage(initialEvaluation: evaluation),
      ),
    );
  }

  Future<void> _openPendingStats(BuildContext context, CaneSample sample) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddReedEvaluationPage(initialCaneId: sample.id),
      ),
    );
    if (context.mounted && created == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reed evaluation saved.')),
      );
    }
  }
}

class AddCanePage extends StatefulWidget {
  const AddCanePage({super.key, this.initialSample});

  final CaneSample? initialSample;

  @override
  State<AddCanePage> createState() => _AddCanePageState();
}

class _AddCanePageState extends State<AddCanePage> {
  final _formKey = GlobalKey<FormState>();
  final _sampleNameController = TextEditingController();
  final _batchController = TextEditingController();
  final _sourceController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _thicknessController = TextEditingController();
  final _thicknessMiddleController = TextEditingController();
  final _thicknessBackController = TextEditingController();
  final _massController = TextEditingController();
  final _flexibilityController = TextEditingController();
  final _loadController = TextEditingController(text: '200');
  final _frequencyController = TextEditingController();
  final _submergedLengthController = TextEditingController();
  final _hardnessController = TextEditingController();
  final _notesController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  List<String> _photoPaths = [];
  List<double> _resonanceTakesHz = [];

  DateTime _purchaseDate = DateTime.now();
  String _innerGougeType = 'none';

  bool get _isEditing => widget.initialSample != null;

  bool get _supportsCameraCapture {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    final sample = widget.initialSample;
    if (sample != null) {
      _sampleNameController.text = sample.sampleName;
      _purchaseDate = sample.purchaseDate;
      _batchController.text = sample.purchaseDateLabel;
      _sourceController.text = sample.source;
      _lengthController.text = sample.lengthMm.toStringAsFixed(2);
      _widthController.text = sample.widthMm.toStringAsFixed(2);
      _thicknessController.text = sample.thicknessMm.toStringAsFixed(3);
      _thicknessMiddleController.text = sample.thicknessReadingsMm.length > 1
          ? sample.thicknessReadingsMm[1].toStringAsFixed(3)
          : sample.thicknessMm.toStringAsFixed(3);
      _thicknessBackController.text = sample.thicknessReadingsMm.length > 2
          ? sample.thicknessReadingsMm[2].toStringAsFixed(3)
          : sample.thicknessMm.toStringAsFixed(3);
      _massController.text = sample.massG.toStringAsFixed(3);
      _flexibilityController.text = sample.flexibilityDeg.toStringAsFixed(2);
      _loadController.text = sample.loadG.toStringAsFixed(1);
      _frequencyController.text = sample.naturalFrequencyHz.toStringAsFixed(1);
      _submergedLengthController.text = sample.submergedLengthMm?.toStringAsFixed(3) ?? '';
      _hardnessController.text = sample.hardness?.toStringAsFixed(3) ?? '';
      _notesController.text = sample.notes;
      _photoPaths = [...sample.photoPaths];
      _resonanceTakesHz = [...sample.resonanceTakesHz];
      _innerGougeType = sample.innerGougeType;
    }
  }

  @override
  void dispose() {
    _sampleNameController.dispose();
    _batchController.dispose();
    _sourceController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _thicknessController.dispose();
    _thicknessMiddleController.dispose();
    _thicknessBackController.dispose();
    _massController.dispose();
    _flexibilityController.dispose();
    _loadController.dispose();
    _frequencyController.dispose();
    _submergedLengthController.dispose();
    _hardnessController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final averageTake = _resonanceTakesHz.isEmpty
        ? null
        : _resonanceTakesHz.reduce((a, b) => a + b) / _resonanceTakesHz.length;
    final controller = context.watch<AppController>();
    final draftMetricSample = _draftMetricSample();
    final livePrediction = _draftPrediction(controller);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Cane Sample' : 'Add Cane Sample')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _sampleNameController,
              decoration: const InputDecoration(labelText: 'Sample name / ID'),
              validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _batchController,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Date of purchase'),
              onTap: _pickPurchaseDate,
              validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _sourceController.text),
              optionsBuilder: (textEditingValue) {
                final query = textEditingValue.text.toLowerCase();
                final sources = controller.sourceHistory;
                if (query.isEmpty) {
                  return sources;
                }
                return sources.where((source) => source.toLowerCase().contains(query));
              },
              onSelected: (value) {
                _sourceController.text = value;
              },
              fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                textEditingController.value = _sourceController.value;
                return TextFormField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  decoration: const InputDecoration(labelText: 'Source / Grower'),
                  validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
                  onChanged: (value) {
                    _sourceController.value = textEditingController.value;
                    setState(() {});
                  },
                );
              },
            ),
            const SizedBox(height: 10),
            _NumberInput(
              controller: _lengthController,
              label: 'Length (mm)',
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.lengthHistory,
              onSelected: (value) {
                _lengthController.text = value.toStringAsFixed(2);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            _NumberInput(
              controller: _widthController,
              label: 'Width (mm)',
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.widthHistory,
              onSelected: (value) {
                _widthController.text = value.toStringAsFixed(2);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            _NumberInput(controller: _thicknessController, label: 'Thickness - outer (mm)', onChanged: (_) => setState(() {})),
            _ValuePresetChips(
              values: controller.thicknessOuterHistory,
              onSelected: (value) {
                _thicknessController.text = value.toStringAsFixed(3);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            _NumberInput(
              controller: _thicknessMiddleController,
              label: 'Thickness - middle (mm, optional)',
              requiredField: false,
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.thicknessMiddleHistory,
              onSelected: (value) {
                _thicknessMiddleController.text = value.toStringAsFixed(3);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            _NumberInput(
              controller: _thicknessBackController,
              label: 'Thickness - inner/back (mm, optional)',
              requiredField: false,
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.thicknessBackHistory,
              onSelected: (value) {
                _thicknessBackController.text = value.toStringAsFixed(3);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _innerGougeType,
              decoration: const InputDecoration(labelText: 'Inner gouge type'),
              items: const [
                DropdownMenuItem(value: 'excentric', child: Text('Excentric')),
                DropdownMenuItem(value: 'concentric', child: Text('Concentric')),
                DropdownMenuItem(value: 'none', child: Text('None')),
              ],
              onChanged: (value) {
                setState(() {
                  _innerGougeType = value ?? 'none';
                });
              },
            ),
            const SizedBox(height: 10),
            _NumberInput(
              controller: _massController,
              label: 'Mass (g, total cane weight, optional)',
              requiredField: false,
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.massHistory,
              onSelected: (value) {
                _massController.text = value.toStringAsFixed(3);
                setState(() {});
              },
            ),
            const SizedBox(height: 6),
            const Text(
              'Hardness is the material property of interest here: resistance to indentation and scratching. Mass is supporting data.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            _NumberInput(
              controller: _flexibilityController,
              label: 'Flexibility / Twist (deg, optional)',
              requiredField: false,
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.flexibilityHistory,
              onSelected: (value) {
                _flexibilityController.text = value.toStringAsFixed(2);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            _NumberInput(
              controller: _loadController,
              label: 'Applied load (g, standard 200 g)',
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.loadHistory,
              onSelected: (value) {
                _loadController.text = value.toStringAsFixed(1);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _NumberInput(
                    controller: _frequencyController,
                    label: 'Natural frequency (Hz)',
                    requiredField: false,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _openFrequencyRecorder,
                  icon: const Icon(Icons.mic),
                  tooltip: 'Record resonance takes',
                ),
              ],
            ),
            _ValuePresetChips(
              values: controller.frequencyHistory,
              onSelected: (value) {
                _frequencyController.text = value.toStringAsFixed(1);
                setState(() {});
              },
            ),
            if (averageTake != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Average recorded resonance: ${averageTake.toStringAsFixed(1)} Hz | Eigenfrequency score ${LauritzenToneScale.indexFromFrequency(averageTake).toStringAsFixed(1)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 10),
            _NumberInput(
              controller: _submergedLengthController,
              label: 'Submerged length (mm, buoyancy test optional)',
              requiredField: false,
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.submergedLengthHistory,
              onSelected: (value) {
                _submergedLengthController.text = value.toStringAsFixed(3);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            _NumberInput(controller: _hardnessController, label: 'Hardness (optional)', requiredField: false),
            _ValuePresetChips(
              values: controller.hardnessHistory,
              onSelected: (value) {
                _hardnessController.text = value.toStringAsFixed(3);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            _TextInput(controller: _notesController, label: 'Notes', maxLines: 3, requiredField: false),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Cane Photos',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PhotoWrap(paths: _photoPaths, onDelete: (path) => setState(() => _photoPaths.remove(path))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickMultiplePhotos,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Pick photos'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _capturePhoto,
                        icon: const Icon(Icons.photo_camera),
                        label: Text(_supportsCameraCapture ? 'Capture photo' : 'Capture photo (mobile only)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Live Prediction',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (draftMetricSample != null) _MetricPreview(sample: draftMetricSample),
                  if (draftMetricSample != null) const SizedBox(height: 10),
                  if (livePrediction == null)
                    const Text('Add dimensions, load, and frequency. Optional fields still improve prediction quality when available.')
                  else
                    _PredictionSummary(result: livePrediction),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(_isEditing ? 'Save changes' : 'Save sample'),
            ),
          ],
        ),
      ),
    );
  }

  PredictionResult? _draftPrediction(AppController controller) {
    final length = _tryParseNumber(_lengthController.text);
    final width = _tryParseNumber(_widthController.text);
    final thickness = _tryParseNumber(_thicknessController.text);
    final thicknessMiddle = _tryParseNumber(_thicknessMiddleController.text);
    final thicknessBack = _tryParseNumber(_thicknessBackController.text);
    final mass = _tryParseNumber(_massController.text);
    final flexibility = _tryParseNumber(_flexibilityController.text);
    final load = _tryParseNumber(_loadController.text);
    final typedFrequency = _tryParseNumber(_frequencyController.text);
    final avgFromTakes = _resonanceTakesHz.isEmpty
        ? null
        : _resonanceTakesHz.reduce((a, b) => a + b) / _resonanceTakesHz.length;
    final frequency = typedFrequency ?? avgFromTakes;

    if ([length, width, thickness, load, frequency]
        .any((item) => item == null)) {
      return null;
    }

    final massForPrediction = mass ?? controller.averageMassG ?? 0;
    final flexibilityForPrediction = flexibility ?? controller.averageFlexibilityDeg ?? 0;
    final thicknessReadings = [
      thickness!,
      ?thicknessMiddle,
      ?thicknessBack,
    ];

    final purchaseDate = _parseDate(_batchController.text) ?? _purchaseDate;

    return controller.predictForDraft(
      purchaseDate: purchaseDate,
      lengthMm: length!,
      widthMm: width!,
      thicknessMm: thickness,
      massG: massForPrediction,
      flexibilityDeg: flexibilityForPrediction,
      loadG: load!,
      naturalFrequencyHz: frequency!,
      thicknessReadingsMm: thicknessReadings,
      innerGougeType: _innerGougeType,
      submergedLengthMm: _tryParseNumber(_submergedLengthController.text),
    );
  }

  CaneSample? _draftMetricSample() {
    final length = _tryParseNumber(_lengthController.text);
    final width = _tryParseNumber(_widthController.text) ?? 0;
    final thickness = _tryParseNumber(_thicknessController.text) ?? 0;
    final flexibility = _tryParseNumber(_flexibilityController.text) ?? 0;
    final load = _tryParseNumber(_loadController.text) ?? 200;
    final typedFrequency = _tryParseNumber(_frequencyController.text);
    final avgFromTakes = _resonanceTakesHz.isEmpty
        ? null
        : _resonanceTakesHz.reduce((a, b) => a + b) / _resonanceTakesHz.length;
    final frequency = typedFrequency ?? avgFromTakes;
    final submergedLength = _tryParseNumber(_submergedLengthController.text);

    if (length == null) {
      return null;
    }

    return CaneSample(
      id: 'draft-metric',
      createdAt: DateTime.now(),
      sampleName: _sampleNameController.text.trim().isEmpty ? 'Draft sample' : _sampleNameController.text.trim(),
      purchaseDate: _parseDate(_batchController.text) ?? _purchaseDate,
      source: _sourceController.text.trim().isEmpty ? 'Live input' : _sourceController.text.trim(),
      lengthMm: length,
      widthMm: width,
      thicknessMm: thickness,
      thicknessReadingsMm: [if (thickness > 0) thickness],
      innerGougeType: _innerGougeType,
      massG: _tryParseNumber(_massController.text) ?? 0,
      flexibilityDeg: flexibility,
      loadG: load,
      naturalFrequencyHz: frequency ?? 0,
      submergedLengthMm: submergedLength,
      hardness: _tryParseNumber(_hardnessController.text),
      notes: _notesController.text.trim(),
      photoPaths: _photoPaths,
      resonanceTakesHz: _resonanceTakesHz,
    );
  }

  Future<void> _pickPurchaseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _purchaseDate = selected;
      _batchController.text = '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _openFrequencyRecorder() async {
    final result = await showModalBottomSheet<_FrequencyCaptureResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FrequencyCaptureSheet(initialTakes: _resonanceTakesHz),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _resonanceTakesHz = result.takes;
      if (result.selectedFrequencyHz != null) {
        _frequencyController.text = result.selectedFrequencyHz!.toStringAsFixed(1);
      }
    });
  }

  Future<void> _pickMultiplePhotos() async {
    try {
      final files = await _imagePicker.pickMultiImage();
      if (files.isEmpty) {
        return;
      }
      setState(() {
        _photoPaths.addAll(files.map((item) => item.path));
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open photo picker: $error')),
        );
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (!_supportsCameraCapture) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera capture is supported on iOS/Android in this app.')),
        );
      }
      return;
    }

    try {
      final file = await _imagePicker.pickImage(source: ImageSource.camera);
      if (file == null) {
        return;
      }
      setState(() {
        _photoPaths.add(file.path);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture photo: $error')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final naturalFrequencyHz = _tryParseNumber(_frequencyController.text) ??
        (_resonanceTakesHz.isEmpty
            ? null
            : _resonanceTakesHz.reduce((a, b) => a + b) / _resonanceTakesHz.length);

    if (naturalFrequencyHz == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Provide frequency manually or add at least one recorded take.')),
      );
      return;
    }

    final controller = context.read<AppController>();
    final lengthMm = _tryParseNumber(_lengthController.text)!;
    final widthMm = _tryParseNumber(_widthController.text)!;
    final thicknessMm = _tryParseNumber(_thicknessController.text)!;
    final thicknessMiddleMm = _tryParseNumber(_thicknessMiddleController.text);
    final thicknessBackMm = _tryParseNumber(_thicknessBackController.text);
    final massG = _tryParseNumber(_massController.text) ?? 0;
    final flexibilityDeg = _tryParseNumber(_flexibilityController.text) ?? 0;
    final loadG = _tryParseNumber(_loadController.text)!;
    final submergedLengthMm = _tryParseNumber(_submergedLengthController.text);
    final thicknessReadingsMm = [
      thicknessMm,
      ?thicknessMiddleMm,
      ?thicknessBackMm,
    ];
    final purchaseDate = _parseDate(_batchController.text) ?? _purchaseDate;

    if (_isEditing) {
      await controller.updateCaneSample(
        id: widget.initialSample!.id,
        sampleName: _sampleNameController.text.trim(),
        purchaseDate: purchaseDate,
        source: _sourceController.text.trim(),
        lengthMm: lengthMm,
        widthMm: widthMm,
        thicknessMm: thicknessMm,
        thicknessReadingsMm: thicknessReadingsMm,
        innerGougeType: _innerGougeType,
        massG: massG,
        flexibilityDeg: flexibilityDeg,
        loadG: loadG,
        naturalFrequencyHz: naturalFrequencyHz,
        submergedLengthMm: submergedLengthMm,
        hardness: _tryParseNumber(_hardnessController.text),
        notes: _notesController.text.trim(),
        photoPaths: _photoPaths,
        resonanceTakesHz: _resonanceTakesHz,
      );
    } else {
      await controller.addCaneSample(
        sampleName: _sampleNameController.text.trim(),
        purchaseDate: purchaseDate,
        source: _sourceController.text.trim(),
        lengthMm: lengthMm,
        widthMm: widthMm,
        thicknessMm: thicknessMm,
        thicknessReadingsMm: thicknessReadingsMm,
        innerGougeType: _innerGougeType,
        massG: massG,
        flexibilityDeg: flexibilityDeg,
        loadG: loadG,
        naturalFrequencyHz: naturalFrequencyHz,
        submergedLengthMm: submergedLengthMm,
        hardness: _tryParseNumber(_hardnessController.text),
        notes: _notesController.text.trim(),
        photoPaths: _photoPaths,
        resonanceTakesHz: _resonanceTakesHz,
      );
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }
}

class AddReedEvaluationPage extends StatefulWidget {
  const AddReedEvaluationPage({super.key, this.initialEvaluation, this.initialCaneId});

  final ReedEvaluation? initialEvaluation;
  final String? initialCaneId;

  @override
  State<AddReedEvaluationPage> createState() => _AddReedEvaluationPageState();
}

class _AddReedEvaluationPageState extends State<AddReedEvaluationPage> {
  final _formKey = GlobalKey<FormState>();
  final _commentController = TextEditingController();
  final _longevityController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String? _caneId;
  int _response = 7;
  int _stability = 7;
  int _tone = 7;
  int _intonation = 7;
  int _flexibility = 7;
  int _projection = 7;
  int _resistance = 7;
  bool _goldStandard = false;
  List<String> _photoPaths = [];

  bool get _isEditing => widget.initialEvaluation != null;

  bool get _supportsCameraCapture {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEvaluation;
    if (initial == null) {
      _caneId = widget.initialCaneId;
      return;
    }

    _caneId = initial.caneId;
    _response = initial.response;
    _stability = initial.stability;
    _tone = initial.tone;
    _intonation = initial.intonation;
    _flexibility = initial.flexibility;
    _projection = initial.projection;
    _resistance = initial.resistance;
    _goldStandard = initial.goldStandard;
    _commentController.text = initial.comment;
    _longevityController.text = initial.longevityDays?.toString() ?? '';
    _photoPaths = [...initial.photoPaths];
  }

  @override
  void dispose() {
    _commentController.dispose();
    _longevityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caneSamples = context.watch<AppController>().caneSamples;
    _caneId ??= caneSamples.isNotEmpty ? caneSamples.first.id : null;
    final selectedCane = _caneId == null
        ? null
        : caneSamples.where((sample) => sample.id == _caneId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Reed Rating' : 'Rate Reed')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _caneId,
              decoration: const InputDecoration(labelText: 'Linked cane sample'),
              items: caneSamples
                  .map(
                    (sample) => DropdownMenuItem(
                      value: sample.id,
                      child: Text('${sample.sampleName} - ${sample.purchaseDateLabel}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _caneId = value),
              validator: (value) => (value == null || value.isEmpty) ? 'Select a cane sample' : null,
            ),
            if (selectedCane != null) ...[
              const SizedBox(height: 10),
              _CaneStatsExpansion(sample: selectedCane),
            ],
            const SizedBox(height: 10),
            _ScoreSlider(label: 'Response', value: _response, onChanged: (value) => setState(() => _response = value)),
            _ScoreSlider(label: 'Stability', value: _stability, onChanged: (value) => setState(() => _stability = value)),
            _ScoreSlider(label: 'Tone', value: _tone, onChanged: (value) => setState(() => _tone = value)),
            _ScoreSlider(label: 'Intonation', value: _intonation, onChanged: (value) => setState(() => _intonation = value)),
            _ScoreSlider(label: 'Flexibility', value: _flexibility, onChanged: (value) => setState(() => _flexibility = value)),
            _ScoreSlider(label: 'Projection', value: _projection, onChanged: (value) => setState(() => _projection = value)),
            _ScoreSlider(label: 'Resistance', value: _resistance, onChanged: (value) => setState(() => _resistance = value)),
            SwitchListTile(
              value: _goldStandard,
              onChanged: (value) => setState(() => _goldStandard = value),
              title: const Text('Gold Standard reed'),
              subtitle: const Text('Mark this reed as one of your finest references.'),
            ),
            const SizedBox(height: 10),
            _TextInput(controller: _commentController, label: 'Comment', maxLines: 3, requiredField: false),
            const SizedBox(height: 10),
            _NumberInput(controller: _longevityController, label: 'Longevity (days, optional)', requiredField: false, integerOnly: true),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Reed Photos',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PhotoWrap(paths: _photoPaths, onDelete: (path) => setState(() => _photoPaths.remove(path))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickMultiplePhotos,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Pick photos'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _capturePhoto,
                        icon: const Icon(Icons.photo_camera),
                        label: Text(_supportsCameraCapture ? 'Capture photo' : 'Capture photo (mobile only)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(_isEditing ? 'Save changes' : 'Save reed evaluation'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMultiplePhotos() async {
    try {
      final files = await _imagePicker.pickMultiImage();
      if (files.isEmpty) {
        return;
      }
      setState(() {
        _photoPaths.addAll(files.map((item) => item.path));
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open photo picker: $error')),
        );
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (!_supportsCameraCapture) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera capture is supported on iOS/Android in this app.')),
        );
      }
      return;
    }

    try {
      final file = await _imagePicker.pickImage(source: ImageSource.camera);
      if (file == null) {
        return;
      }
      setState(() {
        _photoPaths.add(file.path);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture photo: $error')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final controller = context.read<AppController>();
    if (_isEditing) {
      await controller.updateReedEvaluation(
        id: widget.initialEvaluation!.id,
        caneId: _caneId!,
        response: _response,
        stability: _stability,
        tone: _tone,
        intonation: _intonation,
        flexibility: _flexibility,
        projection: _projection,
        resistance: _resistance,
        comment: _commentController.text.trim(),
        goldStandard: _goldStandard,
        longevityDays: _tryParseInt(_longevityController.text),
        photoPaths: _photoPaths,
      );
    } else {
      await controller.addReedEvaluation(
        caneId: _caneId!,
        response: _response,
        stability: _stability,
        tone: _tone,
        intonation: _intonation,
        flexibility: _flexibility,
        projection: _projection,
        resistance: _resistance,
        comment: _commentController.text.trim(),
        goldStandard: _goldStandard,
        longevityDays: _tryParseInt(_longevityController.text),
        photoPaths: _photoPaths,
      );
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }
}

class _FrequencyCaptureResult {
  const _FrequencyCaptureResult({required this.takes, required this.selectedFrequencyHz});

  final List<double> takes;
  final double? selectedFrequencyHz;
}

class _FrequencyCaptureSheet extends StatefulWidget {
  const _FrequencyCaptureSheet({required this.initialTakes});

  final List<double> initialTakes;

  @override
  State<_FrequencyCaptureSheet> createState() => _FrequencyCaptureSheetState();
}

class _FrequencyCaptureSheetState extends State<_FrequencyCaptureSheet> {
  static const double _minHz = 900;
  static const double _maxHz = 2000;

  final ResonanceCaptureService _service = ResonanceCaptureService();
  final TextEditingController _manualController = TextEditingController();

  late List<double> _takes;
  final List<double> _takeConfidences = []; // 0..1 per take
  int? _selectedIndex;
  bool _isRecording = false;
  StreamSubscription<LiveCaptureFrame>? _liveSub;
  LiveCaptureFrame? _liveFrame;
  double _sliderHz = 1200;

  @override
  void initState() {
    super.initState();
    _takes = [...widget.initialTakes];
    for (int i = 0; i < _takes.length; i++) {
      _takeConfidences.add(0); // unknown confidence for pre-existing takes
    }
    if (_takes.isNotEmpty) {
      _selectedIndex = _takes.length - 1;
      _setManual(_takes.last);
    } else {
      _setManual(_sliderHz);
    }
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _manualController.dispose();
    _service.dispose();
    super.dispose();
  }

  void _setManual(double hz) {
    final clamped = hz.clamp(_minHz, _maxHz);
    _sliderHz = clamped;
    _manualController.text = clamped.toStringAsFixed(1);
  }

  double get _mean {
    if (_takes.isEmpty) return 0;
    return _takes.reduce((a, b) => a + b) / _takes.length;
  }

  double get _stddev {
    if (_takes.length < 2) return 0;
    final mean = _mean;
    final sumSq = _takes.fold<double>(0, (acc, v) => acc + (v - mean) * (v - mean));
    return math.sqrt(sumSq / (_takes.length - 1));
  }

  double get _confidencePercent {
    if (_takes.isEmpty) return 0;
    if (_takes.length == 1) return 60;
    final mean = _mean;
    if (mean <= 0) return 0;
    final cv = _stddev / mean; // coefficient of variation
    // 0% CV -> 100% confidence; 5% CV -> 50%; >=10% CV -> 0%
    final raw = (1 - (cv * 10)).clamp(0.0, 1.0);
    final sampleBoost = math.min(_takes.length / 5, 1.0);
    return (raw * 70 + sampleBoost * 30).clamp(0.0, 100.0);
  }

  @override
  Widget build(BuildContext context) {
    final manualValue = _tryParseNumber(_manualController.text);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Record Resonance Takes',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                _isRecording
                    ? 'Now: generate a clear tone (tap, pluck or sustain). Stop when the reading settles.'
                    : 'Press "Start take", then produce a clear tone. Repeat for a few takes to build confidence.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              _LiveCapturePanel(
                isRecording: _isRecording,
                frame: _liveFrame,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _isRecording ? null : _start,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text('Start take'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isRecording ? _stop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop & log take'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TakeBarsPainter(values: _takes, selectedIndex: _selectedIndex),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 10),
              _AccuracySummary(
                count: _takes.length,
                mean: _mean,
                stddev: _stddev,
                confidencePercent: _confidencePercent,
              ),
              const SizedBox(height: 10),
              if (_takes.isEmpty)
                const Text('No takes yet.')
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(_takes.length, (index) {
                    final take = _takes[index];
                    final confidence = _takeConfidences.length > index ? _takeConfidences[index] : 0.0;
                    final isSelected = _selectedIndex == index;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      color: isSelected ? const Color(0xFFE7F3F6) : null,
                      child: ListTile(
                        dense: true,
                        title: Text(
                          'Take ${index + 1}: ${take.toStringAsFixed(1)} Hz',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(confidence > 0
                            ? 'Detection strength: ${(confidence * 100).toStringAsFixed(0)}%'
                            : 'Strength: n/a'),
                        leading: IconButton(
                          icon: const Icon(Icons.play_circle_outline),
                          tooltip: 'Play this take',
                          onPressed: () => _service.playTone(take),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked),
                              tooltip: 'Use this take',
                              onPressed: () {
                                setState(() {
                                  _selectedIndex = index;
                                  _setManual(take);
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove take',
                              onPressed: () {
                                setState(() {
                                  _takes.removeAt(index);
                                  if (_takeConfidences.length > index) {
                                    _takeConfidences.removeAt(index);
                                  }
                                  if (_selectedIndex == index) {
                                    _selectedIndex = _takes.isEmpty ? null : _takes.length - 1;
                                    if (_selectedIndex != null) {
                                      _setManual(_takes[_selectedIndex!]);
                                    }
                                  } else if (_selectedIndex != null && _selectedIndex! > index) {
                                    _selectedIndex = _selectedIndex! - 1;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              const SizedBox(height: 10),
              const Text(
                'Audit & fine-tune chosen frequency',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Drag the fader to match what you hear from the cane. Tap play to compare against a pure tone.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      min: _minHz,
                      max: _maxHz,
                      value: _sliderHz.clamp(_minHz, _maxHz),
                      divisions: (_maxHz - _minHz).round(),
                      label: '${_sliderHz.toStringAsFixed(0)} Hz',
                      onChangeStart: (value) {
                        _service.startContinuousTone(value);
                      },
                      onChanged: (value) {
                        setState(() {
                          _sliderHz = value;
                          _manualController.text = value.toStringAsFixed(1);
                        });
                        _service.setContinuousToneHz(value);
                      },
                      onChangeEnd: (value) {
                        _service.stopContinuousTone();
                      },
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.volume_up),
                    tooltip: 'Play chosen frequency',
                    onPressed: manualValue == null ? null : () => _service.playTone(manualValue),
                  ),
                ],
              ),
              _NumberInput(
                controller: _manualController,
                label: 'Selected frequency (Hz)',
                requiredField: false,
                onChanged: (text) {
                  final parsed = _tryParseNumber(text);
                  if (parsed != null) {
                    setState(() {
                      _sliderHz = parsed.clamp(_minHz, _maxHz);
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _FrequencyCaptureResult(
                          takes: _takes,
                          selectedFrequencyHz: _tryParseNumber(_manualController.text),
                        ),
                      );
                    },
                    child: const Text('Apply frequency'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start() async {
    try {
      final hasPermission = await _service.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied.')),
          );
        }
        return;
      }

      final stream = await _service.startLiveCapture();
      _liveSub?.cancel();
      _liveSub = stream.listen((frame) {
        if (!mounted) return;
        setState(() => _liveFrame = frame);
      });
      setState(() {
        _isRecording = true;
        _liveFrame = null;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $error')),
        );
      }
    }
  }

  Future<void> _stop() async {
    try {
      final result = await _service.stopLiveCapture();
      await _liveSub?.cancel();
      _liveSub = null;
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _liveFrame = null;
      });

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not estimate resonance for this take. Try again with a stronger, sustained tone.')),
        );
        return;
      }

      setState(() {
        _takes.add(result.hz);
        _takeConfidences.add(result.correlation);
        _selectedIndex = _takes.length - 1;
        _setManual(result.hz);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'Take ${_takes.length}: ${result.hz.toStringAsFixed(1)} Hz (strength ${(result.correlation * 100).toStringAsFixed(0)}%). '
          'Confidence now ${_confidencePercent.toStringAsFixed(0)}%.',
        )),
      );
    } catch (error) {
      setState(() {
        _isRecording = false;
        _liveFrame = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not stop/analyze recording: $error')),
        );
      }
    }
  }
}

class _LiveCapturePanel extends StatelessWidget {
  const _LiveCapturePanel({required this.isRecording, required this.frame});

  final bool isRecording;
  final LiveCaptureFrame? frame;

  @override
  Widget build(BuildContext context) {
    final levelDb = frame?.levelDb ?? -80;
    final levelNorm = ((levelDb + 60) / 60).clamp(0.0, 1.0);
    final estimate = frame?.estimateHz;
    final correlation = frame?.correlation;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isRecording ? const Color(0xFFFFF6E5) : const Color(0xFFF1F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRecording ? const Color(0xFFE0A030) : const Color(0xFFDDE3E6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRecording ? Icons.mic : Icons.mic_off,
                color: isRecording ? const Color(0xFFCC5500) : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                isRecording ? 'Listening...' : 'Mic idle',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (frame != null)
                Text('${frame!.elapsed.inSeconds}.${(frame!.elapsed.inMilliseconds % 1000) ~/ 100}s'),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: levelNorm,
              minHeight: 8,
              backgroundColor: const Color(0xFFE0E5E8),
              valueColor: AlwaysStoppedAnimation(
                levelNorm > 0.7
                    ? const Color(0xFFE0584A)
                    : (levelNorm > 0.25 ? const Color(0xFF2A8A4A) : const Color(0xFF6EA9B5)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isRecording
                ? (estimate == null
                    ? 'Detecting... generate a clear, sustained tone now.'
                    : 'Live reading: ${estimate.toStringAsFixed(1)} Hz '
                        '(strength ${((correlation ?? 0) * 100).toStringAsFixed(0)}%)')
                : 'Recording stopped. Use "Start take" to record again.',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AccuracySummary extends StatelessWidget {
  const _AccuracySummary({
    required this.count,
    required this.mean,
    required this.stddev,
    required this.confidencePercent,
  });

  final int count;
  final double mean;
  final double stddev;
  final double confidencePercent;

  @override
  Widget build(BuildContext context) {
    final color = confidencePercent >= 75
        ? const Color(0xFF2A8A4A)
        : (confidencePercent >= 45 ? const Color(0xFFE0A030) : const Color(0xFFE0584A));
    final tip = count == 0
        ? 'Record one or more takes to start building confidence.'
        : count == 1
            ? 'Add another take to verify – more samples raise confidence.'
            : 'Mean ${mean.toStringAsFixed(1)} Hz +/- ${stddev.toStringAsFixed(1)} Hz across $count takes.';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE3E6)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Text(
              '${confidencePercent.toStringAsFixed(0)}%',
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Capture confidence', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(tip, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TakeBarsPainter extends CustomPainter {
  const _TakeBarsPainter({required this.values, required this.selectedIndex});

  final List<double> values;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFE9EEF1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      bg,
    );

    if (values.isEmpty) {
      return;
    }

    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    final span = (maxValue - minValue).abs() < 0.0001 ? 1.0 : (maxValue - minValue);

    final barWidth = size.width / (values.length * 1.6);
    for (int i = 0; i < values.length; i++) {
      final value = values[i];
      final normalized = (value - minValue) / span;
      final h = 18 + normalized * (size.height - 28);
      final x = (i + 0.5) * (size.width / values.length) - barWidth / 2;
      final y = size.height - h;
      final selected = selectedIndex == i;

      final paint = Paint()..color = selected ? const Color(0xFF16697A) : const Color(0xFF6EA9B5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barWidth, h), const Radius.circular(6)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TakeBarsPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.selectedIndex != selectedIndex;
  }
}

class _PredictionSummary extends StatelessWidget {
  const _PredictionSummary({required this.result});

  final PredictionResult result;

  @override
  Widget build(BuildContext context) {
    final ari = result.targetCane.ari;
    final ariStatus = _ariStatus(ari);
    final buoyancy = result.targetCane.buoyancyPercent;
    final buoyancyStatus = _buoyancyStatus(buoyancy);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ARE\'S REED INDEX',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: ariStatus.color,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ari == null ? 'n/a' : ari.toStringAsFixed(1),
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 30, color: ariStatus.color),
        ),
        Text(ariStatus.label, style: TextStyle(fontWeight: FontWeight.w700, color: ariStatus.color)),
        const SizedBox(height: 8),
        Text(
          'Buoyancy: ${buoyancy?.toStringAsFixed(1) ?? 'n/a'}% - ${buoyancyStatus.label}',
          style: TextStyle(fontWeight: FontWeight.w700, color: buoyancyStatus.color),
        ),
        const SizedBox(height: 10),
        Text(
          'Similarity: ${result.similarityPercent.toStringAsFixed(1)}%',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        const SizedBox(height: 4),
        Text(
          'Compared with ${result.successfulReferenceCount} successful reeds (avg grade ${ReedEvaluation.gradeForScore(result.averageReferenceScore)} | ${result.averageReferenceScore.toStringAsFixed(1)}/10).',
        ),
        const SizedBox(height: 6),
        Text('Eigenfrequency score: ${result.referenceAverages['lauritzenToneIndex']?.toStringAsFixed(1) ?? 'n/a'}'),
        Text('Reference ARI: ${result.referenceAverages['ari']?.toStringAsFixed(1) ?? 'n/a'}'),
        Text('Reference buoyancy: ${result.referenceAverages['buoyancyPercent']?.toStringAsFixed(1) ?? 'n/a'}%'),
        if (ari != null && buoyancy != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_combinedPredictionMessage(ari, buoyancy)),
          ),
        const SizedBox(height: 6),
        if (result.featureDeviations.isNotEmpty)
          ...result.featureDeviations.map((row) => Text('- $row')),
      ],
    );
  }
}

class _MetricPreview extends StatelessWidget {
  const _MetricPreview({required this.sample});

  final CaneSample sample;

  @override
  Widget build(BuildContext context) {
    final ari = sample.ari;
    final ariStatus = _ariStatus(ari);
    final buoyancy = sample.buoyancyPercent;
    final buoyancyStatus = _buoyancyStatus(buoyancy);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Live ARI Preview',
          style: TextStyle(fontWeight: FontWeight.w700, color: ariStatus.color),
        ),
        const SizedBox(height: 4),
        Text(
          ari == null ? 'ARI: add flexibility and frequency' : 'ARI: ${ari.toStringAsFixed(0)} (${ariStatus.label})',
          style: TextStyle(fontWeight: FontWeight.w700, color: ariStatus.color),
        ),
        if (sample.naturalFrequencyHz > 0)
          Text(
            'Eigenfrequency score: ${sample.eigenfrequencyScore.toStringAsFixed(0)}',
          ),
        const SizedBox(height: 6),
        Text(
          buoyancy == null
              ? 'Buoyancy: enter submerged length for density interpretation'
              : 'Buoyancy: ${buoyancy.toStringAsFixed(1)}% (${buoyancyStatus.label})',
          style: TextStyle(fontWeight: FontWeight.w700, color: buoyancyStatus.color),
        ),
        if (ari != null && buoyancy != null) ...[
          const SizedBox(height: 4),
          Text(_combinedPredictionMessage(ari, buoyancy)),
        ],
      ],
    );
  }
}

class _CaneCard extends StatelessWidget {
  const _CaneCard({
    required this.sample,
    this.isReviewed,
    this.onEdit,
    this.onDelete,
  });

  final CaneSample sample;
  final bool? isReviewed;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${sample.sampleName} - ${sample.purchaseDateLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
                if (isReviewed != null)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isReviewed! ? const Color(0xFF2E7D32) : const Color(0xFFF57C00),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isReviewed! ? 'Reviewed' : 'Pending review',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                if (onEdit != null || onDelete != null)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit?.call();
                      }
                      if (value == 'delete') {
                        onDelete?.call();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Source: ${sample.source}'),
            Text('L/W/T ${sample.lengthMm.toStringAsFixed(2)}/${sample.widthMm.toStringAsFixed(2)}/${sample.thicknessMm.toStringAsFixed(3)} mm'),
            if (sample.thicknessReadingsMm.length > 1)
              Text('Thickness variants: ${sample.thicknessReadingsMm.skip(1).map((value) => value.toStringAsFixed(3)).join(' / ')} mm'),
            Text(sample.flexibilityDeg > 0
                ? 'Flex ${sample.flexibilityDeg.toStringAsFixed(1)} deg at ${sample.loadG.toStringAsFixed(1)} g | Stiffness ${sample.relativeStiffness.toStringAsFixed(2)}'
                : 'Flexibility test not recorded'),
            Text('Resonance ${sample.naturalFrequencyHz.toStringAsFixed(1)} Hz | Eigenfrequency score ${sample.eigenfrequencyScore.toStringAsFixed(1)}'),
            Text('ARI ${sample.ari?.toStringAsFixed(1) ?? 'n/a'} (${_ariStatus(sample.ari).label})'),
            Text('Buoyancy ${sample.buoyancyPercent?.toStringAsFixed(1) ?? 'n/a'}% (${_buoyancyStatus(sample.buoyancyPercent).label})'),
            if (sample.photoPaths.isNotEmpty) ...[
              const SizedBox(height: 6),
              _ThumbnailRow(paths: sample.photoPaths),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReedCard extends StatelessWidget {
  const _ReedCard({
    required this.evaluation,
    required this.cane,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final ReedEvaluation evaluation;
  final CaneSample? cane;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final markerColor = _scoreMarkerColor(evaluation.overallScore);
    final photos = [
      ...evaluation.photoPaths,
      if (cane != null) ...cane!.photoPaths,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 40,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: markerColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Expanded(
                  child: Text(
                    cane == null ? 'Unknown cane sample' : '${cane!.sampleName} - ${cane!.purchaseDateLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
                if (evaluation.goldStandard)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC89B1F),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Gold Standard',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: markerColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    ReedEvaluation.gradeForScore(evaluation.overallScore),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                if (onEdit != null || onDelete != null)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit?.call();
                      }
                      if (value == 'delete') {
                        onDelete?.call();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Overall grade ${ReedEvaluation.gradeForScore(evaluation.overallScore)} (${evaluation.overallScore.toStringAsFixed(1)} / 10)'),
            Text('R:${evaluation.response} S:${evaluation.stability} T:${evaluation.tone} I:${evaluation.intonation} F:${evaluation.flexibility} P:${evaluation.projection} Res:${evaluation.resistance}'),
            const SizedBox(height: 4),
            const Text('Tap card to open full stats', style: TextStyle(fontSize: 12)),
            if (evaluation.comment.isNotEmpty) Text(evaluation.comment),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 6),
              _ThumbnailRow(paths: photos),
            ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingReedCard extends StatelessWidget {
  const _PendingReedCard({required this.sample, this.onTap});

  final CaneSample sample;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final photos = sample.photoPaths;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                const Icon(Icons.schedule, color: Color(0xFFF57C00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${sample.sampleName} - ${sample.purchaseDateLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF57C00),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Yet to review',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Source: ${sample.source}'),
            Text('Resonance ${sample.naturalFrequencyHz.toStringAsFixed(1)} Hz | Flex ${sample.flexibilityDeg.toStringAsFixed(1)} deg'),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 6),
              _ThumbnailRow(paths: photos),
            ],
            const SizedBox(height: 4),
            const Text('Tap card to start review', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaneStatsExpansion extends StatelessWidget {
  const _CaneStatsExpansion({required this.sample});

  final CaneSample sample;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.analytics_outlined),
        title: const Text('Cane stats'),
        subtitle: Text('${sample.sampleName} - ${sample.purchaseDateLabel}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Source: ${sample.source}'),
          Text('L/W/T ${sample.lengthMm.toStringAsFixed(2)}/${sample.widthMm.toStringAsFixed(2)}/${sample.thicknessMm.toStringAsFixed(3)} mm'),
          Text(sample.flexibilityDeg > 0
              ? 'Flex ${sample.flexibilityDeg.toStringAsFixed(1)} deg at ${sample.loadG.toStringAsFixed(1)} g | Stiffness ${sample.relativeStiffness.toStringAsFixed(2)}'
              : 'Flexibility test not recorded'),
          Text('Resonance ${sample.naturalFrequencyHz.toStringAsFixed(1)} Hz | Eigenfrequency score ${sample.eigenfrequencyScore.toStringAsFixed(1)}'),
          Text('ARI ${sample.ari?.toStringAsFixed(1) ?? 'n/a'} (${_ariStatus(sample.ari).label})'),
          Text('Buoyancy ${sample.buoyancyPercent?.toStringAsFixed(1) ?? 'n/a'}% (${_buoyancyStatus(sample.buoyancyPercent).label})'),
          if (sample.photoPaths.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ThumbnailRow(paths: sample.photoPaths),
          ],
        ],
      ),
    );
  }
}

class _ThumbnailRow extends StatelessWidget {
  const _ThumbnailRow({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: paths.take(5).map((path) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(path),
            width: 62,
            height: 62,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 62,
              height: 62,
              color: Colors.grey.shade300,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PhotoWrap extends StatelessWidget {
  const _PhotoWrap({required this.paths, required this.onDelete});

  final List<String> paths;
  final void Function(String path) onDelete;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return const Text('No photos added yet.');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: paths.map((path) {
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(path),
                width: 84,
                height: 84,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 84,
                  height: 84,
                  color: Colors.grey.shade300,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
            Positioned(
              right: -8,
              top: -8,
              child: IconButton(
                icon: const Icon(Icons.cancel),
                onPressed: () => onDelete(path),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({required this.controller, required this.label, this.maxLines = 1, this.requiredField = true});

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final bool requiredField;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        if (!requiredField) {
          return null;
        }
        return (value ?? '').trim().isEmpty ? 'Required' : null;
      },
    );
  }
}

class _NumberInput extends StatelessWidget {
  const _NumberInput({
    required this.controller,
    required this.label,
    this.requiredField = true,
    this.integerOnly = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool requiredField;
  final bool integerOnly;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: !integerOnly),
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
      validator: (value) {
        final trimmed = (value ?? '').trim();
        if (!requiredField && trimmed.isEmpty) {
          return null;
        }
        if (trimmed.isEmpty) {
          return 'Required';
        }
        if (integerOnly) {
          if (_tryParseInt(trimmed) == null) {
            return 'Invalid integer';
          }
        } else if (_tryParseNumber(trimmed) == null) {
          return 'Invalid number';
        }
        return null;
      },
    );
  }
}

class _ValuePresetChips extends StatelessWidget {
  const _ValuePresetChips({required this.values, required this.onSelected});

  final List<double> values;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: values.take(8).map((value) {
          return ActionChip(
            label: Text(value.toStringAsFixed(3)),
            onPressed: () => onSelected(value),
          );
        }).toList(),
      ),
    );
  }
}

class _ScoreSlider extends StatelessWidget {
  const _ScoreSlider({required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final grade = ReedEvaluation.gradeForScore(value.toDouble());
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: $grade ($value/10)'),
          Slider(
            value: value.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: grade,
            onChanged: (newValue) => onChanged(newValue.round()),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

Color _scoreMarkerColor(double score) {
  if (score >= 8.5) {
    return const Color(0xFF1B5E20);
  }
  if (score >= 7.5) {
    return const Color(0xFF2E7D32);
  }
  if (score >= 6.0) {
    return const Color(0xFFF9A825);
  }
  if (score >= 4.5) {
    return const Color(0xFFEF6C00);
  }
  return const Color(0xFFC62828);
}

double? _tryParseNumber(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return null;
  }
  return double.tryParse(normalized);
}

DateTime? _parseDate(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return DateTime.tryParse(trimmed);
}

int? _tryParseInt(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return int.tryParse(trimmed);
}
