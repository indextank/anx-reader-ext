import 'package:anx_reader/widgets/context_menu/search_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldKeepSearchNavigationInWebView', () {
    bool keep(
      String? target, {
      bool pageLoaded = true,
      Set<String> engineHosts = const {'www.google.com'},
    }) {
      return shouldKeepSearchNavigationInWebView(
        target: target == null ? null : Uri.parse(target),
        pageLoaded: pageLoaded,
        engineHosts: engineHosts,
      );
    }

    test('keeps the initial results page and its redirects in the webview', () {
      expect(
        keep('https://accounts.google.com/consent', pageLoaded: false),
        isTrue,
      );
      expect(
        keep('https://www.example.com/article', pageLoaded: false),
        isTrue,
      );
    });

    test('keeps the search engine pages in the webview', () {
      expect(keep('https://www.google.com/search?q=anx'), isTrue);
      expect(keep('https://www.google.com/search?q=anx&udm=2'), isTrue);
    });

    test('opens links to other sites in the system browser', () {
      expect(keep('https://www.reddit.com/r/PhilosophyofScience'), isFalse);
      expect(keep('http://example.com/page'), isFalse);
    });

    test('treats relative and non-http links as in-page navigation', () {
      expect(keep('https://www.google.com/#anchor'), isTrue);
      expect(keep('mailto:someone@example.com'), isTrue);
      expect(keep('javascript:void(0)'), isTrue);
      expect(keep('about:blank'), isTrue);
      expect(keep(null), isTrue);
    });

    test('keeps everything while the engine hosts are unknown', () {
      expect(
        keep(
          'https://www.reddit.com/r/PhilosophyofScience',
          engineHosts: const {},
        ),
        isTrue,
      );
    });

    test('keeps every engine host seen during consent/captcha redirects', () {
      expect(
        keep(
          'https://www.google.com/search?q=anx',
          engineHosts: const {'consent.google.com', 'www.google.com'},
        ),
        isTrue,
      );
      expect(
        keep(
          'https://consent.google.com/m?continue=www.google.com',
          engineHosts: const {'consent.google.com', 'www.google.com'},
        ),
        isTrue,
      );
      expect(
        keep(
          'https://www.reddit.com/r/PhilosophyofScience',
          engineHosts: const {'consent.google.com', 'www.google.com'},
        ),
        isFalse,
      );
    });
  });
}
