import 'dart:js' as js;

String csrfToken() {
  try {
    final doc = js.context['document'];
    if (doc == null) return '';
    final cookie = doc['cookie'] as String? ?? '';
    final match = RegExp(r'(?:^| )csrf_token=([^;]+)').firstMatch(cookie);
    return match?.group(1) ?? '';
  } catch (_) {
    return '';
  }
}
