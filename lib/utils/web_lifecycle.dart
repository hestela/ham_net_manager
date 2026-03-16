// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

html.EventListener? _beforeUnloadHandler;

void setBeforeUnloadWarning(bool enable) {
  final html.EventListener? existing = _beforeUnloadHandler;
  if (existing != null) {
    html.window.removeEventListener('beforeunload', existing);
    _beforeUnloadHandler = null;
  }
  if (enable) {
    void handler(html.Event event) {
      (event as html.BeforeUnloadEvent).returnValue = '';
    }
    _beforeUnloadHandler = handler;
    html.window.addEventListener('beforeunload', handler);
  }
}
