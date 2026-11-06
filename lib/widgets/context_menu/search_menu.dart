import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether a navigation request from the in-app search panel should stay in
/// the embedded webview instead of being opened in the system browser.
///
/// While the initial results page (and the redirects it may go through) is
/// still loading, every request stays in the webview. Once it has loaded, only
/// the search engine's own pages (result pagination, category tabs, ...) stay
/// inside the webview; every other link is a search result and must open in
/// the system browser.
///
/// [engineHosts] contains every host seen so far for the search engine, so an
/// engine that redirects to a consent/captcha domain (or a regional domain)
/// still keeps both hosts inside the webview.
@visibleForTesting
bool shouldKeepSearchNavigationInWebView({
  required Uri? target,
  required bool pageLoaded,
  required Set<String> engineHosts,
}) {
  if (!pageLoaded) {
    return true;
  }
  if (target == null) {
    return true;
  }
  final scheme = target.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return true;
  }
  return engineHosts.isEmpty || engineHosts.contains(target.host);
}

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

  /// Hosts of the search engine that hosts the results page.
  ///
  /// The configured host is seeded from the search URL and every host the
  /// results page loads from is added, so a redirect to a consent/captcha or a
  /// regional domain still counts as the engine itself.
  final Set<String> _searchEngineHosts = <String>{};
  bool _searchPageLoaded = false;

  @override
  void initState() {
    super.initState();
    final engine = Prefs().selectedSearchEngine;
    _url = engine.buildUrl(widget.query);
    final host = Uri.tryParse(_url)?.host ?? '';
    if (host.isNotEmpty) {
      _searchEngineHosts.add(host);
    }
  }

  void _reload() {
    // The refresh button must keep the reload inside the webview instead of
    // treating it as a user click on a link.
    _searchPageLoaded = false;
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(_url)),
    );
  }

  /// Opens a link from the search results in the system default browser.
  Future<void> _openInSystemBrowser(WebUri? url) async {
    if (url == null) {
      return;
    }
    final uri = Uri.tryParse(url.toString());
    if (uri == null) {
      return;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      AnxLog.warning('SearchMenu: ignored unsupported link: $uri');
      return;
    }
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        AnxLog.warning('SearchMenu: failed to open link in browser: $uri');
      }
    } catch (e) {
      AnxLog.warning('SearchMenu: failed to open link in browser: $uri, $e');
    }
  }

  /// Whether a navigation request should stay inside the embedded webview.
  bool _keepInWebView(WebUri? url) {
    return shouldKeepSearchNavigationInWebView(
      target: url == null ? null : Uri.tryParse(url.toString()),
      pageLoaded: _searchPageLoaded,
      engineHosts: _searchEngineHosts,
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
                    onPressed: _reload,
                  ),
                ],
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.border8,
                  // The Windows implementation of `flutter_inappwebview`
                  // forwards pointer events to the WebView2 but does not
                  // attach the `gestureRecognizers` passed to [InAppWebView].
                  // Without an explicit tap handler here, every click inside
                  // the webview is claimed by the context menu's close-on-tap
                  // detector, which dismisses the whole search panel before
                  // the webview can handle the click (making link clicks look
                  // like a no-op).
                  // TODO: Remove this tap shield once the Windows
                  // implementation of `flutter_inappwebview` honors
                  // `gestureRecognizers`.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: () {},
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(_url)),
                      initialSettings: InAppWebViewSettings(
                        isInspectable: kDebugMode,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        useShouldOverrideUrlLoading: true,
                      ),
                      gestureRecognizers: <Factory<
                          OneSequenceGestureRecognizer>>{
                        Factory<OneSequenceGestureRecognizer>(
                          () => EagerGestureRecognizer(),
                        ),
                      },
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                      },
                      onLoadStop: (controller, url) {
                        final host = url == null
                            ? ''
                            : (Uri.tryParse(url.toString())?.host ?? '');
                        if (host.isNotEmpty) {
                          _searchEngineHosts.add(host);
                        }
                        _searchPageLoaded = true;
                      },
                      shouldOverrideUrlLoading: (controller, navigationAction) {
                        if (!navigationAction.isForMainFrame) {
                          return NavigationActionPolicy.ALLOW;
                        }
                        final url = navigationAction.request.url;
                        if (_keepInWebView(url)) {
                          return NavigationActionPolicy.ALLOW;
                        }
                        unawaited(_openInSystemBrowser(url));
                        return NavigationActionPolicy.CANCEL;
                      },
                    ),
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
