import 'package:flutter/material.dart';
import 'main.dart';

/// 프로그램 설정 전용 페이지. 왼쪽에 메인과 동일한 스타일의 사이드바를 두고, 오른쪽에 설정 콘텐츠 표시.
class ProgramSettingsPage extends StatefulWidget {
  const ProgramSettingsPage({super.key});

  @override
  State<ProgramSettingsPage> createState() => _ProgramSettingsPageState();
}

class _ProgramSettingsPageState extends State<ProgramSettingsPage> {
  final _titleFontController = TextEditingController();
  final _headerFontController = TextEditingController();
  final _bodyFontController = TextEditingController();

  String? _tmpTitleFont;
  String? _tmpHeaderFont;
  String? _tmpBodyFont;

  static const Map<String, String?> _fontOptions = {
    '시스템 기본': null,
    'SJ세종고딕': 'SJ세종고딕',
    'SJ정글고딕': 'SJ정글고딕',
    'SJ고은명조': 'SJ고은명조',
    'SJ정글명조': 'SJ정글명조',
    'SJ상큼오렌지': 'SJ상큼오렌지',
    '맑은 고딕': 'Malgun Gothic',
    '나눔고딕': 'NanumGothic',
  };

  @override
  void initState() {
    super.initState();
    _tmpTitleFont = appFontNotifier.value.titleFont;
    _tmpHeaderFont = appFontNotifier.value.headerFont;
    _tmpBodyFont = appFontNotifier.value.bodyFont;
    _titleFontController.text = _tmpTitleFont ?? '';
    _headerFontController.text = _tmpHeaderFont ?? '';
    _bodyFontController.text = _tmpBodyFont ?? '';
  }

  @override
  void dispose() {
    _titleFontController.dispose();
    _headerFontController.dispose();
    _bodyFontController.dispose();
    super.dispose();
  }

  Widget _sidebarItem(IconData icon, String label, bool isSelected, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.amber : Colors.white, size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.amber : Colors.white,
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: const Color(0xFF1A535C),
      child: Column(
        children: [
          const SizedBox(height: 50),
          const Icon(Icons.emoji_events_outlined, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          const Text('탁구 대회 매니저', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('PC/Tablet Edition', style: TextStyle(color: Colors.white54, fontSize: 11)),
          const Divider(color: Colors.white24, height: 40, indent: 30, endIndent: 30),
          // 메인으로 돌아가기: 대회 설정
          _sidebarItem(Icons.edit_document, '대회 설정 및 참가 등록', false, () => Navigator.pop(context)),
          _sidebarItem(Icons.storage_rounded, '기초 선수 DB 관리', false, () => Navigator.pop(context)),
          _sidebarItem(Icons.settings_applications_rounded, '프로그램 설정', true, () {}),
          const Spacer(),
          const Divider(color: Colors.white24, height: 1),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('프로그램 설정', style: TextStyle(color: Colors.white24, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildFontSettingRow(
    String label,
    String? currentVal,
    void Function(String?) onChanged,
    TextEditingController controller,
    Map<String, String?> options,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String?>(
                  value: options.values.contains(currentVal) ? currentVal : null,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: options.entries
                      .map((e) => DropdownMenuItem(value: e.value, child: Text(e.key, style: TextStyle(fontSize: 13, fontFamily: e.value))))
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '직접 입력',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => onChanged(v.isEmpty ? null : v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),
        ],
      ),
    );
  }

  Widget _buildSettingsContent() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.settings, color: Color(0xFF1A535C), size: 28),
                    SizedBox(width: 12),
                    Text('프로그램 설정', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final newSettings = FontSettings(
                      titleFont: _tmpTitleFont,
                      headerFont: _tmpHeaderFont,
                      bodyFont: _tmpBodyFont,
                    );
                    appFontNotifier.value = newSettings;
                    await saveFontSettings(newSettings);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('영역별 폰트 설정이 저장 및 적용되었습니다.'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.done_all),
                  label: const Text('모든 설정 저장 및 적용', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A535C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('영역별 폰트 설정', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 16)),
                  const SizedBox(height: 24),
                  _buildFontSettingRow(
                    '대제목 (메인 이름)',
                    _tmpTitleFont,
                    (v) => setState(() {
                      _tmpTitleFont = v;
                      _titleFontController.text = v ?? '';
                    }),
                    _titleFontController,
                    _fontOptions,
                  ),
                  _buildFontSettingRow(
                    '타이틀 (소제목/항목)',
                    _tmpHeaderFont,
                    (v) => setState(() {
                      _tmpHeaderFont = v;
                      _headerFontController.text = v ?? '';
                    }),
                    _headerFontController,
                    _fontOptions,
                  ),
                  _buildFontSettingRow(
                    '내용 (선수 이름/일반)',
                    _tmpBodyFont,
                    (v) => setState(() {
                      _tmpBodyFont = v;
                      _bodyFontController.text = v ?? '';
                    }),
                    _bodyFontController,
                    _fontOptions,
                  ),
                  const SizedBox(height: 48),
                  const Divider(height: 1),
                  const SizedBox(height: 24),
                  _buildSettingInfoRow('프로그램 버전', 'v1.5.0'),
                  const SizedBox(height: 8),
                  const Center(child: Text('© 2024 탁구 대회 매니저', style: TextStyle(fontSize: 10, color: Colors.grey))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildSettingsContent()),
        ],
      ),
    );
  }
}
