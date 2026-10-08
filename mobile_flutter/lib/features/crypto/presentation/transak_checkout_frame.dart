// Embeds the hosted Transak checkout inside the app: an iframe platform view
// in the browser build, a WebView on Android and iOS.
export 'transak_checkout_frame_mobile.dart'
    if (dart.library.js_interop) 'transak_checkout_frame_web.dart';
