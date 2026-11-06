/// A local display hint for support screenshots, never an authentication signal.
String browserNameForUserAgent(String userAgent) {
  if (RegExp(r'Edg(A|iOS)?/', caseSensitive: false).hasMatch(userAgent)) {
    return 'Edge';
  }
  if (RegExp(r'OPR/|Opera|OPiOS/|OPT/', caseSensitive: false)
      .hasMatch(userAgent)) {
    return 'Opera';
  }
  if (userAgent.contains('SamsungBrowser/')) {
    return 'Samsung Internet';
  }
  if (userAgent.contains('FxiOS/') || userAgent.contains('Firefox/')) {
    return 'Firefox';
  }
  if (userAgent.contains('Brave/')) {
    return 'Brave';
  }
  if (userAgent.contains('GSA/')) {
    return 'Google app';
  }
  if (RegExp(r'FBAN|FBAV|Instagram', caseSensitive: false)
      .hasMatch(userAgent)) {
    return 'In-app browser';
  }
  if (userAgent.contains('Chromium/')) {
    return 'Chromium';
  }
  if (userAgent.contains('Chrome/') || userAgent.contains('CriOS/')) {
    return 'Chrome';
  }
  if (userAgent.contains('Safari/') && userAgent.contains('Version/')) {
    return 'Safari';
  }
  return 'Browser';
}
