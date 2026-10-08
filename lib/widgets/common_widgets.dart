import 'package:flutter/material.dart';

import '../models/models.dart';

String statusLabel(ConnectorStatus s) {
  switch (s) {
    case ConnectorStatus.ready:
      return 'READY';
    case ConnectorStatus.running:
      return 'RUNNING';
    case ConnectorStatus.success:
      return 'SUCCESS';
    case ConnectorStatus.failed:
      return 'FAILED';
    case ConnectorStatus.blocked:
      return 'BLOCKED';
    case ConnectorStatus.loginRequired:
      return 'LOGIN_REQUIRED';
    case ConnectorStatus.apiRequired:
      return 'API_REQUIRED';
    case ConnectorStatus.rateLimited:
      return 'RATE_LIMITED';
    case ConnectorStatus.notSupported:
      return 'NOT_SUPPORTED';
    case ConnectorStatus.disabled:
      return 'DISABLED';
  }
}

Color statusColor(ConnectorStatus s, ColorScheme cs) {
  switch (s) {
    case ConnectorStatus.success:
      return Colors.green.shade700;
    case ConnectorStatus.ready:
    case ConnectorStatus.running:
      return cs.primary;
    case ConnectorStatus.failed:
    case ConnectorStatus.blocked:
      return cs.error;
    case ConnectorStatus.loginRequired:
    case ConnectorStatus.apiRequired:
    case ConnectorStatus.rateLimited:
      return Colors.orange.shade800;
    case ConnectorStatus.notSupported:
    case ConnectorStatus.disabled:
      return cs.outline;
  }
}

/// يحوّل اسم الحالة المخزّن (نص) إلى لون/عرض.
ConnectorStatus statusFromName(String? name) {
  return ConnectorStatus.values.firstWhere(
    (e) => e.name == name,
    orElse: () => ConnectorStatus.ready,
  );
}

class StatusChip extends StatelessWidget {
  final ConnectorStatus status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = statusColor(status, cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3),
      ),
    );
  }
}

class RankBadge extends StatelessWidget {
  final RankLevel level;
  const RankBadge({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (level) {
      RankLevel.veryHigh => cs.error,
      RankLevel.high => Colors.orange.shade800,
      RankLevel.medium => cs.primary,
      RankLevel.low => cs.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Text(rankLevelLabel(level), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

String typeLabel(SourceType t) {
  switch (t) {
    case SourceType.news:
      return 'NEWS';
    case SourceType.forum:
      return 'FORUM';
    case SourceType.social:
      return 'SOCIAL';
    case SourceType.video:
      return 'VIDEO';
    case SourceType.patent:
      return 'PATENT';
    case SourceType.trademark:
      return 'TRADEMARK';
    case SourceType.inventor:
      return 'INVENTOR';
    case SourceType.academic:
      return 'ACADEMIC';
    case SourceType.pressRelease:
      return 'PRESS_RELEASE';
    case SourceType.job:
      return 'JOB';
    case SourceType.archive:
      return 'ARCHIVE';
    case SourceType.other:
      return 'OTHER';
  }
}

String formatDateTime(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// يُظهر النص مع تمييز الكلمات المطابقة بلون.
class HighlightedText extends StatelessWidget {
  final String text;
  final List<String> terms;
  final TextStyle? style;
  const HighlightedText({super.key, required this.text, required this.terms, this.style});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final clean = terms.where((t) => t.isNotEmpty).map(RegExp.escape).toList();
    if (clean.isEmpty) return Text(text, style: style);
    final pattern = RegExp(clean.join('|'), caseSensitive: false);
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: TextStyle(backgroundColor: cs.tertiaryContainer, fontWeight: FontWeight.w700),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const SectionCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
