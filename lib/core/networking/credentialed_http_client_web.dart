import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

http.Client createCredentialedHttpClient() {
  return BrowserClient()..withCredentials = true;
}
