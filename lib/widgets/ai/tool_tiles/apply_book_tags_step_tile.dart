import 'dart:convert';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/tag.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/service/ai/tools/repository/tag_repository.dart';
import 'package:anx_reader/theme/app_ai_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/utils/color/hash_color.dart';
import 'package:anx_reader/utils/color/rgb.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/tool_tile_base.dart';
import 'package:anx_reader/widgets/common/tag_chip.dart';
import 'package:flutter/material.dart';

typedef ApplyBookTagsPlan = Future<void> Function(Map<String, dynamic> plan);

class ApplyBookTagsStepTile extends StatefulWidget {
  const ApplyBookTagsStepTile({
    super.key,
    required this.step,
    this.applyPlan,
  });

  final ParsedToolStep step;
  final ApplyBookTagsPlan? applyPlan;

  @override
  State<ApplyBookTagsStepTile> createState() => _ApplyBookTagsStepTileState();
}

class _ApplyBookTagsStepTileState extends State<ApplyBookTagsStepTile> {
  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _conflicts = [];
  bool _requiresConfirmation = false;
  String? _parseError;
  bool _isApplying = false;
  bool _applied = false;
  int _outputGeneration = 0;
  int _applyGeneration = 0;

  @override
  void initState() {
    super.initState();
    _syncFromStep();
  }

