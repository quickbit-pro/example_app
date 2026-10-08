/// A PDF prepared before a user chooses a browser action. Delivery methods
/// must invoke browser APIs synchronously, while the button gesture is active.
abstract interface class TransactionPdfDelivery {
  bool get canShare;
  bool open();
  void download();
  Future<bool> share();
  void dispose();
}
