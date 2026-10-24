import 'dart:convert';

/// Configuration supplied locally by a helper. Never include it in logs.
class PairingConfig {
  final String endpoint, token;
  final String? routingKey;
  final bool allowInsecure;
  const PairingConfig(
    this.endpoint,
    this.token,
    this.routingKey,
    this.allowInsecure,
  );

  static PairingConfig parse(String raw) {
    const invalid = FormatException(
      'QR cấu hình không hợp lệ. Nhờ người hỗ trợ tạo lại mã SecondSight.',
    );
    if (raw.length > 8192) throw invalid;
    dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      throw invalid;
    }
    if (data is! Map ||
        data['type'] != 'secondsight_pairing' ||
        data['version'] != 1) {
      throw invalid;
    }
    final endpoint = data['endpoint'];
    final token = data['token'];
    final key = data['routing_key'];
    if (endpoint is! String ||
        token is! String ||
        token.trim().isEmpty ||
        token.length > 1024 ||
        (key != null && key is! String) ||
        (data['allow_insecure'] != null && data['allow_insecure'] is! bool)) {
      throw invalid;
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw invalid;
    }
    final insecure = data['allow_insecure'] == true;
    if (uri.scheme == 'http' && !insecure) throw invalid;
    return PairingConfig(endpoint.trim(), token.trim(), key?.trim(), insecure);
  }
}
