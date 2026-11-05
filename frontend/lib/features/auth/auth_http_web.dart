import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

http.Client createAuthHttpClient() => BrowserClient()..withCredentials = true;
