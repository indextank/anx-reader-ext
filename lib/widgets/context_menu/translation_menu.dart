import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class TranslationMenu extends StatefulWidget {
  const TranslationMenu({
    super.key,
    required this.content,
    required this.decoration,
    required this.axis,
    this.contextText,
  });

  final String content;
  final BoxDecoration decoration;
  final Axis axis;
  final String? contextText;

  @override
  State<TranslationMenu> createState() => _TranslationMenuState();
}

class _TranslationMenuState extends State<TranslationMenu> {
  Widget? _translationWidget;
  Timer? _debounceTimer;
  bool _translationInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeTranslation();
  }

  void _initializeTranslation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _translationInitialized) return;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || _translationInitialized) return;
        setState(() {
          final effectiveContextText =
              (widget.contextText?.trim().isEmpty ?? true)
                  ? null
                  : widget.contextText;
          _translationWidget = translateText(
            widget.content,
            contextText: effectiveContextText,
          );
          _translationInitialized = true;
        });
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Widget _langPicker(bool isFrom) {
    final menuController = MenuController();
    return PointerInterceptor(
      child: MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.secondaryContainer,
          ),
          maximumSize: WidgetStateProperty.all(const Size(300, 300)),
        ),
        controller: menuController,
        menuChildren: [
          for (var lang in LangListEnum.values)
            PointerInterceptor(
              child: MenuItemButton(
                onPressed: () {
                  if (isFrom) {
                    Prefs().translateFrom = lang;
                  } else {
                    Prefs().translateTo = lang;
                  }
                },
                child: Text(lang.getNative(context)),
              ),
            ),
        ],
        builder: (context, controller, child) {
          return AppButton(
            label: isFrom
                ? Prefs().translateFrom.getNative(context)
                : Prefs().translateTo.getNative(context),
            variant: AppButtonVariant.text,
            size: AppButtonSize.small,
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: Container(
          height: widget.axis == Axis.vertical
              ? double.infinity
              : AppReadingTokens.translationMenuHeight,
          width: widget.axis == Axis.vertical
              ? AppReadingTokens.translationMenuVerticalWidth
              : double.infinity,
          decoration: widget.decoration,
          padding: AppReadingTokens.menuPadding,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.content,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                _translationWidget ??
                    const SizedBox(
                      height: 48,
                      child: Center(child: AppLoadingIndicator()),
                    ),
                const Divider(),
                AxisFlex(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  axis: widget.axis,
                  children: [
                    _langPicker(true),
                    Transform.rotate(
                      angle: widget.axis == Axis.horizontal ? 0 : 1.57,
                      child: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                    _langPicker(false),
                    if (widget.axis == Axis.horizontal) const Spacer(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
