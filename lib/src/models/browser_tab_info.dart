/// Information about a browser tab extracted from window title metadata.
///
/// This model is only populated when the focused application is recognised
/// as a desktop browser (Chrome, Edge, Firefox, Brave, Safari, etc.) and
/// when the native platform code successfully parsed the window title.
class BrowserTabInfo {
  /// Domain part of the website (e.g. `stackoverflow.com`).
  final String? domain;

  /// Full URL constructed from the domain if available (e.g. `https://stackoverflow.com`).
  final String? url;

  /// Page title (cleaned, without the browser-name suffix).
  final String title;

  /// Browser type in lowercase (`chrome`, `edge`, `firefox`, ...).
  final String browserType;

  const BrowserTabInfo({
    this.domain,
    this.url,
    required this.title,
    required this.browserType,
  });

  factory BrowserTabInfo.fromJson(Map<String, dynamic> json) {
    return BrowserTabInfo(
      domain: json['domain'] as String?,
      url: json['url'] as String?,
      title: json['title'] as String? ?? '',
      browserType: json['browserType'] as String? ?? 'browser',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'domain': domain,
      'url': url,
      'title': title,
      'browserType': browserType,
    }..removeWhere((_, v) => v == null);
  }

  @override
  String toString() => 'BrowserTabInfo(domain: $domain, title: $title, browserType: $browserType)';
}
