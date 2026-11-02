import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class CustomCSSEditor extends StatefulWidget {
  const CustomCSSEditor({super.key});

  @override
  State<CustomCSSEditor> createState() => _CustomCSSEditorState();
}

class _CustomCSSEditorState extends State<CustomCSSEditor> {
  late TextEditingController _cssController;
  bool _hasValidationErrors = false;
  String _validationMessage = '';
  bool _isExpanded = false;
  String _tempCSS = '';

  static const String defaultCSS = '''p {
  color:red !important;
}
''';

  @override
  void initState() {
    super.initState();
    final currentCSS = Prefs().customCSS;
    _tempCSS = currentCSS.isEmpty ? defaultCSS : currentCSS;
    _cssController = TextEditingController(text: _tempCSS);
    _cssController.addListener(_onCSSChanged);
    _isExpanded = Prefs().customCSSEnabled;
  }

  @override
  void dispose() {
    _cssController.removeListener(_onCSSChanged);
    _cssController.dispose();
    super.dispose();
  }

  void _onCSSChanged() {
    _tempCSS = _cssController.text;
    _validateCSS(_tempCSS);
  }

  void _validateCSS(String css) {
    setState(() {
      _hasValidationErrors = false;
      _validationMessage = '';
    });
    if (css.trim().isEmpty) return;

    final lines = css.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty ||
          line.startsWith('/*') ||
          line.startsWith('*') ||
          line.startsWith('*/')) {
        continue;
      }
      final openBraces = '{'.allMatches(css).length;
      final closeBraces = '}'.allMatches(css).length;
      if (openBraces != closeBraces) {
        setState(() {
          _hasValidationErrors = true;
          _validationMessage = L10n.of(context).cssValidationUnmatchedBraces;
        });
        return;
      }
      if (line.contains(':') && !line.contains('{') && !line.contains('}')) {
        if (!line.endsWith(';') && !line.endsWith('{')) {
          setState(() {
            _hasValidationErrors = true;
            _validationMessage =
                L10n.of(context).cssValidationMissingSemicolon(i + 1);
          });
          return;
        }
      }
    }
  }

  void _applyCSS() {
    epubPlayerKey.currentState?.changeStyle(null);
  }

  void _saveAndApply() {
    if (_hasValidationErrors) return;
    Prefs().customCSS = _tempCSS;
    if (Prefs().customCSSEnabled) _applyCSS();
    AppFeedback.showSuccess(
      context,
      message: L10n.of(context).commonSaved,
    );
  }

  void _restoreDefault() {
    _cssController.text = defaultCSS;
    _tempCSS = defaultCSS;
    _validateCSS(defaultCSS);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppListTile(
          title: L10n.of(context).customCssEnabled,
          contentPadding: AppSpacing.zero,
          trailing: Switch(
            value: Prefs().customCSSEnabled,
            onChanged: (value) {
              setState(() {
                Prefs().customCSSEnabled = value;
                _isExpanded = value;
                if (!_hasValidationErrors) _applyCSS();
              });
            },
          ),
        ),
        if (_isExpanded) ...[
          if (_hasValidationErrors)
            Padding(
              padding: AppReadingTokens.settingsRowGap,
              child: AppInlineFeedback(message: _validationMessage),
            ),
          AppCard(
            padding: AppSpacing.zero,
            child: SizedBox(
              height: AppReadingTokens.cssEditorHeight,
              child: AppTextField(
                controller: _cssController,
                maxLines: null,
                minLines: null,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: AppReadingTokens.codeFontFamily,
                      height: 1.4,
                    ),
                hintText: L10n.of(context).cssEditorHint,
                border: InputBorder.none,
                contentPadding: AppSpacing.all12,
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.tokens.s12,
            runSpacing: AppSpacing.tokens.s8,
            children: [
              AppButton(
                onPressed: _restoreDefault,
                icon: Icons.restore,
                label: L10n.of(context).cssRestoreDefault,
                variant: AppButtonVariant.text,
              ),
              AppButton(
                enabled: !_hasValidationErrors,
                onPressed: _saveAndApply,
                icon: Icons.save,
                label: L10n.of(context).cssSaveAndApply,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
