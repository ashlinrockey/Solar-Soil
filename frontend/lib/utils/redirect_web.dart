import 'dart:html' as html;

Future<void> redirectTo(String url) async {
  html.window.localStorage.remove('solarsoil_session');
  html.window.sessionStorage.remove('solarsoil_session');
  html.window.location.href = url;
}
