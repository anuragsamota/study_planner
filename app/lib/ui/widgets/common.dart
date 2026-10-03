import 'package:flutter/material.dart';

/// Breakpoints (Material 3 window size classes).
enum WindowSize { compact, medium, expanded }

WindowSize windowSize(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return WindowSize.compact;
  if (w < 1100) return WindowSize.medium;
  return WindowSize.expanded;
}

/// Time-of-day periods used by the planner, with icons.
const studyPeriods = <(String, String, IconData)>[
  ('morning', 'Morning', Icons.wb_twilight),
  ('afternoon', 'Afternoon', Icons.wb_sunny_outlined),
  ('evening', 'Evening', Icons.brightness_4_outlined),
  ('night', 'Night', Icons.bedtime_outlined),
];

const subjectPalette = <int>[
  0xFF4F6BED, 0xFFE5484D, 0xFF30A46C, 0xFFF76B15, 0xFF8E4EC6,
  0xFF0090FF, 0xFFD6409F, 0xFF12A594, 0xFFAB6400, 0xFF6E56CF,
];

/// Scrollable page content, centred with a comfortable max width.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1100, this.padBottom = 96});
  final List<Widget> children;
  final double maxWidth;
  final double padBottom;

  @override
  Widget build(BuildContext context) {
    final pad = windowSize(context) == WindowSize.compact ? 16.0 : 24.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, padBottom),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

/// Lays children in a responsive grid: 1 column on phones, 2 on wider screens.
class ResponsiveColumns extends StatelessWidget {
  const ResponsiveColumns({super.key, required this.children, this.spacing = 16, this.minColumnWidth = 380});
  final List<Widget> children;
  final double spacing;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minColumnWidth).floor().clamp(1, 2);
      if (cols == 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final w in children) Padding(padding: EdgeInsets.only(bottom: spacing), child: w)],
        );
      }
      final left = <Widget>[], right = <Widget>[];
      for (var i = 0; i < children.length; i++) {
        (i.isEven ? left : right).add(Padding(padding: EdgeInsets.only(bottom: spacing), child: children[i]));
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
          SizedBox(width: spacing),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
        ],
      );
    });
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                  ?trailing,
                ]),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(children: [
        Icon(icon, size: 48, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
        const SizedBox(height: 12),
        Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

class SubjectDot extends StatelessWidget {
  const SubjectDot({super.key, required this.color, this.size = 12});
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle));
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.label, required this.value, this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(radius: 20, backgroundColor: c.withValues(alpha: 0.15), child: Icon(icon, color: c, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Grid of stat tiles that reflows by width.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 720 ? 4 : 2;
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

/// Opens [child] as a bottom sheet on phones and as a dialog on larger screens.
Future<T?> showAdaptiveSheet<T>(BuildContext context, Widget child) {
  if (windowSize(context) == WindowSize.compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: child),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760), child: child),
    ),
  );
}

/// Standard layout for sheet/dialog forms.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({super.key, required this.title, required this.children, this.actions = const []});
  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...children,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 8), a],
            ]),
          ],
        ],
      ),
    );
  }
}

class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.display,
    this.onChangeEnd,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double)? display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final text = display?.call(value) ?? value.round().toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label)),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
      Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: text, onChanged: onChanged, onChangeEnd: onChangeEnd),
    ]);
  }
}
