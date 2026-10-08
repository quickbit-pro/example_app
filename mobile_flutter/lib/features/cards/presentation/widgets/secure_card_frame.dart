// Embeds the issuer's secure card widget inside the flipped card face.
//
// Mobile uses a WebView; the browser build uses an iframe registered as a
// platform view (see `secure_card_frame_web.dart`). PAN, expiry and CVV are
// rendered by the provider SDK inside that frame and never pass through
// the app.
export 'secure_card_frame_stub.dart'
    if (dart.library.js_interop) 'secure_card_frame_web.dart';