  @override
  void didUpdateWidget(covariant ApplyBookTagsStepTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.output != oldWidget.step.output) {
      _syncFromStep(outputChanged: true);
    }
  }

  void _syncFromStep({bool outputChanged = false}) {
    final output = widget.step.output;
    Map<String, dynamic>? plan;
    List<Map<String, dynamic>> books = [];
    List<Map<String, dynamic>> conflicts = [];
    bool requires = false;
    String? parseError;

    if (output == null || output.trim().isEmpty) {
      parseError = 'Waiting for tool output';
    } else {
      try {
        final decoded = jsonDecode(output);
        if (decoded is Map<String, dynamic>) {
          final data = decoded['data'];
          if (data is Map<String, dynamic>) {
            requires = data['requiresConfirmation'] == true ||
                data['requires_confirmation'] == true;
            plan = Map<String, dynamic>.from(data['plan'] ?? {});
            books = (plan['books'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                const [];
            conflicts = (data['conflicts'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                const [];
            parseError = null;
          } else {
            parseError = 'Unexpected data payload';
          }
        } else {
          parseError = 'Unexpected output format';
        }
      } catch (e) {
        parseError = 'Failed to parse output: $e';
      }
    }

    setState(() {
      _plan = plan;
      _books = books;
      _conflicts = conflicts;
      _requiresConfirmation = requires;
      _parseError = parseError;
      if (outputChanged) {
        _outputGeneration++;
        _applied = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = ToolTileBase.statusColorFor(
      context,
      widget.step.status,
    );
    return ToolTileBase(
      title: widget.step.name,
      leadingIcon: Icons.label_important,
      statusColor: statusColor,
      initiallyExpanded: true,
      contentBuilder: (_) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    if (_parseError != null) {
      return AppInlineFeedback(message: _parseError);
    }
    if (_plan == null) {
      return const AppEmptyState(title: 'No plan found', compact: true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_conflicts.isNotEmpty) _buildConflicts(theme),
        if (_books.isNotEmpty) _buildBooks(theme),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            label: _applied ? 'Applied' : 'Apply',
            enabled: _requiresConfirmation && !_applied,
            isLoading: _isApplying,
            size: AppButtonSize.small,
            onPressed: _confirmApplyPlan,
          ),
        ),
      ],
    );
  }

  Widget _buildBooks(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _books
          .map(
            (book) => Padding(
              padding: AppAiTokens.toolCardBottomMargin,
              child: AppCard(
                padding: AppAiTokens.toolContentPadding,
                borderRadius: AppAiTokens.toolCardContentRadius,
                color: theme.colorScheme.surfaceContainer,
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book['bookTitle']?.toString() ?? '',
                        style: theme.textTheme.titleMedium,
                      ),
                      SizedBox(height: AppAiTokens.chipSpacing),
                      Wrap(
                        spacing: AppAiTokens.chipSpacing,
                        runSpacing: AppSpacing.tokens.s4,
                        children: (book['finalTags'] as List? ?? [])
                            .map((tag) {
                              final name = tag['name']?.toString() ?? '';
                              final rgb = _parseRgb(tag['rgb']) ??
                                  rgbFromColor(hashColor(name));
                              return TagChip(
                                label: name,
                                color: colorFromRgb(rgb),
                                dense: true,
                                selected: true,
                              );
                            })
                            .whereType<TagChip>()
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildConflicts(ThemeData theme) {
    return Padding(
      padding: AppAiTokens.toolCardBottomMargin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Conflicts', style: theme.textTheme.titleSmall),
          SizedBox(height: AppSpacing.tokens.s4),
          ..._conflicts.map(
            (c) => Text(
              c.toString(),
              style: theme.textTheme.bodySmall,
            ),
          ),
          SizedBox(height: AppSpacing.tokens.s8),
        ],
      ),
    );
  }

  Future<void> _confirmApplyPlan() async {
    if (_plan == null || _isApplying || _applied || !_requiresConfirmation) {
      return;
    }
    await AppDialog.confirm(
      context,
      title: 'Apply',
      message: 'Apply tag changes to ${_books.length} books?',
      isDangerous: true,
      dangerDescription: 'Conflicts: ${_conflicts.length}. '
          'This changes book and tag data.',
      onConfirm: _applyPlan,
    );
  }

  Future<void> _applyPlan() async {
    final plan = _plan;
    if (plan == null || _isApplying || _applied) return;
    final outputGeneration = _outputGeneration;
    final applyGeneration = ++_applyGeneration;
    setState(() {
      _isApplying = true;
    });

    try {
      final applyPlan = widget.applyPlan;
      if (applyPlan != null) {
        await applyPlan(plan);
      } else {
        await _applyPlanToRepository(plan);
      }
      if (!mounted || applyGeneration != _applyGeneration) return;
      if (outputGeneration != _outputGeneration) {
        setState(() => _isApplying = false);
        return;
      }
      setState(() {
        _isApplying = false;
        _applied = true;
      });
      AppFeedback.showSuccess(context, message: 'Tags updated');
    } catch (_) {
      if (!mounted || applyGeneration != _applyGeneration) return;
      if (outputGeneration != _outputGeneration) {
        setState(() => _isApplying = false);
        return;
      }
      setState(() => _isApplying = false);
      rethrow;
    }
  }

  Future<void> _applyPlanToRepository(Map<String, dynamic> plan) async {
    final tagRepo = TagRepository();

    for (final merge in (plan['mergeTags'] as List? ?? [])) {
      final sourceId = (merge['sourceId'] as num?)?.toInt();
      final targetId = (merge['targetId'] as num?)?.toInt();
      if (sourceId == null || targetId == null) continue;
      final source = await tagRepo.fetchTagById(sourceId);
      final target = await tagRepo.fetchTagById(targetId);
      if (source != null && target != null && source.id != target.id) {
        await tagRepo.mergeTags(source: source, target: target);
      }
    }

    for (final update in (plan['updateTags'] as List? ?? [])) {
      final id = (update['id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      await tagRepo.updateTag(
        id: id,
        newName: update['name'] as String?,
        color: _colorFromPlan(update['rgb']),
      );
    }

    for (final create in (plan['createTags'] as List? ?? [])) {
      final name = (create['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final rgb = _colorFromPlan(create['rgb']);
      await tagRepo.ensureTag(name, color: rgb);
    }

    for (final change in (plan['bookChanges'] as List? ?? [])) {
      final bookId = (change['bookId'] as num?)?.toInt();
      if (bookId == null || bookId <= 0) continue;
      final book = await bookDao.selectBookById(bookId);
      final addNames = (change['add'] as List? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty);
      final removeNames = (change['remove'] as List? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty);

      for (final name in addNames) {
        final tag = await tagRepo.ensureTag(name);
        await bookTagDao.addRelation(bookId: book.id, tagId: tag.id);
      }
      for (final name in removeNames) {
        final tag = await tagRepo.fetchTagByName(name);
        if (tag != null) {
          await bookTagDao.removeRelation(bookId: book.id, tagId: tag.id);
        }
      }
    }
  }
}

Color? _colorFromPlan(dynamic value) {
  final rgb = _parseRgb(value);
  if (rgb == null) return null;
  return colorFromRgb(rgb);
}

int? _parseRgb(dynamic value) {
  if (value == null) return null;
  if (value is Color) return rgbFromColor(value);
  if (value is num) return (value.toInt()) & 0x00FFFFFF;
  if (value is String) {
    var v = value.trim();
    if (v.startsWith('0x')) v = v.substring(2);
    if (v.startsWith('#')) v = v.substring(1);
    try {
      return int.parse(v, radix: 16) & 0x00FFFFFF;
    } catch (_) {
      return null;
    }
  }
  return null;
}
