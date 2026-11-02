import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class SearchMenu extends StatefulWidget {
  const SearchMenu({
    super.key,
    required this.query,
    required this.decoration,
    required this.axis,
  });

  final String query;
  final BoxDecoration decoration;
  final Axis axis;

  @override
  State<SearchMenu> createState() => _SearchMenuState();
}

class _SearchMenuState extends State<SearchMenu> {
  late final String _url;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    final engine = Prefs().selectedSearchEngine;
    _url = engine.buildUrl(widget.query);
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
              : AppReadingTokens.searchMenuHeight,
          width: widget.axis == Axis.vertical
              ? AppReadingTokens.searchMenuVerticalWidth
              : double.infinity,
          decoration: widget.decoration,
          padding: AppReadingTokens.menuPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${L10n.of(context).contextMenuSearch}: ${widget.query}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.refresh,
                    tooltip: L10n.of(context).commonRefresh,
                    onPressed: () {
                      _webViewController?.loadUrl(
                        urlRequest: URLRequest(url: WebUri(_url)),
                      );
                    },
                  ),
                ],
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.border8,
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(_url)),
                    initialSettings: InAppWebViewSettings(
                      isInspectable: kDebugMode,
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                    ),
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
