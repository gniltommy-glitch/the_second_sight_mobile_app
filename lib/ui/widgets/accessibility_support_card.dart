import 'package:flutter/material.dart';

import '../../services/android_accessibility.dart';
import 'glass_card.dart';

class AccessibilitySupportCard extends StatelessWidget {
  const AccessibilitySupportCard({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AndroidAccessibilityScope.maybeOf(context);
    if (service == null || !service.supported) return const SizedBox.shrink();
    final active =
        service.systemReaderActive ||
        MediaQuery.of(context).accessibleNavigation;
    final known = service.touchExplorationEnabled != null;
    final status = active
        ? service.talkBackEnabled == true
              ? 'TalkBack đang bật'
              : 'Trình đọc màn hình hệ thống đang bật'
        : known
        ? 'Đang dùng giọng đọc của Aurelia'
        : 'Chưa xác định được trạng thái TalkBack';
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Hỗ trợ đọc màn hình',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(status)),
          const SizedBox(height: 8),
          Text(
            active
                ? 'Trình đọc của hệ thống đọc nội dung dưới ngón tay. '
                      'Aurelia tạm dừng đọc giao diện để tránh hai giọng cùng lúc. '
                      'Giọng dẫn đường và cảnh báo vẫn hoạt động.'
                : 'Khi chưa bật TalkBack, Aurelia đọc nút và văn bản khi bạn '
                      'lướt ngón tay. Bạn có thể bật TalkBack trong cài đặt Trợ năng '
                      'để được hỗ trợ trên toàn điện thoại.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.accessibility_new),
            label: const Text('Mở cài đặt TalkBack / Trợ năng'),
            onPressed: () async {
              final opened = await service.openSettings();
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Không mở được cài đặt. Vào Cài đặt điện thoại, '
                      'chọn Trợ năng rồi chọn TalkBack.',
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Với TalkBack: kéo một ngón tay để nghe, chạm đúp để '
            'kích hoạt và dùng hai ngón tay để cuộn.',
          ),
        ],
      ),
    );
  }
}
