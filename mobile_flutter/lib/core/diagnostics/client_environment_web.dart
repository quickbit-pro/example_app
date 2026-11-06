import 'package:web/web.dart' as web;
import 'browser_name.dart';

String currentClientEnvironment() =>
    browserNameForUserAgent(web.window.navigator.userAgent);
