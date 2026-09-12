/// One row of the place tree.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/models/location_tree.dart';
import 'package:home_inventory/ui/theme.dart';

/// How far indentation keeps growing before it stops.
const int kMaxIndentDepth = 6;

/// One row of the place tree: name, counts, and its own actions.
///
/// Indentation stops at [kMaxIndentDepth]: past that the rows would march off
/// the right edge on a phone, and the chevron plus the parent above it
/// already say where you are.
class PlaceRow extends StatelessWidget {
  /// Creates the row.
  const PlaceRow({
    required this.node,
    required this.expanded,
    required this.onToggle,
    required this.onShow,
    required this.onAddChild,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
    super.key,
  });

  /// The place this row shows, with its counts and depth.
  final LocationTreeNode node;

  /// Whether this place's children are currently shown.
  final bool expanded;

  /// Opens or closes this place's children.
  final VoidCallback onToggle;

  /// Shows this place, and everything in it, on the items tab.
  final VoidCallback onShow;

  /// Adds a place inside this one.
  final VoidCallback onAddChild;

  /// Renames this place.
  final VoidCallback onRename;

  /// Re-parents this place.
  final VoidCallback onMove;

  /// Deletes this place, leaving its children and items where they are.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChildren = node.children.isNotEmpty;
    final indent =
        AppSpacing.md +
        AppSpacing.lg *
            (node.depth > kMaxIndentDepth ? kMaxIndentDepth : node.depth);
    return ListTile(
      contentPadding: EdgeInsets.only(left: indent, right: AppSpacing.xs),
      leading: hasChildren
          ? IconButton(
              onPressed: onToggle,
              icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
              tooltip: expanded ? 'Collapse' : 'Expand',
            )
          // Keeps childless rows aligned with their siblings' labels.
          : const SizedBox(width: 48),
      title: Text(node.name.isEmpty ? 'Unnamed place' : node.name),
      subtitle: Text(
        _countLabel(node.totalItemCount),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: hasChildren ? onToggle : onShow,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onShow,
            icon: const Icon(Icons.arrow_forward),
            tooltip: 'Show everything here',
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) => switch (value) {
              'add' => onAddChild(),
              'rename' => onRename(),
              'move' => onMove(),
              _ => onDelete(),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'add', child: Text('Add a place inside')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'move', child: Text('Move')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  static String _countLabel(int count) =>
      count == 1 ? '1 item' : '$count items';
}
