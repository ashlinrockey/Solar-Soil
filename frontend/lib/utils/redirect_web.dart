import 'dart:html' as html;

Future<void> redirectTo(String url) async {
  html.window.location.href = url;
}
