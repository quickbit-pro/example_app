// Browser "install app" (PWA) prompt bridge; a no-op outside the web build.
export 'web_install_prompt_stub.dart'
    if (dart.library.js_interop) 'web_install_prompt_web.dart';
