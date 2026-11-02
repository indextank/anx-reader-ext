import 'dart:async';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

Future<dynamic> showSimpleDialog(
    String title, Function saveToPrefs, List<Widget> children) {
  final context = navigatorKey.currentContext!;
  return showDialog(
    context: context,
    builder: (BuildContext context) {
      return _SettingsSimpleDialog(title: title, children: children);
    },
  );
}

Widget dialogOption(String name, String value, Function saveToPrefs) {
  return _SettingsDialogOption(
    name: name,
    value: value,
    saveToPrefs: saveToPrefs,
  );
}

class _SettingsSimpleDialog extends StatefulWidget {
  const _SettingsSimpleDialog({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  State<_SettingsSimpleDialog> createState() => _SettingsSimpleDialogState();
}

class _SettingsSimpleDialogState extends State<_SettingsSimpleDialog> {
  bool _pending = false;
  bool _showError = false;
  bool _completed = false;
  Future<void> Function()? _lastAction;

  Future<void> _save(Future<void> Function() action) async {
    if (_pending || _completed) return;
    _lastAction = action;
    setState(() {
      _pending = true;
      _showError = false;
    });
    try {
      await action();
      if (!mounted || _completed) return;
      _completed = true;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _showError = true);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  void _retry() {
    final action = _lastAction;
    if (action != null) _save(action);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_pending,
      child: SimpleDialog(
        title: Text(widget.title),
        children: [
          ...widget.children.map(
            (child) => _SettingsDialogScope(
              pending: _pending,
              onSave: _save,
              child: child,
            ),
          ),
          if (_pending)
            const Center(
              child: AppLoadingIndicator(
                size: AppLoadingIndicatorSize.button,
              ),
            ),
          if (_showError)
            Padding(
              padding: AppSpacing.horizontal16,
              child: AppInlineFeedback(onRetry: _retry),
            ),
        ],
      ),
    );
  }
}

class _SettingsDialogScope extends InheritedWidget {
  const _SettingsDialogScope({
    required this.pending,
    required this.onSave,
    required super.child,
  });

  final bool pending;
  final Future<void> Function(Future<void> Function() action) onSave;

  static _SettingsDialogScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_SettingsDialogScope>();
    assert(scope != null, 'dialogOption must be used with showSimpleDialog');
    return scope!;
  }

  @override
  bool updateShouldNotify(_SettingsDialogScope oldWidget) {
    return pending != oldWidget.pending || onSave != oldWidget.onSave;
  }
}

class _SettingsDialogOption extends StatelessWidget {
  const _SettingsDialogOption({
    required this.name,
    required this.value,
    required this.saveToPrefs,
  });

  final String name;
  final String value;
  final Function saveToPrefs;

  @override
  Widget build(BuildContext context) {
    final scope = _SettingsDialogScope.of(context);
    return SimpleDialogOption(
      onPressed: scope.pending
          ? null
          : () => scope.onSave(
                () => Future.sync(() => saveToPrefs(value)),
              ),
      child: Padding(
        padding: AppSpacing.vertical4,
        child: Text(name),
      ),
    );
  }
}
