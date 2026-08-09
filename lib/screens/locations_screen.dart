/// "Where is it?" — the place tree, at any depth.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/location_tree.dart';
import 'package:home_inventory/ui/empty_state.dart';
import 'package:home_inventory/ui/location_picker.dart';
import 'package:home_inventory/ui/theme.dart';

/// How far indentation keeps growing before it stops.
///
/// Past this the rows would march off the right edge on a phone, and the
/// chevron plus the parent above it already say where you are.
const int kMaxIndentDepth = 6;

/// Browsable map of the house, nested as deeply as the user likes.
class LocationsScreen extends StatefulWidget {
  /// Creates the locations screen.
  const LocationsScreen({
    required this.repository,
    required this.onSelect,
    this.now,
    super.key,
  });

  /// Source of the tree, and the target of every edit.
  final ItemRepository repository;

  /// Called with the tapped place id. The shell turns it into a filtered
  /// items list covering that place and everything inside it.
  final void Function(String locationId) onSelect;

  /// Injectable clock, so tests need not depend on wall time.
  final DateTime Function()? now;

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  /// Which places are open. Held here rather than in each row so it survives
  /// both list recycling and a tab switch — the shell keeps this screen alive
  /// in an `IndexedStack`.
  final Set<String> _expanded = <String>{};

  DateTime _now() => (widget.now ?? DateTime.now)();

  /// Flattens the tree to just the rows that are actually visible.
  ///
  /// The reason this screen does not nest `ExpansionTile`s: nesting builds a
  /// widget per node at every depth even while collapsed, so a deep tree pays
  /// for branches nobody can see. Walking to a flat list means the row count
  /// is what is on screen, and `ListView.builder` can do its job.
  List<LocationTreeNode> _visibleRows(List<LocationTreeNode> roots) {
    final rows = <LocationTreeNode>[];
    void walk(List<LocationTreeNode> nodes) {
      for (final node in nodes) {
        rows.add(node);
        if (_expanded.contains(node.id)) walk(node.children);
      }
    }

    walk(roots);
    return rows;
  }

  Future<void> _addPlace({String? parentId}) async {
    final name = await _promptForName(
      context,
      title: parentId == null ? 'New room' : 'New place inside',
      parentId: parentId,
    );
    if (name == null) return;
    await widget.repository.createLocation(
      name: name,
      parentId: parentId,
      now: _now(),
    );
    // Opening the parent is the only way the user sees what they just made.
    if (parentId != null) setState(() => _expanded.add(parentId));
  }

  Future<void> _rename(LocationTreeNode node) async {
    final name = await _promptForName(
      context,
      title: 'Rename',
      parentId: node.location.parentId,
      initial: node.name,
      ignoringId: node.id,
    );
    if (name == null) return;
    await widget.repository.renameLocation(node.id, name, now: _now());
  }

  Future<void> _move(LocationTreeNode node) async {
    final target = await showLocationPicker(
      context,
      repository: widget.repository,
      title: 'Move "${node.name}" to',
      // Its own subtree cannot host it; offering the choice only to reject it
      // is worse than not offering it.
      excludeSubtreeOf: node.id,
    );
    if (target == null) return;
    final moved = await widget.repository.moveLocation(
      node.id,
      target.id,
      now: _now(),
    );
    if (!moved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That would put a place inside itself.')),
      );
    }
  }

  Future<void> _delete(LocationTreeNode node) async {
    final count = node.totalItemCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${node.name}"?'),
        content: Text(
          count == 0
              ? 'Nothing is filed here.'
              : 'Anything inside stays, and moves up a level. '
                    '$count ${count == 1 ? 'item' : 'items'} '
                    'will show as unfiled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await widget.repository.deleteLocation(node.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Locations')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPlace,
        tooltip: 'Add a room',
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<LocationTreeNode>>(
        stream: widget.repository.watchLocationTree(),
        builder: (context, snapshot) {
          final roots = snapshot.data ?? const <LocationTreeNode>[];
          if (roots.isEmpty) {
            return const EmptyState(
              icon: Icons.room_preferences_outlined,
              title: 'No locations yet',
              message: 'Tap + to add a room. It can stay empty.',
            );
          }
          final rows = _visibleRows(roots);
          return ListView.builder(
            // Room for the FAB, so the last row is never stuck under it.
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 2),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final node = rows[index];
              return _PlaceRow(
                node: node,
                expanded: _expanded.contains(node.id),
                onToggle: () => setState(() {
                  if (!_expanded.remove(node.id)) _expanded.add(node.id);
                }),
                onShow: () => widget.onSelect(node.id),
                onAddChild: () => _addPlace(parentId: node.id),
                onRename: () => _rename(node),
                onMove: () => _move(node),
                onDelete: () => _delete(node),
              );
            },
          );
        },
      ),
    );
  }

  Future<String?> _promptForName(
    BuildContext context, {
    required String title,
    required String? parentId,
    String? initial,
    String? ignoringId,
  }) {
    final controller = TextEditingController(text: initial ?? '');
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (value) {
              final name = (value ?? '').trim();
              if (name.isEmpty) return 'Give it a name';
              // Sibling names must stay unique: ids are derived from
              // (parent, folded name), so two "Shelf" rows under one cupboard
              // would collapse onto a single record.
              if (widget.repository.hasChildNamed(
                parentId,
                name,
                ignoringId: ignoringId,
              )) {
                return 'There is already a "$name" here';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.node,
    required this.expanded,
    required this.onToggle,
    required this.onShow,
    required this.onAddChild,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
  });

  final LocationTreeNode node;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onShow;
  final VoidCallback onAddChild;
  final VoidCallback onRename;
  final VoidCallback onMove;
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
