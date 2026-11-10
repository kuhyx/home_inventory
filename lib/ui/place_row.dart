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
    final muted = theme.colorScheme.onSurfaceVariant;
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
              icon: Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                semanticLabel: expanded ? 'Collapse' : 'Expand',
              ),
            )
          // Keeps childless rows aligned with their siblings' labels.
          : const SizedBox(width: 48),
      // A nameless place (synced in blank) shows a dashed box, not a word.
      title: node.name.isEmpty
          ? const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Icon(
                Icons.check_box_outline_blank,
                semanticLabel: 'Unnamed place',
              ),
            )
          : Text(node.name),
      // Box glyph + count, the same pair the item summary strip uses.
      subtitle: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 14, color: muted),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${node.totalItemCount}',
            semanticsLabel: _countLabel(node.totalItemCount),
            style: theme.textTheme.labelMedium?.copyWith(color: muted),
          ),
        ],
      ),
      onTap: hasChildren ? onToggle : onShow,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('btn_show_everything'),
            onPressed: onShow,
            icon: const Icon(
              Icons.arrow_forward,
              semanticLabel: 'Show everything here',
            ),
          ),
          PopupMenuButton<String>(
            key: const Key('menu_more'),
            icon: const Icon(Icons.more_vert, semanticLabel: 'More'),
            onSelected: (value) => switch (value) {
              'add' => onAddChild(),
              'rename' => onRename(),
              'move' => onMove(),
              _ => onDelete(),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'add',
                child: Icon(
                  Icons.add_circle_outline,
                  semanticLabel: 'Add a place inside',
                ),
              ),
              PopupMenuItem(
                value: 'rename',
                child: Icon(Icons.edit, semanticLabel: 'Rename'),
              ),
              PopupMenuItem(
                value: 'move',
                child: Icon(Icons.change_circle, semanticLabel: 'Move'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Icon(Icons.delete, semanticLabel: 'Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Spoken-only item count.
  static String _countLabel(int count) =>
      count == 1 ? '1 item' : '$count items';
}
