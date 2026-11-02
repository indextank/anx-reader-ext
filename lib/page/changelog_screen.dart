import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/get_current_language_code.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Changelog screen for showing app updates
/// Displays version history and new features
class ChangelogScreen extends StatefulWidget {
  final String lastVersion;
  final String currentVersion;
  final VoidCallback onComplete;

  const ChangelogScreen({
    super.key,
    required this.lastVersion,
    required this.currentVersion,
    required this.onComplete,
  });

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  String _changelogContent = '';
  bool _isLoading = true;
  bool _loadFailed = false;

  String get currentVersion => widget.currentVersion.split('+').first;
  String get lastVersion => widget.lastVersion.split('+').first;

  @override
  void initState() {
    super.initState();
    _loadChangelog();
  }

  Future<void> _loadChangelog() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }
    try {
      final fullChangelog = await rootBundle.loadString('assets/CHANGELOG.md');
      final content = processChangelogContent(
        _extractVersionChangelog(fullChangelog),
      );
      if (mounted) setState(() => _changelogContent = content);
    } catch (e) {
      AnxLog.warning('Failed to load changelog from assets: $e');
      if (mounted) {
        setState(() {
          _changelogContent = processChangelogContent(_getDefaultChangelog());
          _loadFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String processChangelogContent(String content) {
    bool isChinese() => getCurrentLanguageCode().startsWith('zh');

    final lines = content.split('\n');
    var processedLines = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        continue;
      }

      if (line.startsWith('- ') || line.startsWith('* ')) {
        processedLines.add(line);
        continue;
      }
    }
    if (isChinese()) {
      processedLines = processedLines.sublist(processedLines.length ~/ 2);
    } else {
      processedLines = processedLines.sublist(0, processedLines.length ~/ 2);
    }

    return processedLines.join('\n');
  }

  String _extractVersionChangelog(String fullChangelog) {
    final versionMatch = RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(currentVersion);
    if (versionMatch == null) {
      return _getDefaultChangelog();
    }

    final version = versionMatch.group(1)!;
    final versionHeader = '## $version';
    final lines = fullChangelog.split('\n');
    final startIndex = lines.indexWhere((line) => line.trim() == versionHeader);

    if (startIndex == -1) {
      AnxLog.warning('Version $version not found in changelog');
      return _getDefaultChangelog();
    }

    int endIndex = lines.length;
    for (int i = startIndex + 1; i < lines.length; i++) {
      if (lines[i].trim().startsWith('## ') &&
          lines[i].trim() != versionHeader) {
        endIndex = i;
        break;
      }
    }

    final versionContent =
        lines.sublist(startIndex + 1, endIndex).join('\n').trim();

    if (versionContent.isEmpty) {
      return _getDefaultChangelog();
    }

    return versionContent;
  }

  String _getDefaultChangelog() {
    return '''
- Fixed some bugs
- 修复已知问题
''';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.whatsNew)),
      body: AppSafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: AppLoadingIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.update,
                              color: theme.colorScheme.primary,
                              size: AppSpacing.tokens.s24,
                            ),
                            SizedBox(width: AppSpacing.tokens.s8),
                            Expanded(
                              child: Text(
                                l10n.updateFromVersion(lastVersion),
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: AppSpacing.tokens.s4),
                        Text(
                          l10n.welcomeToVersion(currentVersion),
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _changelogContent.isEmpty
                        ? const AppEmptyState()
                        : SingleChildScrollView(
                            padding: AppSpacing.all16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_loadFailed) ...[
                                  AppInlineFeedback(
                                    message: l10n.commonLoadFailed,
                                    onRetry: _loadChangelog,
                                  ),
                                  SizedBox(height: AppSpacing.tokens.s16),
                                ],
                                StyledMarkdown(data: _changelogContent),
                              ],
                            ),
                          ),
                  ),
                  Padding(
                    padding: AppSpacing.all16,
                    child: SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: l10n.commonOk,
                        onPressed: widget.onComplete,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
