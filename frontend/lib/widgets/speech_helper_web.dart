import 'dart:js' as js;

bool isSpeechSupported() {
  try {
    final supported = js.context.callMethod('eval', [
      '!!(window.SpeechRecognition || window.webkitSpeechRecognition)'
    ]);
    return supported == true;
  } catch (_) {
    return false;
  }
}

Future<String> startSpeechRecognition() async {
  try {
    js.context.callMethod('eval', ['''
      (function() {
        var sr = window.SpeechRecognition || window.webkitSpeechRecognition;
        var r = new sr();
        r.lang = 'en-US';
        r.interimResults = false;
        r.continuous = false;
        r.onresult = function(e) {
          window._srResult = e.results[e.results.length - 1][0].transcript;
        };
        r.onerror = function() { window._srResult = ''; };
        r.onend = function() { window._srDone = true; };
        r.start();
      })()
    ''']);

    while (true) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (js.context['_srDone'] == true) {
        final transcript = js.context['_srResult'] as String? ?? '';
        js.context.callMethod('eval', [
          'delete window._srResult; delete window._srDone;'
        ]);
        return transcript;
      }
    }
  } catch (_) {
    return '';
  }
}
