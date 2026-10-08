import 'invoice_picker_native.dart'
    if (dart.library.js_interop) 'invoice_picker_web.dart' as platform;
export 'invoice_file.dart';

class InvoicePicker extends platform.InvoicePicker {}
