import 'dart:convert';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan_group.dart';
import 'package:anx_reader/service/bookshelf/bookshelf_organize_service.dart';
import 'package:anx_reader/theme/app_ai_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/tool_tile_base.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

typedef _GroupNameLookup = Map<int, String>;

class OrganizeBookshelfStepTile extends ConsumerStatefulWidget {
  const OrganizeBookshelfStepTile({
    super.key,
    required this.step,
  });

  final ParsedToolStep step;

  @override
  ConsumerState<OrganizeBookshelfStepTile> createState() =>
      _OrganizeBookshelfStepTileState();
}

class _OrganizeBookshelfStepTileState
    extends ConsumerState<OrganizeBookshelfStepTile> {
  bool _isApplying = false;
  bool _applied = false;
  bool _requiresConfirmation = false;
  BookshelfOrganizePlan? _plan;
  String? _parseError;
  bool _didInitialSync = false;
  int _outputGeneration = 0;
  int _applyGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitialSync) {
      _didInitialSync = true;
      _syncFromStep(initial: true, useSetState: true);
    }
  }

  @override
  void didUpdateWidget(covariant OrganizeBookshelfStepTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.output != oldWidget.step.output) {
      _syncFromStep(initial: false, useSetState: true);
    }
  }

  void _syncFromStep({required bool initial, bool useSetState = false}) {
    final output = widget.step.output;
    BookshelfOrganizePlan? plan;
    String? parseError;
    var requiresConfirmation = false;

    if (output == null || output.trim().isEmpty) {
      parseError = L10n.of(context).waitingForToolOutput;
    } else {
      try {
        final decoded = jsonDecode(output);
        if (decoded is! Map<String, dynamic>) {
          parseError = L10n.of(context).unexpectedToolOutputFormat;
        } else {
          final data = decoded['data'];
          if (data is! Map<String, dynamic>) {
            parseError = L10n.of(context).missingPlanPayload;
          } else {
            requiresConfirmation = data['requiresConfirmation'] == true ||
                data['requires_confirmation'] == true;
            final planJson = data['plan'];
            if (planJson is! Map) {
              parseError = L10n.of(context).planDetailsMissing;
            } else {
              plan = BookshelfOrganizePlan.fromJson(
                Map<String, dynamic>.from(planJson),
              );
              parseError = null;
            }
          }
        }
      } catch (error) {
        parseError = L10n.of(context).failedToParsePlan(error);
      }
    }

    void assign() {
      _plan = plan;
      _parseError = parseError;
      _requiresConfirmation = requiresConfirmation;
      if (!initial) {
        _outputGeneration++;
        _applied = false;
      }
    }

    if (useSetState) {
      setState(assign);
    } else {
      assign();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = ToolTileBase.statusColorFor(
      context,
      widget.step.status,
    );

    return ToolTileBase(
      title: widget.step.name,
      leadingIcon: Icons.auto_awesome_mosaic,
      statusColor: statusColor,
      initiallyExpanded: true,
      contentBuilder: (_) => _buildExpandedContent(theme),
    );
  }

  Widget _buildExpandedContent(ThemeData theme) {
    if (_parseError != null) {
      return Text(_parseError!, style: theme.textTheme.bodyMedium);
    }

    if (_plan == null) {
      return Text(
        L10n.of(context).noReorganizationPlanGenerated,
        style: theme.textTheme.bodyMedium,
      );
    }

    final groupLookup = _resolveGroupNames();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_plan!.summary != null)
          Padding(
            padding: AppAiTokens.toolCardBottomMargin,
            child: Text(_plan!.summary!, style: theme.textTheme.bodyMedium),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: AppAiTokens.toolOutputMaxHeight,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ..._plan!.groups.map(
                  (group) => _buildGroupBlock(group, groupLookup, theme),
                ),
              ],
            ),
          ),
        ),
        if (_plan!.groups.isNotEmpty) SizedBox(height: AppSpacing.tokens.s8),
        if (_plan!.ungroupedBooks.isNotEmpty) _buildUngroupedBlock(theme),
        if (_plan!.cleanupGroupIds.isNotEmpty)
          Padding(
            padding: AppAiTokens.feedbackTopPadding,
            child: _buildCleanupSection(groupLookup, theme),
          ),
        SizedBox(height: AppSpacing.tokens.s8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.tokens.s8,
          runSpacing: AppSpacing.tokens.s8,
          children: [
            AppButton(
              label: L10n.of(context).copyJson,
              icon: Icons.copy,
              variant: AppButtonVariant.text,
              size: AppButtonSize.small,
              enabled: widget.step.output != null,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.step.output!));
                AppFeedback.showInfo(
                  context,
                  message: L10n.of(context).planCopied,
                );
              },
            ),
            AppButton(
              label: _applied
                  ? L10n.of(context).completed
                  : L10n.of(context).applyToBookshelf,
              enabled: _canApplyPlan,
              isLoading: _isApplying,
              size: AppButtonSize.small,
              onPressed: _confirmApplyPlan,
            ),
          ],
        ),
      ],
    );
  }

  bool get _canApplyPlan =>
      !_isApplying && !_applied && _plan != null && _requiresConfirmation;

  Widget _buildGroupBlock(
    BookshelfOrganizePlanGroup group,
    _GroupNameLookup groupLookup,
    ThemeData theme,
  ) {
    final title = group.proposedName ?? group.currentName;
    final chips = <Widget>[];
    if (group.createNew) {
      chips.add(_buildChip(theme, L10n.of(context).newGroup));
    }
    if (group.willRename) {
      final current = group.currentName ??
          groupLookup[group.groupId] ??
          L10n.of(context).unnamed;
      chips.add(_buildChip(theme, L10n.of(context).renameFrom(current)));
    }

    return AppCard(
      color: theme.colorScheme.surfaceContainer,
      padding: AppAiTokens.toolContentPadding,
      margin: AppAiTokens.toolCardBottomMargin,
      borderRadius: AppAiTokens.toolCardContentRadius,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title ?? L10n.of(context).groupWithId(group.groupId),
              style: theme.textTheme.titleSmall,
            ),
            if (chips.isNotEmpty)
              Padding(
                padding: AppSpacing.only(top: AppSpacing.tokens.s4),
                child: Wrap(
                  spacing: AppAiTokens.chipSpacing,
                  runSpacing: AppSpacing.tokens.s4,
                  children: chips,
                ),
              ),
            if (group.books.isNotEmpty)
              Padding(
                padding: AppAiTokens.toolContentTopPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: group.books
                      .map(
                        (book) => Padding(
                          padding: AppSpacing.only(
                            bottom: AppSpacing.tokens.s4,
                          ),
                          child: Text(
                            '• ${book.title}${book.author != null ? ' — ${book.author}' : ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (group.books.isEmpty)
              Padding(
                padding: AppAiTokens.toolContentTopPadding,
                child: Text(
                  L10n.of(context).noBooksAssignedInThisPlan,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUngroupedBlock(ThemeData theme) {
    return AppCard(
      color: theme.colorScheme.surface,
      padding: AppAiTokens.toolContentPadding,
      borderRadius: AppAiTokens.toolCardContentRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.of(context).booksToUngroup,
            style: theme.textTheme.titleSmall,
          ),
          SizedBox(height: AppSpacing.tokens.s4),
          ..._plan!.ungroupedBooks.map(
            (book) => Padding(
              padding: AppSpacing.only(bottom: AppSpacing.tokens.s4),
              child: Text(
                '• ${book.title}${book.author != null ? ' — ${book.author}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCleanupSection(
    _GroupNameLookup lookup,
    ThemeData theme,
  ) {
    return AppCard(
      color: theme.colorScheme.surfaceContainer,
      padding: AppAiTokens.toolContentPadding,
      borderRadius: AppAiTokens.toolCardContentRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.of(context).groupsToRemove,
            style: theme.textTheme.titleSmall,
          ),
          SizedBox(height: AppSpacing.tokens.s4),
          ..._plan!.cleanupGroupIds.map((id) {
            final name = lookup[id];
            return Text(
              name != null
                  ? '• $name (ID $id)'
                  : '• ${L10n.of(context).groupId(id)}',
              style: theme.textTheme.bodySmall,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChip(ThemeData theme, String text) {
    return Container(
      padding: AppAiTokens.toolChipPadding,
      decoration: BoxDecoration(
        borderRadius: AppAiTokens.toolChipRadius,
        color: theme.colorScheme.secondaryContainer,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  Future<void> _confirmApplyPlan() async {
    if (!_canApplyPlan) return;
    final plan = _plan!;
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.applyToBookshelf,
      message: plan.summary ?? l10n.applyToBookshelf,
      isDangerous: true,
      dangerDescription: '${l10n.booksToUngroup}: '
          '${plan.ungroupedBooks.length}; ${l10n.groupsToRemove}: '
          '${plan.cleanupGroupIds.length}',
      onConfirm: () => _applyPlan(plan),
    );
  }

  Future<void> _applyPlan(BookshelfOrganizePlan plan) async {
    if (_isApplying || _applied) return;
    final outputGeneration = _outputGeneration;
    final applyGeneration = ++_applyGeneration;
    setState(() {
      _isApplying = true;
    });

    try {
      await ref.read(bookshelfOrganizeServiceProvider).applyPlan(plan);
      if (!mounted || applyGeneration != _applyGeneration) return;
      if (outputGeneration != _outputGeneration) {
        setState(() => _isApplying = false);
        return;
      }
      setState(() {
        _isApplying = false;
        _applied = true;
      });
      AppFeedback.showSuccess(
        context,
        message: L10n.of(context).bookshelfUpdated,
      );
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

  _GroupNameLookup _resolveGroupNames() {
    final groups = ref.watch(groupDaoProvider);
    return groups.maybeWhen(
      data: (items) => {
        for (final group in items) group.id: group.name,
      },
      orElse: () => const {},
    );
  }
}
