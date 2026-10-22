import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createCredentialedHttpClient() =>
    IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 30));
