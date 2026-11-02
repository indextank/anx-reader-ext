import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/chapter_split_presets.dart';
import 'package:anx_reader/models/chapter_split_rule.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

class ChapterSplitRulesPage extends StatefulWidget {
  const ChapterSplitRulesPage({super.key});

  @override
  State<ChapterSplitRulesPage> createState() => _ChapterSplitRulesPageState();
}

class _RuleEntry {
  _RuleEntry({required this.rule, required this.evaluation});

  final ChapterSplitRule rule;
  final ChapterSplitRuleEvaluation evaluation;
}

class _ChapterSplitRulesPageState extends State<ChapterSplitRulesPage> {
  late String _selectedRuleId;
  List<_RuleEntry> _builtinRules = const <_RuleEntry>[];
  List<_RuleEntry> _customRules = const <_RuleEntry>[];

  @override
  void initState() {
    super.initState();
    _refreshRules();
  }

  Future<void> _refreshRules() async {
    final prefs = Prefs();
    final activeRule = prefs.activeChapterSplitRule;
    final storedId = prefs.chapterSplitSelectedRuleId;
    if (!mounted) return;
    setState(() {
      _selectedRuleId = storedId ?? activeRule.id;
      _builtinRules = builtinChapterSplitRules
          .map(
            (rule) => _RuleEntry(
              rule: rule,
              evaluation: rule.evaluateSamples(),
            ),
          )
          .toList(growable: false);
      _customRules = prefs.chapterSplitCustomRules
          .map(
            (rule) => _RuleEntry(
              rule: rule,
              evaluation: rule.evaluateSamples(),
            ),
          )
          .toList(growable: false);
    });
  }

  Future<void> _onAddRule() async {
    final rule = await Navigator.of(context).push<ChapterSplitRule>(
      MaterialPageRoute(
          builder: (context) => const ChapterSplitRuleEditorPage()),
    );
    if (rule == null) return;
    Prefs().saveCustomChapterSplitRule(rule);
    await _refreshRules();
  }

  Future<void> _onEditRule(ChapterSplitRule rule) async {
    final updatedRule = await Navigator.of(context).push<ChapterSplitRule>(
      MaterialPageRoute(
        builder: (context) => ChapterSplitRuleEditorPage(rule: rule),
      ),
    );
    if (updatedRule == null) return;
    Prefs().saveCustomChapterSplitRule(updatedRule);
    await _refreshRules();
  }

