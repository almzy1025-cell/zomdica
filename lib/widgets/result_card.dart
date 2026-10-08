import 'package:flutter/material.dart';

import '../models/models.dart';
import 'common_widgets.dart';

class ResultCard extends StatelessWidget {
  final SearchResult result;
  final bool isNew;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ResultCard({
    super.key,
    required this.result,
    required this.onTap,
    this.isNew = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(typeLabel(result.sourceType),
                    style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: cs.tertiary, borderRadius: BorderRadius.circular(6)),
                    child: Text('NEW', style: TextStyle(fontSize: 10, color: cs.onTertiary, fontWeight: FontWeight.w700)),
                  ),
                const Spacer(),
                RankBadge(level: result.rankLevel),
              ]),
              const SizedBox(height: 6),
              Text(result.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${result.source} · ${formatDateTime(result.publishedAt ?? result.discoveredAt)}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              HighlightedText(
                text: result.snippet,
                terms: result.keywords,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Requested: ${result.requestedSource} · Queried: ${result.actualSource} · Connector: ${result.connectorId}',
                style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
