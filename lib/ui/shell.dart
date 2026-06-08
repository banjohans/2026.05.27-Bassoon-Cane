import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cane.dart';
import '../models/reed.dart';
import '../services/prediction_engine.dart';
import '../services/resonance_capture_service.dart';
import '../state/app_controller.dart';
import '../state/theme_controller.dart';
import '../app.dart'
    show
        kBrandBurgundy,
        kBrandBurgundyDark,
        kBrandBurgundyDeep,
        kBrandGold,
        kBrandGoldLight,
        kBrandCane,
        kBrandParchment,
        kBrandParchmentDeep,
        kSurfaceTint,
        kSurfaceLine,
        kInk,
        kStatusSuccess,
        kStatusSuccessAccent,
        kStatusSuccessSoft,
        kStatusWarning,
        kStatusWarningAccent,
        kStatusWarningSoft,
        kStatusDanger,
        kStatusDangerAccent,
        kStatusNeutral;

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _InAppTourStep {
  const _InAppTourStep({
    required this.tab,
    required this.icon,
    required this.title,
    required this.body,
    required this.bullets,
  });

  final int tab;
  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
}

class _ShellPageState extends State<ShellPage> {
  int _tab = 0;
  bool _tourActive = false;
  int _tourIndex = 0;

  static const List<_InAppTourStep> _tourSteps = [
    _InAppTourStep(
      tab: 0,
      icon: Icons.home_rounded,
      title: 'Home Dashboard',
      body: 'Start here to read trends and your current best-performance profile.',
      bullets: [
        'Check success rate and average quality in your selected date range.',
        'Use this as your quick status view before making adjustments.',
      ],
    ),
    _InAppTourStep(
      tab: 1,
      icon: Icons.insights_rounded,
      title: 'Behavior Map',
      body: 'This view shows where successful reeds cluster on the map.',
      bullets: [
        'Tap points or clusters to inspect the linked reeds.',
        'Use the target zone to guide your next cane selection.',
      ],
    ),
    _InAppTourStep(
      tab: 2,
      icon: Icons.straighten,
      title: 'Cane Logging',
      body: 'Register cane pieces and capture measurements and resonance.',
      bullets: [
        'Add physical metrics and photos for traceability.',
        'Use the recorder flow to set reliable natural frequency.',
      ],
    ),
    _InAppTourStep(
      tab: 3,
      icon: Icons.library_music,
      title: 'Reed Evaluations',
      body: 'Connect musical outcomes to cane instances.',
      bullets: [
        'Rate response, tone, stability, intonation, and projection.',
        'Use export/import JSON for backup and restore.',
      ],
    ),
    _InAppTourStep(
      tab: 4,
      icon: Icons.tune_rounded,
      title: 'About and Safety',
      body: 'Review ARE guidance, app settings, and data safety actions.',
      bullets: [
        'Read the ARE interpretation bands to align evaluations.',
        'Use Danger zone only after exporting a backup.',
      ],
    ),
  ];

  void _startTour() {
    setState(() {
      _tourActive = true;
      _tourIndex = 0;
      _tab = _tourSteps.first.tab;
    });
  }

  void _closeTour() {
    setState(() => _tourActive = false);
  }

  void _setTourStep(int index) {
    final safeIndex = index.clamp(0, _tourSteps.length - 1);
    setState(() {
      _tourIndex = safeIndex;
      _tab = _tourSteps[safeIndex].tab;
    });
  }

  void _nextTourStep() {
    if (_tourIndex >= _tourSteps.length - 1) {
      _closeTour();
      return;
    }
    _setTourStep(_tourIndex + 1);
  }