  Future<void> _onDeleteRule(ChapterSplitRule rule) async {
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.deleteCustomRule,
      message: l10n.removeRule(rule.name),
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: l10n.removeRule(rule.name),
      onConfirm: () async {
        Prefs().deleteCustomChapterSplitRule(rule.id);
        await _refreshRules();
      },
    );
  }

  void _onSelectRule(String id) {
    Prefs().selectChapterSplitRule(id);
    setState(() => _selectedRuleId = id);
  }

  Widget _buildRuleSection({
    required String title,
    required List<_RuleEntry> rules,
    required bool allowActions,
  }) {
    if (rules.isEmpty && !allowActions) return const SizedBox.shrink();
    return Padding(
      padding: AppSpacing.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: AppSpacing.tokens.s12),
          if (rules.isEmpty)
            AppEmptyState(
              title: title,
              message: L10n.of(context).addCustomRule,
              actionLabel: L10n.of(context).addCustomRule,
              onAction: _onAddRule,
            )
          else
            ...rules.map(
              (entry) => _buildRuleTile(
                entry: entry,
                allowActions: allowActions,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRuleTile({
    required _RuleEntry entry,
    required bool allowActions,
  }) {
    final rule = entry.rule;
    final evaluation = entry.evaluation;
    final isSelected = _selectedRuleId == rule.id;
    final l10n = L10n.of(context);
    return AppCard(
      margin: AppSpacing.only(bottom: 12),
      padding: AppSpacing.all12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<String>(value: rule.id),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rule.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: AppSpacing.tokens.s4),
                    SelectableText(
                      rule.pattern,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                    if (!evaluation.isValid)
                      Padding(
                        padding: AppSpacing.only(top: 8),
                        child: Text(
                          evaluation.errorMessage ?? l10n.invalidPattern,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.appTheme.colors.error,
                                  ),
                        ),
                      ),
                  ],
                ),
              ),
              if (allowActions)
                Column(
                  children: [
                    AppIconButton(
                      tooltip: l10n.commonEdit,
                      icon: Icons.edit_outlined,
                      onPressed: () => _onEditRule(rule),
                    ),
                    AppIconButton(
                      tooltip: l10n.commonDelete,
                      icon: Icons.delete_outline,
                      onPressed: () => _onDeleteRule(rule),
                    ),
                  ],
                ),
            ],
          ),
          const Divider(),
          Text(l10n.samples, style: Theme.of(context).textTheme.labelMedium),
          SizedBox(height: AppSpacing.tokens.s8),
          _SampleMatches(evaluation: evaluation),
          if (evaluation.sampleMatches.isEmpty) Text(l10n.noSamplesProvided),
          if (isSelected)
            Padding(
              padding: AppSpacing.only(top: 8),
              child: Text(
                l10n.currentlyInUse,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).chapterSplitting)),
      body: AppSafeArea(
        top: false,
        child: RadioGroup<String>(
          groupValue: _selectedRuleId,
          onChanged: (value) {
            if (value != null) _onSelectRule(value);
          },
          child: ListView(
            children: [
              _buildRuleSection(
                title: L10n.of(context).builtInRules,
                rules: _builtinRules,
                allowActions: false,
              ),
              _buildRuleSection(
                title: L10n.of(context).customRules,
                rules: _customRules,
                allowActions: true,
              ),
              Padding(
                padding: AppSpacing.horizontal16,
                child: AppButton(
                  label: L10n.of(context).addCustomRule,
                  icon: Icons.add_circle_outline,
                  variant: AppButtonVariant.outlined,
                  onPressed: _onAddRule,
                ),
              ),
              SizedBox(height: AppSpacing.tokens.s24),
            ],
          ),
        ),
      ),
    );
  }
}

class ChapterSplitRuleEditorPage extends StatefulWidget {
  const ChapterSplitRuleEditorPage({super.key, this.rule});

  final ChapterSplitRule? rule;

  @override
  State<ChapterSplitRuleEditorPage> createState() =>
      _ChapterSplitRuleEditorPageState();
}

