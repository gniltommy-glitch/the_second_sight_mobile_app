/// Browser WebSockets cannot set the bearer handshake header required by Pi.
class PiSocket {
  static PiSocket connect(Uri uri, String token) => throw UnsupportedError(
    'Kết nối kính cần ứng dụng Android/iOS. Web chỉ xem giao diện hoặc mô phỏng.',
  );
  Future<void> get ready => Future.value();
  Stream<dynamic> get stream => const Stream.empty();
  void send(String text) {}
  Future<void> close() async {}
}