  void _previousTourStep() {
    if (_tourIndex <= 0) {
      return;
    }
    _setTourStep(_tourIndex - 1);
  }

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
          _SettingsTab(onStartTour: _startTour),
        ];

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: Theme.of(context).extension<BrandTheme>()?.bodyGradient ??
                    const [kBrandParchment, kBrandParchmentDeep, kSurfaceTint],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(child: pages[_tab]),
                  if (controller.errorMessage != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.warning_amber_rounded),
                        color: Theme.of(context).colorScheme.error,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(controller.errorMessage!)),
                          );
                        },
                      ),
                    ),
                  if (_tourActive)
                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 180),
                        builder: (context, value, child) {
                          return IgnorePointer(
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: 1.8 * value,
                                sigmaY: 1.8 * value,
                              ),
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: 0.28 * value),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (_tourActive)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Card(
                        elevation: 8,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary.withValues(alpha: 0.14),
                                    child: Icon(
                                      _tourSteps[_tourIndex].icon,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Tour ${_tourIndex + 1}/${_tourSteps.length}: ${_tourSteps[_tourIndex].title}',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _tourSteps[_tourIndex].body,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
                              ),
                              const SizedBox(height: 8),
                              ..._tourSteps[_tourIndex].bullets.map(
                                (line) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Icon(Icons.circle, size: 6, color: kBrandBurgundy),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          line,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall?.copyWith(height: 1.35),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: _tourIndex == 0 ? null : _previousTourStep,
                                    child: const Text('Back'),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: _closeTour,
                                    child: const Text('Close'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: _nextTourStep,
                                    child: Text(
                                      _tourIndex == _tourSteps.length - 1 ? 'Finish' : 'Next',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) {
              setState(() {
                _tab = value;
                if (_tourActive) {
                  final match = _tourSteps.indexWhere((step) => step.tab == value);
                  if (match >= 0) {
                    _tourIndex = match;
                  }
                }
              });
            },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'Behavior'),
              NavigationDestination(icon: Icon(Icons.straighten), label: 'Cane'),
              NavigationDestination(icon: Icon(Icons.library_music), label: 'Reeds'),
              NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'About'),
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
    final goldStandardCount = reeds.where((r) => r.goldStandard).length;
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
    final topCount = ranked.isEmpty
        ? 0
        : math.max(1, (ranked.length * 0.25).ceil()).clamp(1, ranked.length);
    final topReeds = ranked.take(topCount).toList();
    final topCanes = topReeds
        .map((r) => canesById[r.caneId])
        .whereType<CaneSample>()
        .toList();
    final hallOfFame = allReeds
        .where((reed) => reed.goldStandard)
        .map((reed) {
          final cane = canesById[reed.caneId];
          if (cane == null) {
            return null;
          }
          return _HallOfFameEntry(reed: reed, cane: cane);
        })
        .whereType<_HallOfFameEntry>()
        .toList()
      ..sort((a, b) {
        final score = b.reed.overallScore.compareTo(a.reed.overallScore);
        if (score != 0) {
          return score;
        }
        return b.reed.createdAt.compareTo(a.reed.createdAt);
      });
    final topHallOfFame = hallOfFame.take(10).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _HomeWordmarkHeader(),
        const SizedBox(height: 12),
        _RangeSelector(
          range: _range,
          onChanged: (value) => setState(() => _range = value),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Showing data from the ${_range.longLabel}.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              fontSize: 12,
            ),
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
          if (goldStandardCount > 0) ...[
            const SizedBox(height: 10),
            _GoldStandardSummary(count: goldStandardCount),
          ],
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
          const SizedBox(height: 12),
          _GoldStandardHallOfFameCard(entries: topHallOfFame),
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
      ? 'The home screen will automatically fill with useful stats, trends, and your top performer profile once you add cane and reed data.'
      : 'This home screen view fills itself with useful stats once data exists in the selected range. Try a wider range above, or log a cane and a reed to populate this window.';
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
        border: Border.all(color: kSurfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined,
                  color: kBrandBurgundy, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: kBrandBurgundyDeep,
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
                  backgroundColor: kBrandBurgundy,
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
                  foregroundColor: kBrandBurgundy,
                  side: const BorderSide(color: kBrandBurgundy),
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
          colors: [kBrandBurgundyDeep, kBrandBurgundyDark, kBrandBurgundy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    const Text(
                      'It\'s about a predictable cane, not a perfect cane.',
                      style: TextStyle(
                        color: kBrandParchment,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'A measurement journal for bassoon reed makers. Log every cane and reed, '
            'then let the app surface the physical fingerprint of the ones that play best for you.',
            style: TextStyle(
              color: kBrandParchment.withValues(alpha: 0.92),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: kBrandGold.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBrandGold.withValues(alpha: 0.45)),
            ),
            child: const Text(
              'Developed using a combination of well known methods, and the craft and research from professional bassoonist '
              'Are Bøen Lauritzen, who has made his own reeds throughout a long '
              'career as a working bassoon player, and developed the ARE method.',
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
            color: kBrandBurgundy,
            icon: Icons.assignment_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountCard(
            label: 'Successful',
            value: '$successful',
            color: kStatusSuccess,
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountCard(
            label: 'Unsuccessful',
            value: '$unsuccessful',
            color: kStatusDanger,
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Boost saturation/lightness for legibility on dark surfaces.
    final accent = isDark ? Color.lerp(color, Colors.white, 0.35)! : color;
    final onSurface = scheme.onSurface;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: accent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: onSurface.withValues(alpha: 0.78),
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
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.label,
            style: TextStyle(
              fontSize: 11.5,
              color: onSurface.withValues(alpha: 0.65),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (data.unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  data.unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withValues(alpha: 0.6),
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Text(
              'Log a few reeds (with linked cane measurements) to unlock your personal profile.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kStatusSuccessSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Top ${topReeds.length} reed${topReeds.length == 1 ? '' : 's'} · '
                'avg score ${avgScore.toStringAsFixed(2)}/10 '
                '(${ReedEvaluation.gradeForScore(avgScore)})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kStatusSuccess,
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

class _HallOfFameEntry {
  const _HallOfFameEntry({required this.reed, required this.cane});

  final ReedEvaluation reed;
  final CaneSample cane;
}

class _GoldStandardHallOfFameCard extends StatelessWidget {
  const _GoldStandardHallOfFameCard({required this.entries});

  final List<_HallOfFameEntry> entries;

  String _bestTraits(ReedEvaluation reed) {
    final traits = <MapEntry<String, int>>[
      MapEntry('Response', reed.response),
      MapEntry('Stability', reed.stability),
      MapEntry('Tone', reed.tone),
      MapEntry('Intonation', reed.intonation),
      MapEntry('Flexibility', reed.flexibility),
      MapEntry('Projection', reed.projection),
      MapEntry('Resistance', reed.resistance),
    ]..sort((a, b) => b.value.compareTo(a.value));

    return traits.take(2).map((item) => '${item.key} ${item.value}/10').join('  •  ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;
    final badgeBg = isDark
      ? const Color(0xFFB8842B).withValues(alpha: 0.78)
      : const Color(0xFFE2B24A).withValues(alpha: 0.24);
    final badgeTextColor = isDark ? const Color(0xFFFFF4D7) : const Color(0xFF5B3A00);
    final badgeBorder = isDark
      ? const Color(0xFFF5D67A).withValues(alpha: 0.65)
      : const Color(0xFFB8842B).withValues(alpha: 0.45);

    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF5D67A).withValues(alpha: 0.26),
              theme.colorScheme.surface.withValues(alpha: 0.96),
              const Color(0xFFE2B24A).withValues(alpha: 0.18),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events_rounded, color: Color(0xFFE2B24A), size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Gold Standard Hall of Fame',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Text(
                    'Top ${entries.length}/10 all-time',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: badgeTextColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Highest-scoring reeds ever marked as Gold Standard, with their strongest metrics and cane fingerprints.',
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: onSurface.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                'No Gold Standard reeds yet. Mark a top reed as Gold Standard to populate the Hall of Fame.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withValues(alpha: 0.72),
                ),
              )
            else
              ...entries.asMap().entries.map((item) {
                final rank = item.key + 1;
                final entry = item.value;
                final score = entry.reed.overallScore;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFB8842B).withValues(alpha: 0.36)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFF5D67A), Color(0xFFB8842B)],
                          ),
                          border: Border.all(color: const Color(0xFF8B6420).withValues(alpha: 0.7)),
                        ),
                        child: Text(
                          '$rank',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: Color(0xFF2F1E00),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.cane.sampleName} · ${entry.cane.purchaseVintageLabel}',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Score ${score.toStringAsFixed(2)}/10 (${ReedEvaluation.gradeForScore(score)})   ·   ${entry.cane.naturalFrequencyHz.toStringAsFixed(0)} Hz   ·   ${entry.cane.flexibilityDeg.toStringAsFixed(1)} deg',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: onSurface.withValues(alpha: 0.82),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Best stats: ${_bestTraits(entry.reed)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: onSurface.withValues(alpha: 0.72),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
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
  Set<String> _selectedGraphEvaluationIds = const <String>{};
  bool _showRecommendedTargetInfo = false;

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
                  final scheme = Theme.of(context).colorScheme;
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
                                frameColor: scheme.surfaceContainerHigh,
                                plotTintColor: scheme.onSurface.withValues(alpha: 0.08),
                                axisColor: scheme.onSurface,
                                labelColor: scheme.onSurface,
                                selectedEvaluationIds: _selectedGraphEvaluationIds,
                                showRecommendedTargetInfo: _showRecommendedTargetInfo,
                                lightweightRendering: _graphZoom != 1 ||
                                    _graphPan.dx.abs() > 0.01 ||
                                    _graphPan.dy.abs() > 0.01,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: _HeatmapLegendCard(),
                          ),
                          Positioned(
                            bottom: 8,
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
                                const SizedBox(height: 6),
                                IconButton.filledTonal(
                                  tooltip: _showRecommendedTargetInfo
                                      ? 'Hide target info'
                                      : 'Show target info',
                                  onPressed: () {
                                    setState(() {
                                      _showRecommendedTargetInfo =
                                          !_showRecommendedTargetInfo;
                                    });
                                  },
                                  icon: Icon(
                                    _showRecommendedTargetInfo
                                        ? Icons.visibility_off
                                        : Icons.my_location,
                                  ),
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

  Future<void> _onGraphTap(Offset localPosition, List<_BehaviorCluster> clusters) async {
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
    final tappedCluster = nearest;

    if (tappedCluster.items.length == 1) {
      final entry = tappedCluster.items.first.entry;
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedGraphEvaluationIds = {entry.evaluation.id};
      });
      await _showGraphEntryPreview(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedGraphEvaluationIds = const <String>{};
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedGraphEvaluationIds =
          tappedCluster.items.map((item) => item.entry.evaluation.id).toSet();
    });

    final pickedEntry = await _showClusterPicker(tappedCluster);
    if (!mounted) {
      return;
    }
    if (pickedEntry != null) {
      setState(() {
        _selectedGraphEvaluationIds = {pickedEntry.evaluation.id};
      });
      await _showGraphEntryPreview(pickedEntry);
      if (!mounted) {
        return;
      }
    }
    setState(() {
      _selectedGraphEvaluationIds = const <String>{};
    });
  }

  List<_BehaviorCluster> _clusterPlottedEntries(List<_PlottedBehaviorEntry> plottedEntries) {
    if (plottedEntries.isEmpty) {
      return const [];
    }

    final mergeRadius = (22 / _graphZoom).clamp(10, 24).toDouble();
    final accumulators = <_BehaviorClusterAccumulator>[];

    for (final plotted in plottedEntries) {
      _BehaviorClusterAccumulator? nearest;
      var nearestDistance = double.infinity;
      for (final accumulator in accumulators) {
        final distance = (accumulator.center - plotted.position).distance;
        if (distance > mergeRadius || distance >= nearestDistance) {
          continue;
        }
        nearestDistance = distance;
        nearest = accumulator;
      }

      if (nearest != null) {
        nearest.add(plotted);
      } else {
        accumulators.add(_BehaviorClusterAccumulator(plotted));
      }
    }

    return accumulators
        .map((accumulator) => _BehaviorCluster(items: accumulator.items, center: accumulator.center))
        .toList();
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
                        '${entry.cane.sampleName} - ${entry.cane.purchaseVintageLabel}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                      ),
                    ),
                    if (entry.evaluation.goldStandard) ...[
                      const _GoldStandardBadge(compact: true),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: entry.success ? kStatusSuccess : kStatusDanger,
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
                Text('ARE: ${entry.cane.ari?.toStringAsFixed(1) ?? 'n/a'}'),
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

  Future<_BehaviorEntry?> _showClusterPicker(_BehaviorCluster cluster) async {
    if (!mounted) {
      return null;
    }

    return showModalBottomSheet<_BehaviorEntry>(
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
                    '${entry.cane.purchaseVintageLabel} | ${ReedEvaluation.gradeForScore(entry.score)} | ${entry.cane.naturalFrequencyHz.toStringAsFixed(1)} Hz';

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
                    title: Row(
                      children: [
                        Expanded(child: Text(entry.cane.sampleName)),
                        if (entry.evaluation.goldStandard) ...[
                          const SizedBox(width: 6),
                          const _GoldStandardBadge(compact: true, label: 'Gold'),
                        ],
                      ],
                    ),
                    subtitle: Text(subtitle),
                    trailing: Icon(
                      entry.success ? Icons.check_circle : Icons.cancel,
                      color: entry.success ? kStatusSuccess : kStatusDanger,
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop(entry);
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

class _BehaviorClusterAccumulator {
  _BehaviorClusterAccumulator(_PlottedBehaviorEntry first) {
    add(first);
  }

  final List<_PlottedBehaviorEntry> items = <_PlottedBehaviorEntry>[];
  double _sumX = 0;
  double _sumY = 0;

  void add(_PlottedBehaviorEntry item) {
    items.add(item);
    _sumX += item.position.dx;
    _sumY += item.position.dy;
  }

  Offset get center => Offset(_sumX / items.length, _sumY / items.length);
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
      plotRect: Rect.fromLTWH(74, 24, size.width - 116, size.height - 76),
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
    required this.frameColor,
    required this.plotTintColor,
    required this.axisColor,
    required this.labelColor,
    required this.selectedEvaluationIds,
    required this.showRecommendedTargetInfo,
    required this.lightweightRendering,
  });

  final _BehaviorGraphProjection projection;
  final List<_BehaviorCluster> clusters;
  final _BehaviorPoint? livePoint;
  final _ZoneModel zoneModel;
  final Color frameColor;
  final Color plotTintColor;
  final Color axisColor;
  final Color labelColor;
  final Set<String> selectedEvaluationIds;
  final bool showRecommendedTargetInfo;
  final bool lightweightRendering;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(0, 0, size.width, size.height);
    final background = Paint()..color = frameColor;
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

    // Build weighted successful anchors and create organic contour bands from
    // directional influence, producing non-circular heatmap geometry.
    final anchors = <_HeatAnchor>[];
    double weightedX = zoneCenter.dx * 3;
    double weightedY = zoneCenter.dy * 3;
    double weightedSum = 3;
    for (final cluster in clusters) {
      final successful = cluster.items.where((item) => item.entry.success).toList();
      if (successful.isEmpty) {
        continue;
      }
      final avgScore = successful
              .map((item) => item.entry.score)
              .reduce((a, b) => a + b) /
          successful.length;
      final weight = (successful.length * avgScore).clamp(1.0, 40.0);
      anchors.add(_HeatAnchor(position: cluster.center, weight: weight));
      weightedX += cluster.center.dx * weight;
      weightedY += cluster.center.dy * weight;
      weightedSum += weight;
    }

    final weightedCenter = Offset(weightedX / weightedSum, weightedY / weightedSum);
    final baseRadius = ((zoneModel.bandFrequency * xScale) +
                (zoneModel.bandFlexibility * yScale)) /
            2 *
        1.55;
    final baseRadii = _buildOrganicHeatRadii(
      center: weightedCenter,
      anchors: anchors,
      baseRadius: baseRadius.clamp(44.0, 160.0),
      sampleCount: 72,
    );

    final corePath = _buildOrganicPath(
      center: weightedCenter,
      plotRect: plotRect,
      radii: baseRadii,
      scale: 0.68,
    );
    final midPath = _buildOrganicPath(
      center: weightedCenter,
      plotRect: plotRect,
      radii: baseRadii,
      scale: 0.96,
    );
    final outerPath = _buildOrganicPath(
      center: weightedCenter,
      plotRect: plotRect,
      radii: baseRadii,
      scale: 1.24,
    );

    canvas.save();
    canvas.clipRect(plotRect);
    canvas.drawRect(plotRect, Paint()..color = plotTintColor);

    canvas.drawPath(
      outerPath,
      Paint()
        ..color = const Color(0xFFE85D4F).withValues(alpha: 0.26)
        ..maskFilter = lightweightRendering
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 3.0),
    );
    canvas.drawPath(
      midPath,
      Paint()
        ..color = const Color(0xFFF2C94C).withValues(alpha: 0.30)
        ..maskFilter = lightweightRendering
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 2.0),
    );
    canvas.drawPath(
      corePath,
      Paint()
        ..color = const Color(0xFF2E7D4F).withValues(alpha: 0.34)
        ..maskFilter = lightweightRendering
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 1.6),
    );

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(
      outerPath,
      ringPaint..color = const Color(0xFFE85D4F).withValues(alpha: 0.22),
    );
    canvas.drawPath(
      midPath,
      ringPaint..color = const Color(0xFFF2C94C).withValues(alpha: 0.24),
    );
    canvas.drawPath(
      corePath,
      ringPaint..color = const Color(0xFF2E7D4F).withValues(alpha: 0.26),
    );
    canvas.restore();

    final gridPaint = Paint()
      ..color = kSurfaceLine.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final x = plotRect.left + (plotRect.width / 4) * i;
      final y = plotRect.top + (plotRect.height / 4) * i;
      canvas.drawLine(Offset(x, plotRect.top), Offset(x, plotRect.bottom), gridPaint);
      canvas.drawLine(Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);
    }

    final axisPaint = Paint()
      ..color = axisColor.withValues(alpha: 0.82)
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
          style: TextStyle(
            color: labelColor,
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

    String formatTick(double value) {
      final rounded = value.roundToDouble();
      final isWhole = (value - rounded).abs() < 0.05;
      return isWhole ? rounded.toInt().toString() : value.toStringAsFixed(1);
    }

    const tickCount = 4;
    final tickPaint = Paint()
      ..color = axisColor.withValues(alpha: 0.82)
      ..strokeWidth = 1;

    for (int i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final x = plotRect.left + plotRect.width * t;
      final frequencyValue = projection.minFrequency +
          (projection.maxFrequency - projection.minFrequency) * t;

      canvas.drawLine(
        Offset(x, plotRect.bottom),
        Offset(x, plotRect.bottom + 4),
        tickPaint,
      );
      drawLabel(
        formatTick(frequencyValue),
        Offset(x, plotRect.bottom + 18),
        center: true,
      );
    }

    for (int i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final y = plotRect.bottom - plotRect.height * t;
      final flexibilityValue = projection.minFlexibility +
          (projection.maxFlexibility - projection.minFlexibility) * t;

      canvas.drawLine(
        Offset(plotRect.left - 4, y),
        Offset(plotRect.left, y),
        tickPaint,
      );
      drawLabel(
        formatTick(flexibilityValue),
        Offset(plotRect.left - 28, y),
        center: true,
      );
    }

    drawLabel(
      'Cane Tone (Hz)',
      Offset(plotRect.center.dx, plotRect.bottom + 36),
      center: true,
    );
    drawLabel(
      'Flexibility',
      Offset(plotRect.left - 54, plotRect.center.dy),
      center: true,
      rotation: -math.pi / 2,
    );

    canvas.save();
    canvas.clipRect(plotRect);

    for (final cluster in clusters) {
      final successCount = cluster.items.where((item) => item.entry.success).length;
      final ratio = cluster.items.isEmpty ? 0.5 : successCount / cluster.items.length;
      final color = Color.lerp(kStatusDanger, kStatusSuccess, ratio)!;
      final hasGoldStandard =
          cluster.items.any((item) => item.entry.evaluation.goldStandard);
      final isSelected = cluster.items.any(
        (item) => selectedEvaluationIds.contains(item.entry.evaluation.id),
      );

      final radius = cluster.items.length == 1
          ? 4.0
          : (6 + math.sqrt(cluster.items.length) * 2).clamp(8, 16).toDouble();

      if (isSelected) {
        canvas.drawCircle(
          cluster.center,
          radius + 13,
          Paint()
            ..color = kBrandGold.withValues(alpha: 0.42)
            ..maskFilter = lightweightRendering
                ? null
                : const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }

      // Soft drop shadow under every cluster dot for premium depth.
      canvas.drawCircle(
        cluster.center.translate(0, 1.5),
        radius + 1.5,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.18)
          ..maskFilter = lightweightRendering
              ? null
              : const MaskFilter.blur(BlurStyle.normal, 2.4),
      );

      // Gold standard halo — a blurred warm glow rendered behind the dot.
      if (hasGoldStandard) {
        canvas.drawCircle(
          cluster.center,
          radius + 9,
          Paint()
            ..color = const Color(0xFFE2B24A).withValues(alpha: 0.55)
            ..maskFilter = lightweightRendering
                ? null
                : const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }

      // The dot itself, with a vertical highlight gradient.
      final dotRect = Rect.fromCircle(center: cluster.center, radius: radius);
      canvas.drawCircle(
        cluster.center,
        radius,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(color, Colors.white, 0.35)!,
              color,
            ],
          ).createShader(dotRect),
      );

      // Crisp gold ring for Gold Standard clusters.
      if (hasGoldStandard) {
        canvas.drawCircle(
          cluster.center,
          radius + 2.5,
          Paint()
            ..color = const Color(0xFFE2B24A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
        canvas.drawCircle(
          cluster.center,
          radius + 2.5,
          Paint()
            ..color = const Color(0xFFF5D67A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }

      if (isSelected) {
        canvas.drawCircle(
          cluster.center,
          radius + 4,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }

      if (cluster.items.length > 1) {
        canvas.drawCircle(
          cluster.center,
          radius,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.95)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );

        final countTextColor = color.computeLuminance() > 0.58
            ? const Color(0xFF1A1A1A)
            : Colors.white;

        final tp = TextPainter(
          text: TextSpan(
            text: '${cluster.items.length}',
            style: TextStyle(
              color: countTextColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(
                  color: countTextColor == Colors.white
                      ? Colors.black54
                      : Colors.white70,
                  blurRadius: 2,
                ),
              ],
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
      canvas.drawCircle(project(livePoint!), 6, Paint()..color = kBrandBurgundy);
    }

    // Recommended target marker (crosshair + center point), rendered above
    // occurrences so it remains readable when points overlap the target area.
    final targetPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.82);
    canvas.drawCircle(zoneCenter, 12, targetPaint);
    canvas.drawLine(
      zoneCenter.translate(-20, 0),
      zoneCenter.translate(-7, 0),
      targetPaint,
    );
    canvas.drawLine(
      zoneCenter.translate(7, 0),
      zoneCenter.translate(20, 0),
      targetPaint,
    );
    canvas.drawLine(
      zoneCenter.translate(0, -20),
      zoneCenter.translate(0, -7),
      targetPaint,
    );
    canvas.drawLine(
      zoneCenter.translate(0, 7),
      zoneCenter.translate(0, 20),
      targetPaint,
    );
    canvas.drawCircle(
      zoneCenter,
      4.5,
      Paint()..color = const Color(0xFF2E7D4F).withValues(alpha: 0.90),
    );

    if (showRecommendedTargetInfo) {
      final callout = TextPainter(
        text: TextSpan(
          text:
              'Recommended target\n${zoneModel.centerFrequency.round()} Hz\n${zoneModel.centerFlexibility.toStringAsFixed(1)} flexibility',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 130);

      final calloutRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (zoneCenter.dx + 18).clamp(plotRect.left + 8, plotRect.right - 152),
          (zoneCenter.dy - 36).clamp(plotRect.top + 8, plotRect.bottom - 86),
          144,
          74,
        ),
        const Radius.circular(12),
      );
      canvas.drawRRect(
        calloutRect,
        Paint()..color = const Color(0xFF3F3A36).withValues(alpha: 0.76),
      );
      callout.paint(
        canvas,
        Offset(calloutRect.left + 12, calloutRect.top + 11),
      );
    }

    canvas.restore();
  }

  List<double> _buildOrganicHeatRadii({
    required Offset center,
    required List<_HeatAnchor> anchors,
    required double baseRadius,
    required int sampleCount,
  }) {
    if (anchors.isEmpty) {
      return List<double>.filled(sampleCount, baseRadius);
    }

    final radii = List<double>.filled(sampleCount, baseRadius);
    const sigma = 0.50;
    for (int i = 0; i < sampleCount; i++) {
      final theta = (2 * math.pi * i) / sampleCount;
      double radius = baseRadius;
      for (final anchor in anchors) {
        final vector = anchor.position - center;
        final dist = vector.distance;
        if (dist < 1) {
          continue;
        }
        final angle = math.atan2(vector.dy, vector.dx);
        final diff = _wrapAngle(theta - angle).abs();
        final angular = math.exp(-(diff * diff) / (2 * sigma * sigma));
        final pull = (dist * 0.72).clamp(0.0, 180.0);
        radius += angular * pull * (anchor.weight / 30);
      }
      radius *= 0.97 + 0.06 * math.sin(theta * 2.0);
      radii[i] = radius;
    }

    var smoothed = radii;
    for (int pass = 0; pass < 4; pass++) {
      final next = List<double>.filled(sampleCount, 0);
      for (int i = 0; i < sampleCount; i++) {
        final prev = smoothed[(i - 1 + sampleCount) % sampleCount];
        final curr = smoothed[i];
        final nxt = smoothed[(i + 1) % sampleCount];
        next[i] = (prev + curr * 2 + nxt) / 4;
      }
      smoothed = next;
    }
    return smoothed;
  }

  Path _buildOrganicPath({
    required Offset center,
    required Rect plotRect,
    required List<double> radii,
    required double scale,
  }) {
    final count = radii.length;
    final points = <Offset>[];
    for (int i = 0; i < count; i++) {
      final theta = (2 * math.pi * i) / count;
      final dir = Offset(math.cos(theta), math.sin(theta));
      final maxRadius = _rayToRectRadius(center, dir, plotRect) - 6;
      final radius = (radii[i] * scale).clamp(24.0, maxRadius);
      points.add(center + dir * radius);
    }

    final path = Path();
    if (points.isEmpty) {
      return path;
    }
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    final last = points.last;
    final first = points.first;
    final closingMid = Offset((last.dx + first.dx) / 2, (last.dy + first.dy) / 2);
    path.quadraticBezierTo(last.dx, last.dy, closingMid.dx, closingMid.dy);
    path.close();
    return path;
  }

  double _rayToRectRadius(Offset center, Offset dir, Rect rect) {
    final candidates = <double>[];

    if (dir.dx.abs() > 1e-6) {
      final tx1 = (rect.left - center.dx) / dir.dx;
      final y1 = center.dy + tx1 * dir.dy;
      if (tx1 > 0 && y1 >= rect.top && y1 <= rect.bottom) {
        candidates.add(tx1);
      }
      final tx2 = (rect.right - center.dx) / dir.dx;
      final y2 = center.dy + tx2 * dir.dy;
      if (tx2 > 0 && y2 >= rect.top && y2 <= rect.bottom) {
        candidates.add(tx2);
      }
    }

    if (dir.dy.abs() > 1e-6) {
      final ty1 = (rect.top - center.dy) / dir.dy;
      final x1 = center.dx + ty1 * dir.dx;
      if (ty1 > 0 && x1 >= rect.left && x1 <= rect.right) {
        candidates.add(ty1);
      }
      final ty2 = (rect.bottom - center.dy) / dir.dy;
      final x2 = center.dx + ty2 * dir.dx;
      if (ty2 > 0 && x2 >= rect.left && x2 <= rect.right) {
        candidates.add(ty2);
      }
    }

    if (candidates.isEmpty) {
      return 24;
    }
    return candidates.reduce(math.min);
  }

  double _wrapAngle(double value) {
    var v = value;
    while (v > math.pi) {
      v -= 2 * math.pi;
    }
    while (v < -math.pi) {
      v += 2 * math.pi;
    }
    return v;
  }

  @override
  bool shouldRepaint(covariant _BehaviorMapPainter oldDelegate) {
    return oldDelegate.projection != projection ||
        oldDelegate.clusters != clusters ||
        oldDelegate.livePoint != livePoint ||
        oldDelegate.zoneModel != zoneModel ||
        oldDelegate.frameColor != frameColor ||
        oldDelegate.plotTintColor != plotTintColor ||
        oldDelegate.showRecommendedTargetInfo != showRecommendedTargetInfo ||
        oldDelegate.lightweightRendering != lightweightRendering ||
        oldDelegate.selectedEvaluationIds != selectedEvaluationIds;
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
        title: 'Recommended target',
        child: Text(
          'No successful reeds yet. As soon as you log a reed with a score of 8 or higher, a weighted target profile will appear here.',
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
        _TargetRowData('ARE', p.ari!.toStringAsFixed(1)),
      if (p.buoyancy != null)
        _TargetRowData('Buoyancy', '${p.buoyancy!.toStringAsFixed(1)}%'),
    ];

    return _SectionCard(
      title: 'Recommended target',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Score-weighted target from your $successCount successful reed${successCount == 1 ? '' : 's'} (avg ${p.avgScore.toStringAsFixed(1)}/10).',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.68),
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

    final scheme = Theme.of(context).colorScheme;
    final mutedInk = scheme.onSurface.withValues(alpha: 0.65);

    return _SectionCard(
      title: 'Musical resonance window',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Centered on your highest-scoring reeds:',
            style: TextStyle(
              fontSize: 13,
              color: mutedInk,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${p.frequency.toStringAsFixed(0)} Hz',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Pitch ${pitch.label} ($centsLabel)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outline),
            ),
            child: Row(
              children: [
                Icon(Icons.unfold_more, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Observed success range: '
                    '${p.freqMin.toStringAsFixed(0)} - ${p.freqMax.toStringAsFixed(0)} Hz',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
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
              color: scheme.onSurface.withValues(alpha: 0.6),
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
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
        color: kStatusSuccessSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kStatusSuccess.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 18, color: kStatusSuccess),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: kStatusSuccess,
                    )),
                const SizedBox(height: 2),
                Text(
                  'Aim for $target  •  stay within $corridor',
                  style: const TextStyle(
                    fontSize: 13,
                    color: kBrandBurgundyDeep,
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

class _HeatAnchor {
  const _HeatAnchor({required this.position, required this.weight});

  final Offset position;
  final double weight;
}

class _HeatmapLegendCard extends StatelessWidget {
  const _HeatmapLegendCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3F3A36).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeatmapLegendRow(label: '9-10', color: Color(0xFF2E7D4F), text: 'dark green'),
          _HeatmapLegendRow(label: '7-8', color: Color(0xFF83A846), text: 'light green'),
          _HeatmapLegendRow(label: '4-6', color: Color(0xFFF2B84B), text: 'yellow'),
          _HeatmapLegendRow(label: '1-3', color: Color(0xFFE85D4F), text: 'red'),
        ],
      ),
    );
  }
}

class _HeatmapLegendRow extends StatelessWidget {
  const _HeatmapLegendRow({
    required this.label,
    required this.color,
    required this.text,
  });

  final String label;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label  $text',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
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
    return const _MetricStatus(label: 'No ARE (missing flexibility)', color: kStatusNeutral);
  }
  if (ari <= -6) {
    return const _MetricStatus(label: 'A+ Excellent', color: kStatusSuccess);
  }
  if (ari < 0) {
    return const _MetricStatus(label: 'A Very Good', color: kStatusSuccessAccent);
  }
  if (ari <= 4) {
    return const _MetricStatus(label: 'B Acceptable', color: kStatusWarning);
  }
  if (ari < 10) {
    return const _MetricStatus(label: 'C Weak Match', color: kStatusWarningAccent);
  }
  return const _MetricStatus(label: 'D Poor (+10 or more)', color: kStatusDanger);
}

_MetricStatus _buoyancyStatus(double? percent) {
  if (percent == null) {
    return const _MetricStatus(label: 'No buoyancy data', color: kStatusNeutral);
  }
  if (percent >= 81 && percent <= 85) {
    return const _MetricStatus(label: 'Excellent', color: kStatusSuccess);
  }
  if (percent >= 78 && percent <= 87) {
    return const _MetricStatus(label: 'Good', color: kStatusSuccessAccent);
  }
  if ((percent >= 74 && percent < 78) || (percent > 87 && percent <= 90)) {
    return const _MetricStatus(label: 'Borderline', color: kStatusWarning);
  }
  return const _MetricStatus(label: 'Weak Candidate', color: kStatusDanger);
}

String _combinedPredictionMessage(double ari, double buoyancyPercent) {
  final ariGood = ari < 0;
  final ariPoor = ari >= 10;
  final buoyancyGood = buoyancyPercent >= 81 && buoyancyPercent <= 85;

  if (ariPoor && !buoyancyGood) {
    return 'Weak candidate: ARE is in poor range (+10 or more) and density proxy is off target.';
  }
  if (ariPoor && buoyancyGood) {
    return 'Density is good, but ARE is in poor range (+10 or more). Proceed with caution.';
  }
  if (ariGood && buoyancyGood) {
    return 'Excellent candidate: ARE balance and density profile are both in target range.';
  }
  if (ariGood && !buoyancyGood) {
    return 'Excellent ARE balance, but density mismatch. Proceed with caution.';
  }
  if (!ariGood && buoyancyGood) {
    return 'Density is strong, but flexibility/resonance balance is weaker than target.';
  }
  return 'Both ARE and density are outside preferred range for this profile.';
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _importJsonData(context),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import JSON'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportJsonData(context),
                  icon: const Icon(Icons.download),
                  label: const Text('Export JSON'),
                ),
              ],
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

    final mixedItems = <_ReedListItem>[
      ...filteredEvaluations.map(_ReedListItem.reviewed),
      ...filteredPendingCanes.map(_ReedListItem.pending),
    ];

    int compareByDate(_ReedListItem a, _ReedListItem b, {required bool newestFirst}) {
      return newestFirst
          ? b.sortDate.compareTo(a.sortDate)
          : a.sortDate.compareTo(b.sortDate);
    }

    mixedItems.sort((a, b) {
      switch (_sortOrder) {
        case 'score_high':
          if (a.isPending != b.isPending) {
            return a.isPending ? 1 : -1;
          }
          if (a.isPending && b.isPending) {
            return compareByDate(a, b, newestFirst: true);
          }
          final scoreOrder = b.evaluation!.overallScore.compareTo(a.evaluation!.overallScore);
          if (scoreOrder != 0) {
            return scoreOrder;
          }
          return compareByDate(a, b, newestFirst: true);
        case 'score_low':
          if (a.isPending != b.isPending) {
            return a.isPending ? 1 : -1;
          }
          if (a.isPending && b.isPending) {
            return compareByDate(a, b, newestFirst: true);
          }
          final scoreOrder = a.evaluation!.overallScore.compareTo(b.evaluation!.overallScore);
          if (scoreOrder != 0) {
            return scoreOrder;
          }
          return compareByDate(a, b, newestFirst: true);
        case 'gold_first':
          if (a.isPending != b.isPending) {
            return a.isPending ? 1 : -1;
          }
          if (a.isPending && b.isPending) {
            return compareByDate(a, b, newestFirst: true);
          }
          final goldOrder = (b.evaluation!.goldStandard ? 1 : 0) -
              (a.evaluation!.goldStandard ? 1 : 0);
          if (goldOrder != 0) {
            return goldOrder;
          }
          return compareByDate(a, b, newestFirst: true);
        case 'oldest':
          return compareByDate(a, b, newestFirst: false);
        case 'newest':
        default:
          return compareByDate(a, b, newestFirst: true);
      }
    });

    final reedListWidgets = <Widget>[];
    var pendingHeaderShown = false;
    for (final item in mixedItems) {
      if (item.isPending) {
        if (!pendingHeaderShown) {
          reedListWidgets.addAll([
            const Text(
              'Pending Reviews',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
          ]);
          pendingHeaderShown = true;
        }
        reedListWidgets.add(
          _PendingReedCard(
            sample: item.pendingCane!,
            onTap: () => _openPendingStats(context, item.pendingCane!),
          ),
        );
        continue;
      }

      final evaluation = item.evaluation!;
      final cane = controller.findCane(evaluation.caneId);
      reedListWidgets.add(
        _ReedCard(
          evaluation: evaluation,
          cane: cane,
          onTap: () => _openReedStats(context, evaluation, cane),
          onEdit: () => _editReed(context, evaluation),
          onDelete: () => _deleteReed(context, evaluation),
        ),
      );
    }

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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _importJsonData(context),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import JSON'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportJsonData(context),
                  icon: const Icon(Icons.download),
                  label: const Text('Export JSON'),
                ),
              ],
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
            if (reedListWidgets.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No reeds match the current filters.'),
                ),
              )
            else
              ...reedListWidgets,
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

class _ReedListItem {
  const _ReedListItem.reviewed(this.evaluation) : pendingCane = null;
  const _ReedListItem.pending(this.pendingCane) : evaluation = null;

  final ReedEvaluation? evaluation;
  final CaneSample? pendingCane;

  bool get isPending => pendingCane != null;

  DateTime get sortDate => isPending ? pendingCane!.purchaseDate : evaluation!.createdAt;
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

  int _step = 0;

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
      _batchController.text = sample.purchaseDate.year.toString().padLeft(4, '0');
      _sourceController.text = sample.source;
      _lengthController.text = sample.lengthMm.toStringAsFixed(2);
      _widthController.text = sample.widthMm.toStringAsFixed(2);
      _thicknessController.text = sample.thicknessMm.toStringAsFixed(3);
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
    final controller = context.watch<AppController>();
    final steps = _buildSteps(controller);
    if (_step >= steps.length) {
      _step = steps.length - 1;
    }
    final current = steps[_step];
    final isLast = _step == steps.length - 1;
    final livePrediction = _draftPrediction(controller);
    final draftMetricSample = _draftMetricSample();

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Cane Sample' : 'Add Cane Sample')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Progress header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Step ${_step + 1} of ${steps.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 0.6,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      if (current.optional)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Optional', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_step + 1) / steps.length,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    current.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  if (current.helper != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      current.helper!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Step body
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Container(
                      key: ValueKey<int>(_step),
                      child: current.builder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionCard(
                    title: 'Live Prediction',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PredictionStatus(
                          missing: _missingForPrediction(),
                          result: livePrediction,
                        ),
                        if (draftMetricSample != null) ...[
                          const SizedBox(height: 10),
                          _MetricPreview(sample: draftMetricSample),
                        ],
                        if (livePrediction != null) ...[
                          const SizedBox(height: 10),
                          _PredictionSummary(result: livePrediction),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Bottom navigation bar
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  border: Border(
                    top: BorderSide(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                child: Row(
                  children: [
                    if (_step > 0)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _step--),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                      ),
                    const Spacer(),
                    if (!isLast)
                      TextButton.icon(
                        onPressed: () => setState(() => _step++),
                        icon: const Icon(Icons.skip_next, size: 18),
                        label: Text(current.optional ? 'Skip' : 'Skip for now'),
                      ),
                    const SizedBox(width: 8),
                    if (!isLast)
                      FilledButton.icon(
                        onPressed: () {
                          if (current.canAdvance == null || current.canAdvance!()) {
                            setState(() => _step++);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please complete this step or use Skip.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: Text(_isEditing ? 'Save changes' : 'Save sample'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_WizardStep> _buildSteps(AppController controller) {
    final averageTake = _resonanceTakesHz.isEmpty
        ? null
        : _resonanceTakesHz.reduce((a, b) => a + b) / _resonanceTakesHz.length;

    return [
      _WizardStep(
        title: 'Sample name',
        helper: 'Give this piece of cane a label you will recognize later.',
        builder: () => TextFormField(
          controller: _sampleNameController,
          decoration: const InputDecoration(labelText: 'Sample name / ID'),
          onChanged: (_) => setState(() {}),
        ),
        canAdvance: () => _sampleNameController.text.trim().isNotEmpty,
      ),
      _WizardStep(
        title: 'Vintage year',
        helper: 'Choose the production year/vintage for this cane.',
        builder: () => TextFormField(
          controller: _batchController,
          readOnly: true,
          decoration: const InputDecoration(labelText: 'Vintage year'),
          onTap: _pickPurchaseDate,
        ),
        canAdvance: () => _batchController.text.trim().isNotEmpty,
      ),
      _WizardStep(
        title: 'Source / Grower',
        helper: 'Where did the cane come from? Start typing to use a previous source.',
        builder: () => Autocomplete<String>(
          initialValue: TextEditingValue(text: _sourceController.text),
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.toLowerCase();
            final sources = controller.sourceHistory;
            if (query.isEmpty) return sources;
            return sources.where((source) => source.toLowerCase().contains(query));
          },
          onSelected: (value) {
            _sourceController.text = value;
            setState(() {});
          },
          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
            textEditingController.value = _sourceController.value;
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: const InputDecoration(labelText: 'Source / Grower'),
              onChanged: (value) {
                _sourceController.value = textEditingController.value;
                setState(() {});
              },
            );
          },
        ),
        canAdvance: () => _sourceController.text.trim().isNotEmpty,
      ),
      _WizardStep(
        title: 'Length (mm)',
        helper: 'Measured tip-to-tip on the gouged blank. Common standards: 120, 118, 116 mm.',
        builder: () => Column(
          children: [
            _NumberInput(
              controller: _lengthController,
              label: 'Length (mm)',
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: _presetValues(controller.lengthHistory, const [120, 118, 116]),
              onSelected: (value) {
                _lengthController.text = value.toStringAsFixed(2);
                setState(() {});
              },
            ),
          ],
        ),
        canAdvance: () => _tryParseNumber(_lengthController.text) != null,
      ),
      _WizardStep(
        title: 'Width (mm)',
        helper: 'Width at the widest point of the gouge. Common standards: 15, 16, 17, 18 mm.',
        builder: () => Column(
          children: [
            _NumberInput(
              controller: _widthController,
              label: 'Width (mm)',
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: _presetValues(controller.widthHistory, const [15, 16, 17, 18]),
              onSelected: (value) {
                _widthController.text = value.toStringAsFixed(2);
                setState(() {});
              },
            ),
          ],
        ),
        canAdvance: () => _tryParseNumber(_widthController.text) != null,
      ),
      _WizardStep(
        title: 'Thickness (mm)',
        helper: 'Caliper reading on the bark / centre of the gouge.',
        builder: () => Column(
          children: [
            _NumberInput(
              controller: _thicknessController,
              label: 'Thickness (mm)',
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.thicknessOuterHistory,
              onSelected: (value) {
                _thicknessController.text = value.toStringAsFixed(3);
                setState(() {});
              },
            ),
          ],
        ),
        canAdvance: () => _tryParseNumber(_thicknessController.text) != null,
      ),
      _WizardStep(
        title: 'Gouge style',
        helper: 'How is the inside of the cane shaped?',
        builder: () => DropdownButtonFormField<String>(
          initialValue: _innerGougeType,
          decoration: const InputDecoration(labelText: 'Gouge'),
          items: const [
            DropdownMenuItem(value: 'excentric', child: Text('Excentric')),
            DropdownMenuItem(value: 'concentric', child: Text('Concentric')),
            DropdownMenuItem(value: 'none', child: Text('None / unknown')),
          ],
          onChanged: (value) {
            setState(() {
              _innerGougeType = value ?? 'none';
            });
          },
        ),
        optional: true,
      ),
      _WizardStep(
        title: 'Applied load (g)',
        helper: 'Default 200 g matches the Lauritzen flex test.',
        builder: () => Column(
          children: [
            _NumberInput(
              controller: _loadController,
              label: 'Applied load (g)',
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.loadHistory,
              onSelected: (value) {
                _loadController.text = value.toStringAsFixed(1);
                setState(() {});
              },
            ),
          ],
        ),
        canAdvance: () => _tryParseNumber(_loadController.text) != null,
      ),
      _WizardStep(
        title: 'Flexibility / Twist (deg)',
        helper: 'Optional — skip if you don\'t measure it.',
        optional: true,
        builder: () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NumberInput(
              controller: _flexibilityController,
              label: 'Flexibility (deg)',
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
            const SizedBox(height: 12),
            const _FlexibilityHelpCard(),
          ],
        ),
      ),
      _WizardStep(
        title: 'Natural frequency (Hz)',
        helper: 'Type a value or tap the mic to record resonance takes.',
        builder: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Avg recorded: ${averageTake.toStringAsFixed(1)} Hz · score ${LauritzenToneScale.indexFromFrequency(averageTake).toStringAsFixed(1)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        canAdvance: () =>
            _tryParseNumber(_frequencyController.text) != null || _resonanceTakesHz.isNotEmpty,
      ),
      _WizardStep(
        title: 'Mass (g)',
        helper: 'Total cane weight. Skip if you do not have a scale.',
        optional: true,
        builder: () => Column(
          children: [
            _NumberInput(
              controller: _massController,
              label: 'Mass (g)',
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
          ],
        ),
      ),
      _WizardStep(
        title: 'Submerged length (mm)',
        helper: 'Buoyancy test — skip if not performed.',
        optional: true,
        builder: () => Column(
          children: [
            _NumberInput(
              controller: _submergedLengthController,
              label: 'Submerged length (mm)',
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
          ],
        ),
      ),
      _WizardStep(
        title: 'Hardness',
        helper: 'Optional indentation/scratch resistance value.',
        optional: true,
        builder: () => Column(
          children: [
            _NumberInput(
              controller: _hardnessController,
              label: 'Hardness',
              requiredField: false,
              onChanged: (_) => setState(() {}),
            ),
            _ValuePresetChips(
              values: controller.hardnessHistory,
              onSelected: (value) {
                _hardnessController.text = value.toStringAsFixed(3);
                setState(() {});
              },
            ),
          ],
        ),
      ),
      _WizardStep(
        title: 'Notes & photos',
        helper: 'Anything else worth remembering about this cane.',
        optional: true,
        builder: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          ],
        ),
      ),
      _WizardStep(
        title: 'Review & save',
        helper: 'Confirm the values below, then save the cane.',
        builder: () => _ReviewSummary(
          rows: [
            _ReviewRow('Sample', _sampleNameController.text),
            _ReviewRow('Vintage year', _batchController.text),
            _ReviewRow('Source', _sourceController.text),
            _ReviewRow('Length', _displayValue(_lengthController.text, 'mm')),
            _ReviewRow('Width', _displayValue(_widthController.text, 'mm')),
            _ReviewRow('Thickness', _displayValue(_thicknessController.text, 'mm')),
            _ReviewRow('Gouge', _innerGougeType),
            _ReviewRow('Load', _displayValue(_loadController.text, 'g')),
            _ReviewRow('Frequency', _displayValue(_frequencyController.text, 'Hz')),
            _ReviewRow('Mass', _displayValue(_massController.text, 'g')),
            _ReviewRow('Flexibility', _displayValue(_flexibilityController.text, 'deg')),
            _ReviewRow('Submerged length', _displayValue(_submergedLengthController.text, 'mm')),
            _ReviewRow('Hardness', _displayValue(_hardnessController.text, '')),
            _ReviewRow('Photos', _photoPaths.isEmpty ? '—' : '${_photoPaths.length} attached'),
            _ReviewRow('Notes', _notesController.text.trim().isEmpty ? '—' : _notesController.text.trim()),
          ],
        ),
      ),
    ];
  }

  String _displayValue(String raw, String unit) {
    final v = raw.trim();
    if (v.isEmpty) return '—';
    return unit.isEmpty ? v : '$v $unit';
  }

  List<double> _presetValues(List<double> historyValues, List<double> defaults) {
    final presets = <double>[];
    for (final value in defaults) {
      if (!presets.any((existing) => (existing - value).abs() < 0.0001)) {
        presets.add(value);
      }
    }
    for (final value in historyValues) {
      if (!presets.any((existing) => (existing - value).abs() < 0.0001)) {
        presets.add(value);
      }
    }
    return presets;
  }

  List<String> _missingForPrediction() {
    final missing = <String>[];
    if (_tryParseNumber(_lengthController.text) == null) missing.add('length');
    if (_tryParseNumber(_widthController.text) == null) missing.add('width');
    if (_tryParseNumber(_thicknessController.text) == null) missing.add('thickness');
    if (_tryParseNumber(_loadController.text) == null) missing.add('load');
    final freq = _tryParseNumber(_frequencyController.text);
    if (freq == null && _resonanceTakesHz.isEmpty) missing.add('frequency');
    return missing;
  }

  PredictionResult? _draftPrediction(AppController controller) {
    final length = _tryParseNumber(_lengthController.text);
    final width = _tryParseNumber(_widthController.text);
    final thickness = _tryParseNumber(_thicknessController.text);
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
    final thicknessReadings = [thickness!];

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
      initialDatePickerMode: DatePickerMode.year,
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _purchaseDate = DateTime(selected.year, 1, 1);
      _batchController.text = selected.year.toString().padLeft(4, '0');
    });
  }

  Future<void> _openFrequencyRecorder() async {
    final result = await showModalBottomSheet<_FrequencyCaptureResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
    final massG = _tryParseNumber(_massController.text) ?? 0;
    final flexibilityDeg = _tryParseNumber(_flexibilityController.text) ?? 0;
    final loadG = _tryParseNumber(_loadController.text)!;
    final submergedLengthMm = _tryParseNumber(_submergedLengthController.text);
    final thicknessReadingsMm = [thicknessMm];
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
                      child: Text('${sample.sampleName} - ${sample.purchaseVintageLabel}'),
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
  final List<List<ResonanceCandidate>> _takeCandidates = [];
  int? _selectedIndex;
  bool _isRecording = false;
  bool _isAuditioning = false;
  double _lastDragHz = 1200;
  StreamSubscription<LiveCaptureFrame>? _liveSub;
  LiveCaptureFrame? _liveFrame;
  double _sliderHz = 1200;

  @override
  void initState() {
    super.initState();
    _takes = [...widget.initialTakes];
    for (int i = 0; i < _takes.length; i++) {
      _takeConfidences.add(0); // unknown confidence for pre-existing takes
      _takeCandidates.add(const []);
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
    _lastDragHz = clamped;
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

  List<_PrevalentFrequency> get _prevalentCandidates {
    if (_takes.isEmpty) {
      return const [];
    }

    final clusters = <_PrevalenceAccumulator>[];
    const clusterToleranceHz = 12.0;

    for (int takeIndex = 0; takeIndex < _takes.length; takeIndex++) {
      final takeConfidence =
          _takeConfidences.length > takeIndex ? _takeConfidences[takeIndex] : 0.0;
      final baselineWeight = math.max(0.25, takeConfidence);

      final ranked = (_takeCandidates.length > takeIndex &&
              _takeCandidates[takeIndex].isNotEmpty)
          ? _takeCandidates[takeIndex].take(5).toList()
          : [
              ResonanceCandidate(
                hz: _takes[takeIndex],
                score: baselineWeight,
                label: 'legacy',
              ),
            ];

      for (int rank = 0; rank < ranked.length; rank++) {
        final candidate = ranked[rank];
        final rankWeight = math.max(0.35, 1.0 - (rank * 0.12));
        final weight = math.max(0.10, candidate.score) * rankWeight;

        _PrevalenceAccumulator? nearest;
        double nearestDistance = double.infinity;
        for (final cluster in clusters) {
          final distance = (cluster.centerHz - candidate.hz).abs();
          if (distance <= clusterToleranceHz && distance < nearestDistance) {
            nearest = cluster;
            nearestDistance = distance;
          }
        }

        if (nearest == null) {
          final cluster = _PrevalenceAccumulator();
          cluster.add(candidate.hz, weight, takeIndex);
          clusters.add(cluster);
        } else {
          nearest.add(candidate.hz, weight, takeIndex);
        }
      }
    }

    final maxWeight = clusters.fold<double>(
      0,
      (current, cluster) => math.max(current, cluster.totalWeight),
    );
    final safeMax = maxWeight <= 1e-9 ? 1.0 : maxWeight;

    final prevalent = clusters.map((cluster) {
      return _PrevalentFrequency(
        hz: cluster.centerHz,
        score: (cluster.totalWeight / safeMax).clamp(0.0, 1.0),
        supportTakes: cluster.supportTakeCount,
      );
    }).toList();

    prevalent.sort((a, b) {
      final bySupport = b.supportTakes.compareTo(a.supportTakes);
      if (bySupport != 0) {
        return bySupport;
      }
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return a.hz.compareTo(b.hz);
    });

    return prevalent.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final manualValue = _tryParseNumber(_manualController.text);
    final heardHz = _isAuditioning
        ? _sliderHz
        : (manualValue != null && manualValue > 0 ? manualValue : _sliderHz);
    final selectedPitch = heardHz > 0 ? _pitchFromFrequency(heardHz) : null;
    final selectedPointScore = heardHz > 0
        ? LauritzenToneScale.continuousIndexFromFrequency(heardHz)
        : null;
    final roundedPointScore = heardHz > 0
        ? LauritzenToneScale.indexFromFrequency(heardHz)
        : null;

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
                idleSurface: scheme.surfaceContainerHigh,
                idleBorder: scheme.outline,
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
                  painter: _TakeBarsPainter(
                    values: _takes,
                    selectedIndex: _selectedIndex,
                    backgroundColor: scheme.surfaceContainerHigh,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 10),
              _AccuracySummary(
                count: _takes.length,
                mean: _mean,
                stddev: _stddev,
                confidencePercent: _confidencePercent,
                surfaceColor: scheme.surfaceContainerHigh,
                borderColor: scheme.outline,
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
                      color: isSelected
                          ? scheme.secondaryContainer.withValues(alpha: 0.72)
                          : null,
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
                                  if (_takeCandidates.length > index) {
                                    _takeCandidates.removeAt(index);
                                  }
                                  if (_selectedIndex == index) {
                                    _selectedIndex = _takes.isEmpty ? null : _takes.length - 1;
                                    final prevalent = _prevalentCandidates;
                                    if (prevalent.isNotEmpty) {
                                      _setManual(prevalent.first.hz);
                                    } else if (_selectedIndex != null) {
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
                'Most likely natural frequencies',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              if (_prevalentCandidates.isEmpty)
                const Text(
                  'Record at least one take to generate ranked suggestions.',
                  style: TextStyle(fontSize: 12),
                )
              else
                Column(
                  children: List.generate(_prevalentCandidates.length, (index) {
                    final candidate = _prevalentCandidates[index];
                    final selected = manualValue != null &&
                        (manualValue - candidate.hz).abs() <= 0.6;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      color: selected
                          ? scheme.secondaryContainer.withValues(alpha: 0.72)
                          : null,
                      child: ListTile(
                        dense: true,
                        title: Text(
                          'Likely #${index + 1}: ${candidate.hz.toStringAsFixed(1)} Hz',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Support ${candidate.supportTakes}/${_takes.length} takes | strength ${(candidate.score * 100).toStringAsFixed(0)}%',
                        ),
                        leading: IconButton(
                          icon: const Icon(Icons.play_circle_outline),
                          tooltip: 'Play candidate',
                          onPressed: () => _service.playTone(candidate.hz),
                        ),
                        trailing: IconButton(
                          icon: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked),
                          tooltip: 'Use this frequency',
                          onPressed: () {
                            setState(() {
                              _setManual(candidate.hz);
                            });
                          },
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
                        setState(() {
                          _isAuditioning = true;
                          _lastDragHz = value;
                          _sliderHz = value;
                          _manualController.text = value.toStringAsFixed(1);
                        });
                        _service.auditionToneHz(value);
                      },
                      onChanged: (value) {
                        setState(() {
                          _isAuditioning = true;
                          _lastDragHz = value;
                          _sliderHz = value;
                          _manualController.text = value.toStringAsFixed(1);
                        });
                        _service.auditionToneHz(value);
                      },
                      onChangeEnd: (_) {
                        // Use _lastDragHz from onChanged — not the pointer-up
                        // value, which can contain micro-movement jitter.
                        setState(() {
                          _isAuditioning = false;
                          _sliderHz = _lastDragHz;
                          _manualController.text = _lastDragHz.toStringAsFixed(1);
                        });
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
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isAuditioning
                      ? kStatusWarningSoft
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isAuditioning ? kStatusWarningAccent : scheme.outline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (context) {
                        final panelBg = _isAuditioning
                            ? kStatusWarningSoft
                            : scheme.surfaceContainerHigh;
                        final panelText = panelBg.computeLuminance() > 0.56
                            ? Colors.black.withValues(alpha: 0.88)
                            : scheme.onSurface;
                        final panelMuted = panelBg.computeLuminance() > 0.56
                            ? Colors.black.withValues(alpha: 0.70)
                            : scheme.onSurface.withValues(alpha: 0.78);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    Row(
                      children: [
                        Icon(
                          _isAuditioning ? Icons.graphic_eq : Icons.music_note,
                          size: 18,
                          color: _isAuditioning ? kBrandBurgundy : kStatusNeutral,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isAuditioning ? 'Hearing now' : 'Selected tone',
                          style: TextStyle(fontWeight: FontWeight.w700, color: panelText),
                        ),
                        const Spacer(),
                        Text(
                          '${heardHz.toStringAsFixed(1)} Hz',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: panelText,
                          ),
                        ),
                      ],
                    ),
                    if (selectedPitch != null &&
                        selectedPointScore != null &&
                        roundedPointScore != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tone ${selectedPitch.label} (${selectedPitch.cents >= 0 ? '+' : ''}${selectedPitch.cents} cents)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: panelText,
                        ),
                      ),
                      Text(
                        'Score ${selectedPointScore.toStringAsFixed(2)} exact (${roundedPointScore.toStringAsFixed(0)} rounded)',
                        style: TextStyle(
                          fontSize: 12,
                          color: panelMuted,
                        ),
                      ),
                    ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const Text(
                'Fine-tune frequency',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final step in [-10, -5, -1, 1, 5, 10])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          final current = _tryParseNumber(_manualController.text) ?? _sliderHz;
                          final next = (current + step).clamp(_minHz, _maxHz);
                          setState(() {
                            _sliderHz = next;
                            _lastDragHz = next;
                            _manualController.text = next.toStringAsFixed(1);
                          });
                        },
                        child: Text(
                          '${step > 0 ? '+' : ''}$step',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _NumberInput(
                controller: _manualController,
                label: 'Frequency (Hz)',
                requiredField: false,
                onChanged: (text) {
                  final parsed = _tryParseNumber(text);
                  if (parsed != null) {
                    setState(() {
                      _sliderHz = parsed.clamp(_minHz, _maxHz);
                      _lastDragHz = _sliderHz;
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
        _takeCandidates.add(result.candidates);
        _selectedIndex = _takes.length - 1;
        final prevalent = _prevalentCandidates;
        if (prevalent.isNotEmpty) {
          _setManual(prevalent.first.hz);
        } else {
          _setManual(result.hz);
        }
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

class _PrevalenceAccumulator {
  double weightedHz = 0;
  double totalWeight = 0;
  final Set<int> supportingTakes = <int>{};

  void add(double hz, double weight, int takeIndex) {
    weightedHz += hz * weight;
    totalWeight += weight;
    supportingTakes.add(takeIndex);
  }

  double get centerHz {
    if (totalWeight <= 1e-9) {
      return 0;
    }
    return weightedHz / totalWeight;
  }

  int get supportTakeCount => supportingTakes.length;
}

class _PrevalentFrequency {
  const _PrevalentFrequency({
    required this.hz,
    required this.score,
    required this.supportTakes,
  });

  final double hz;
  final double score;
  final int supportTakes;
}

class _LiveCapturePanel extends StatelessWidget {
  const _LiveCapturePanel({
    required this.isRecording,
    required this.frame,
    required this.idleSurface,
    required this.idleBorder,
  });

  final bool isRecording;
  final LiveCaptureFrame? frame;
  final Color idleSurface;
  final Color idleBorder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final levelDb = frame?.levelDb ?? -80;
    final levelNorm = ((levelDb + 60) / 60).clamp(0.0, 1.0);
    final estimate = frame?.estimateHz;
    final correlation = frame?.correlation;
    final panelBg = isRecording ? kStatusWarningSoft : idleSurface;
    final panelText = panelBg.computeLuminance() > 0.56
        ? Colors.black.withValues(alpha: 0.88)
        : scheme.onSurface;
    final panelMuted = panelBg.computeLuminance() > 0.56
        ? Colors.black.withValues(alpha: 0.70)
        : scheme.onSurface.withValues(alpha: 0.78);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRecording ? kStatusWarningAccent : idleBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRecording ? Icons.mic : Icons.mic_off,
                color: isRecording ? kBrandBurgundy : panelMuted,
              ),
              const SizedBox(width: 8),
              Text(
                isRecording ? 'Listening...' : 'Mic idle',
                style: TextStyle(fontWeight: FontWeight.w700, color: panelText),
              ),
              const Spacer(),
              if (frame != null)
                Text(
                  '${frame!.elapsed.inSeconds}.${(frame!.elapsed.inMilliseconds % 1000) ~/ 100}s',
                  style: TextStyle(color: panelMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: levelNorm,
              minHeight: 8,
              backgroundColor: kSurfaceLine,
              valueColor: AlwaysStoppedAnimation(
                levelNorm > 0.7
                    ? kStatusDangerAccent
                    : (levelNorm > 0.25 ? kStatusSuccessAccent : kBrandCane),
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
            style: TextStyle(fontSize: 12, color: panelText),
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
    required this.surfaceColor,
    required this.borderColor,
  });

  final int count;
  final double mean;
  final double stddev;
  final double confidencePercent;
  final Color surfaceColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final color = confidencePercent >= 75
        ? kStatusSuccessAccent
        : (confidencePercent >= 45 ? kStatusWarningAccent : kStatusDangerAccent);
    final tip = count == 0
        ? 'Record one or more takes to start building confidence.'
        : count == 1
            ? 'Add another take to verify – more samples raise confidence.'
            : 'Mean ${mean.toStringAsFixed(1)} Hz +/- ${stddev.toStringAsFixed(1)} Hz across $count takes.';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
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
  const _TakeBarsPainter({
    required this.values,
    required this.selectedIndex,
    required this.backgroundColor,
  });

  final List<double> values;
  final int? selectedIndex;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = backgroundColor;
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

      final paint = Paint()..color = selected ? kBrandBurgundy : kBrandCane;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barWidth, h), const Radius.circular(6)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TakeBarsPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.backgroundColor != backgroundColor;
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
          'ACCEPTABLE REED ESTIMATE (ARE)',
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
        Text('Reference ARE: ${result.referenceAverages['ari']?.toStringAsFixed(1) ?? 'n/a'}'),
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
          'Live ARE Preview',
          style: TextStyle(fontWeight: FontWeight.w700, color: ariStatus.color),
        ),
        const SizedBox(height: 4),
        Text(
          ari == null ? 'ARE: add flexibility and frequency' : 'ARE: ${ari.toStringAsFixed(0)} (${ariStatus.label})',
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
                    '${sample.sampleName} - ${sample.purchaseVintageLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
                if (isReviewed != null)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isReviewed! ? kStatusSuccess : kStatusWarning,
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
            Text('Size ${sample.lengthMm.toStringAsFixed(1)} × ${sample.widthMm.toStringAsFixed(1)} mm'),
            Text('ARE ${sample.ari?.toStringAsFixed(1) ?? 'n/a'} (${_ariStatus(sample.ari).label})'),
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
                    cane == null ? 'Unknown cane sample' : '${cane!.sampleName} - ${cane!.purchaseVintageLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
                if (evaluation.goldStandard)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: _GoldStandardBadge(),
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
            if (cane != null)
              Text('ARE ${cane!.ari?.toStringAsFixed(1) ?? 'n/a'} (${_ariStatus(cane!.ari).label})'),
            const SizedBox(height: 4),
            const Text('Tap for full reed and cane stats', style: TextStyle(fontSize: 12)),
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
                const Icon(Icons.schedule, color: kStatusWarning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${sample.sampleName} - ${sample.purchaseVintageLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: kStatusWarning,
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
            Text('Size ${sample.lengthMm.toStringAsFixed(1)} × ${sample.widthMm.toStringAsFixed(1)} mm'),
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
        subtitle: Text('${sample.sampleName} - ${sample.purchaseVintageLabel}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Source: ${sample.source}'),
          Text('L/W/T ${sample.lengthMm.toStringAsFixed(2)}/${sample.widthMm.toStringAsFixed(2)}/${sample.thicknessMm.toStringAsFixed(3)} mm'),
          Text(sample.flexibilityDeg > 0
              ? 'Flex ${sample.flexibilityDeg.toStringAsFixed(1)} deg at ${sample.loadG.toStringAsFixed(1)} g | Stiffness ${sample.relativeStiffness.toStringAsFixed(2)}'
              : 'Flexibility test not recorded'),
          Text('Resonance ${sample.naturalFrequencyHz.toStringAsFixed(1)} Hz | Eigenfrequency score ${sample.eigenfrequencyScore.toStringAsFixed(1)}'),
          Text('ARE ${sample.ari?.toStringAsFixed(1) ?? 'n/a'} (${_ariStatus(sample.ari).label})'),
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
    return kStatusSuccess;
  }
  if (score >= 7.5) {
    return kStatusSuccessAccent;
  }
  if (score >= 6.0) {
    return kStatusWarning;
  }
  if (score >= 4.5) {
    return kStatusWarningAccent;
  }
  return kStatusDanger;
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
  final yearOnly = int.tryParse(trimmed);
  if (yearOnly != null && yearOnly >= 1) {
    return DateTime(yearOnly, 1, 1);
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

Future<void> _importJsonData(BuildContext context) async {
  final mode = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Import Data'),
        content: const Text(
          'Choose how the JSON data should be applied.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Merge'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Replace all'),
          ),
        ],
      );
    },
  );

  if (mode == null || !context.mounted) {
    return;
  }

  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !context.mounted) {
      return;
    }

    final file = picked.files.single;
    final content = await _readPickedFileAsString(file);
    if (content == null || !context.mounted) {
      return;
    }

    final result = await context.read<AppController>().importDatabaseJson(
      content,
      merge: mode,
    );
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported data: ${result.caneCount} canes, ${result.reedCount} reeds.',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Import failed: $error')),
    );
  }
}

Future<void> _exportJsonData(BuildContext context) async {
  final controller = context.read<AppController>();
  final json = controller.exportDatabaseJson(pretty: true);
  final timestamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final fileName = 'reedlab_export_$timestamp.json';

  try {
    final target = await FilePicker.saveFile(
      dialogTitle: 'Export ReedLab data',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(json)),
    );

    if (kIsWeb) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export started in browser download flow.')),
      );
      return;
    }

    if (target == null || target.trim().isEmpty) {
      return;
    }

    await File(target).writeAsString(json, flush: true);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported data file: $target')),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export fallback'),
          content: const Text(
            'Could not open the file-save dialog. Data was copied to clipboard instead.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    await Clipboard.setData(ClipboardData(text: json));
  }
}

Future<String?> _readPickedFileAsString(PlatformFile file) async {
  if (file.bytes != null) {
    return utf8.decode(file.bytes!);
  }
  final path = file.path;
  if (path == null || path.isEmpty) {
    return null;
  }
  return File(path).readAsString();
}

// ---------------------------------------------------------------------------
// Branding & wizard helpers
// ---------------------------------------------------------------------------

/// Explainer + external link shown under the Flexibility wizard step.
///
/// Flexibility is the deflection-under-load reading produced by a Lauritzen-
/// style flex meter. New users often have not encountered the device, so we
/// link to a demonstration video and make clear ReedLab is not affiliated.
class _FlexibilityHelpCard extends StatelessWidget {
  const _FlexibilityHelpCard();

  static final Uri _videoUri =
      Uri.parse('https://www.youtube.com/watch?v=8QEzAyQ4PGc');

  Future<void> _open(BuildContext context) async {
    final ok = await launchUrl(_videoUri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${_videoUri.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'What is flexibility?',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Flexibility is how many degrees a tube of cane twists under a '
            'known load on a Lauritzen-style flex meter. Bigger angle = '
            'softer / more flexible cane.',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _open(context),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('Watch a demonstration on YouTube'),
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ReedLab is not affiliated with or endorsed by the makers of any '
            'flex-measurement device. The app simply uses the data such a tool '
            'provides to help guide your reed-making process.',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.65),
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandLogoMark extends StatelessWidget {
  const _BrandLogoMark({this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Image.asset(
        'assets/logo.png',
        height: size,
        width: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          height: size,
          width: size,
          color: kBrandBurgundy,
          alignment: Alignment.center,
          child: const Icon(Icons.music_note, color: kBrandGoldLight, size: 18),
        ),
      ),
    );
  }
}

/// Decorative gold "ReedLab" wordmark used on the Home screen and About card.
///
/// Falls back to a stylised text wordmark if the bundled asset is missing,
/// so the app remains presentable until the artwork is dropped in place.
class _HomeWordmarkHeader extends StatelessWidget {
  const _HomeWordmarkHeader({this.maxHeight = 64});

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 280),
          child: Image.asset(
            'assets/reedlab_wordmark.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _WordmarkFallback(
              height: maxHeight,
            ),
          ),
        ),
      ),
    );
  }
}

class _WordmarkFallback extends StatelessWidget {
  const _WordmarkFallback({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            colors: [
              Color(0xFFF5D67A),
              Color(0xFFE2B24A),
              Color(0xFFB8842B),
              Color(0xFFE2B24A),
              Color(0xFFF5D67A),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
          child: Text(
            'ReedLab',
            style: TextStyle(
              color: Colors.white,
              fontSize: height * 0.55,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              fontStyle: FontStyle.italic,
              shadows: const [
                Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WizardStep {
  _WizardStep({
    required this.title,
    required this.builder,
    this.helper,
    this.optional = false,
    this.canAdvance,
  });

  final String title;
  final String? helper;
  final Widget Function() builder;
  final bool optional;
  final bool Function()? canAdvance;
}

class _PredictionStatus extends StatelessWidget {
  const _PredictionStatus({required this.missing, required this.result});

  final List<String> missing;
  final PredictionResult? result;

  @override
  Widget build(BuildContext context) {
    if (missing.isEmpty && result != null) {
      return Row(
        children: const [
          Icon(Icons.check_circle, color: kStatusSuccess, size: 18),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Prediction ready — see details below.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }
    if (missing.isNotEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_bottom, color: kBrandGold, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Waiting on ${missing.length} input${missing.length == 1 ? '' : 's'}: ${missing.join(', ')}.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }
    return const Text(
      'Live prediction will appear as you enter data.',
      style: TextStyle(fontWeight: FontWeight.w600),
    );
  }
}

class _ReviewRow {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String value;
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.rows});
  final List<_ReviewRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    row.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Expanded(child: Text(row.value)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.onStartTour});

  final VoidCallback onStartTour;

  Future<void> _confirmDeleteFullHistory(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete full history?'),
          content: const Text(
            'This will permanently delete all registered cane samples and reed evaluations from this device.\n\n'
            'Before deleting, go to the Reeds tab and export a JSON backup so your data can be restored later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kStatusDanger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete all data'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !context.mounted) {
      return;
    }

    await context.read<AppController>().deleteAllHistory();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'All cane and reed history deleted. Tip: use Reeds tab export before future resets.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const _HomeWordmarkHeader(maxHeight: 56),
        const SizedBox(height: 8),
        const _PhilosophyHeader(),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'About ReedLab',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'ReedLab is a measurement journal for bassoon reed makers. Track each piece '
                  'of cane from purchase through every reed it becomes, capture the physical '
                  'fingerprint of your best players, and use that profile to choose future '
                  'cane with confidence.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'All data lives locally in your browser or device. Use the Reeds tab to '
                  'export or import a JSON backup.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onStartTour,
                  icon: const Icon(Icons.tour),
                  label: const Text('Take tour'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.science_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Understanding ARE',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'ARE stands for Acceptable Reed Estimate — a single number that '
                  'combines a cane\'s stiffness with its tapped pitch so you can compare '
                  'pieces on one axis instead of two.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 12),
                _AriFormulaBlock(
                  primary: theme.colorScheme.primary,
                  onSurface: theme.colorScheme.onSurface,
                  surface: theme.colorScheme.surfaceContainerHigh,
                  outline: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'Flexibility is measured in degrees of deflection under a known load. '
                  'Tone index is a Lauritzen scale (0–36) where the tapped pitch G♯ is 0 '
                  '(highest, densest cane) and B is 36 (lowest, softest cane).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Philosophy',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The premise is simple: a cane\'s tonality (its tapped pitch) and its '
                  'flexibility together describe how the material will behave once it '
                  'becomes a reed. Combining the two into a single index lets you '
                  'predict a piece of cane\'s suitability for a great reed before you '
                  'invest the hours of scraping. By judging cane with ARE up front, the '
                  'bassoonist hopes to cut down on unsuccessful reeds — and the time, '
                  'money and frustration they cost.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 14),
                Text(
                  'How ReedLab grades it',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                _AriBandLegend(theme: theme),
                const SizedBox(height: 12),
                Text(
                  'These bands are a starting point — the Behavior tab learns your own '
                  'sweet spot from the reeds you flag as successful, and the green zone '
                  'on the behavior map shows the ARE/flexibility neighbourhood your best '
                  'reeds cluster in.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Appearance',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose the visual theme that frames your reed-making notes. '
                  'Switching themes restyles the navigation, cards, buttons and dialogs.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
                const SizedBox(height: 14),
                ...AppThemeVariant.values.map((variant) {
                  final selected = controller.variant == variant;
                  return _ThemeOptionTile(
                    variant: variant,
                    selected: selected,
                    onTap: () => controller.setVariant(variant),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: kStatusDanger.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.delete_forever, color: theme.colorScheme.error),
                    const SizedBox(width: 10),
                    Text(
                      'Danger zone',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Delete full local history (all cane + reed instances). This action cannot be undone.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
                const SizedBox(height: 8),
                Text(
                  'Backup tip: export JSON from the Reeds tab before deleting.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _confirmDeleteFullHistory(context),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete full history'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AriFormulaBlock extends StatelessWidget {
  const _AriFormulaBlock({
    required this.primary,
    required this.onSurface,
    required this.surface,
    required this.outline,
  });
  final Color primary;
  final Color onSurface;
  final Color surface;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ARE = flexibility (°)  −  tone index (Lauritzen 0–36)',
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: primary,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Lower (more negative) ARE = stiffer cane for its pitch — generally better.',
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.75),
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AriBandLegend extends StatelessWidget {
  const _AriBandLegend({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final rows = const [
      ('ARE ≤ −6', 'A+ Excellent', kStatusSuccess),
      ('−6 < ARE < 0', 'A  Very Good', kStatusSuccessAccent),
      ('0 ≤ ARE ≤ 4', 'B  Acceptable', kStatusWarning),
      ('4 < ARE < 10', 'C  Weak match', kStatusWarningAccent),
      ('ARE ≥ 10', 'D  Poor', kStatusDanger),
    ];
    return Column(
      children: rows.map((r) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: r.$3,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: Text(
                  r.$1,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  r.$2,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: r.$3,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final AppThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swatch = _swatchFor(variant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: selected ? 1.6 : 1,
            ),
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              _SwatchStrip(colors: swatch),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      variant.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _swatchFor(AppThemeVariant variant) {
    switch (variant) {
      case AppThemeVariant.classic:
        return const [Color(0xFF5C1A1B), Color(0xFFC9A24A), Color(0xFFFAF3E7)];
      case AppThemeVariant.dark:
        return const [Color(0xFF1B1418), Color(0xFFD9B26A), Color(0xFF9C4A4C)];
      case AppThemeVariant.enchantedForest:
        return const [Color(0xFF2F4A30), Color(0xFFB8842B), Color(0xFFEFEAD6)];
      case AppThemeVariant.rococo:
        return const [Color(0xFF8E3A66), Color(0xFFB89858), Color(0xFFFCEFEF)];
    }
  }
}

class _SwatchStrip extends StatelessWidget {
  const _SwatchStrip({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 46,
        height: 32,
        child: Row(
          children: colors
              .map((c) => Expanded(child: Container(color: c)))
              .toList(),
        ),
      ),
    );
  }
}

/// Recognisable accolade badge shown wherever a Gold Standard reed is surfaced.
///
/// The badge intentionally renders with its own gold gradient and dark
/// burgundy text regardless of the surrounding theme so the accolade reads
/// consistently across Classic, Midnight, Forest and Rococo modes.
class _GoldStandardBadge extends StatelessWidget {
  const _GoldStandardBadge({this.compact = false, this.label = 'Gold Standard'});
  /// Compact variant: just the star + short label, smaller padding.
  final bool compact;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? 10.0 : 11.5;
    final iconSize = compact ? 12.0 : 14.0;
    final padH = compact ? 7.0 : 10.0;
    final padV = compact ? 3.0 : 4.5;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF5D67A), // pale highlight
            Color(0xFFE2B24A), // body gold
            Color(0xFFB8842B), // burnished edge
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: const Color(0xFF8B6420).withValues(alpha: 0.55),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8842B).withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: iconSize,
            color: const Color(0xFF3A1F08),
          ),
          SizedBox(width: compact ? 3 : 5),
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF3A1F08),
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              letterSpacing: compact ? 0.2 : 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashboard summary pill highlighting how many reeds in the current window
/// achieved Gold Standard status.
class _GoldStandardSummary extends StatelessWidget {
  const _GoldStandardSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFF1C8).withValues(alpha: 0.55),
            const Color(0xFFE8C977).withValues(alpha: 0.35),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFB8842B).withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const _GoldStandardBadge(compact: true, label: 'Gold'),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$count Gold Standard reed${count == 1 ? '' : 's'} in this window',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3A1F08),
              ),
            ),
          ),
          Icon(Icons.workspace_premium_rounded,
              color: const Color(0xFF8B6420).withValues(alpha: 0.85)),
        ],
      ),
    );
  }
}