class _ChapterSplitRuleEditorPageState
    extends State<ChapterSplitRuleEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _patternController;
  late final TextEditingController _samplesController;
  late bool _caseSensitive;
  late bool _multiLine;
  late String _ruleId;
  ChapterSplitRuleEvaluation? _evaluation;
  bool _localizedDefaultsApplied = false;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    if (rule == null) {
      _ruleId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      _nameController = TextEditingController();
      _patternController = TextEditingController();
      _samplesController = TextEditingController();
      _caseSensitive = false;
      _multiLine = true;
    } else {
      _ruleId = rule.id;
      _nameController = TextEditingController(text: rule.name);
      _patternController = TextEditingController(text: rule.pattern);
      _samplesController = TextEditingController(text: rule.samples.join('\n'));
      _caseSensitive = rule.caseSensitive;
      _multiLine = rule.multiLine;
    }
    _evaluate();
    _patternController.addListener(_evaluate);
    _samplesController.addListener(_evaluate);
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localizedDefaultsApplied) return;
    if (widget.rule == null) {
      final l10n = L10n.of(context);
      if (_nameController.text.isEmpty) {
        _nameController.text = l10n.newCustomRule;
      }
      if (_samplesController.text.isEmpty) {
        _samplesController.text = 'Chapter 1: Beginning';
      }
    }
    _localizedDefaultsApplied = true;
    _evaluate();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _patternController.dispose();
    _samplesController.dispose();
    super.dispose();
  }

  void _evaluate() {
    final rule = ChapterSplitRule(
      id: _ruleId,
      name: _nameController.text,
      pattern: _patternController.text,
      samples: _currentSamples,
      caseSensitive: _caseSensitive,
      multiLine: _multiLine,
      isBuiltin: false,
    );
    setState(() => _evaluation = rule.evaluateSamples());
  }

  List<String> get _currentSamples => _samplesController.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  bool get _canSave {
    if (_nameController.text.trim().isEmpty ||
        _patternController.text.trim().isEmpty ||
        _currentSamples.isEmpty) {
      return false;
    }
    return _evaluation?.isValid ?? false;
  }

  Future<void> _onSave() async {
    if (!_canSave) return;
    final rule = ChapterSplitRule(
      id: _ruleId,
      name: _nameController.text.trim(),
      pattern: _patternController.text.trim(),
      samples: _currentSamples,
      caseSensitive: _caseSensitive,
      multiLine: _multiLine,
      isBuiltin: false,
    );
    if (mounted) Navigator.of(context).pop(rule);
  }

  @override
  Widget build(BuildContext context) {
    final evaluation = _evaluation;
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.rule == null ? l10n.newCustomRule : l10n.editCustomRule,
        ),
        actions: [
          AppSubmitButton(
            label: l10n.commonSave,
            variant: AppButtonVariant.text,
            disabled: !_canSave,
            onSubmit: _onSave,
          ),
        ],
      ),
      body: AppSafeArea(
        top: false,
        child: ListView(
          padding: AppSpacing.all16,
          children: [
            AppTextField(controller: _nameController, label: l10n.ruleName),
            SizedBox(height: AppSpacing.tokens.s16),
            AppTextField(
              controller: _patternController,
              label: l10n.regularExpression,
              errorText: evaluation != null && !evaluation.isValid
                  ? evaluation.errorMessage ?? l10n.invalidPattern
                  : null,
              helperText: l10n.dartStyleRegularExpression,
              maxLines: 3,
              minLines: 1,
            ),
            SizedBox(height: AppSpacing.tokens.s16),
            CheckboxListTile(
              value: _caseSensitive,
              onChanged: (value) {
                setState(() => _caseSensitive = value ?? false);
                _evaluate();
              },
              title: Text(l10n.caseSensitive),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: AppSpacing.zero,
            ),
            CheckboxListTile(
              value: _multiLine,
              onChanged: (value) {
                setState(() => _multiLine = value ?? true);
                _evaluate();
              },
              title: Text(l10n.multiLine),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: AppSpacing.zero,
            ),
            SizedBox(height: AppSpacing.tokens.s16),
            AppTextField(
              controller: _samplesController,
              label: l10n.samplesOnePerLine,
              minLines: 5,
              maxLines: 10,
            ),
            SizedBox(height: AppSpacing.tokens.s24),
            if (evaluation != null) ...[
              Text(l10n.testResults,
                  style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: AppSpacing.tokens.s12),
              _SampleMatches(evaluation: evaluation),
              if (evaluation.sampleMatches.isEmpty) Text(l10n.noSamples),
            ],
          ],
        ),
      ),
    );
  }
}

class _SampleMatches extends StatelessWidget {
  const _SampleMatches({required this.evaluation});

  final ChapterSplitRuleEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: evaluation.sampleMatches.map((sample) {
        final color = evaluation.isValid && sample.isMatch
            ? context.appTheme.colors.success
            : context.appTheme.colors.error;
        return Padding(
          padding: AppSpacing.vertical4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                evaluation.isValid
                    ? (sample.isMatch
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined)
                    : Icons.error_outline,
                color: color,
                size: AppSpacing.tokens.s20,
              ),
              SizedBox(width: AppSpacing.tokens.s8),
              Expanded(
                child: Text(
                  sample.sample,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
