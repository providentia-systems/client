import 'package:web/web.dart' as web;

void scrubBrowserFragment() {
  final current = Uri.base;
  if (!current.hasFragment) return;
  web.window.history.replaceState(
    null,
    '',
    current.replace(fragment: '').toString(),
  );
}
