typedef PreviewMessageHandler = void Function(Map<String, dynamic> message);

void configurePreviewPlatform() {}

void Function() listenForPreviewMessages(PreviewMessageHandler handler) =>
    () {};

void sendPreviewMessage(Map<String, dynamic> message) {}
