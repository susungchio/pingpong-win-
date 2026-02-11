import 'package:flutter/material.dart';
import 'main.dart';
import 'models.dart';

/// 프로그램 설정 전용 페이지. 왼쪽에 메인과 동일한 스타일의 사이드바를 두고, 오른쪽에 설정 콘텐츠 표시.
class ProgramSettingsPage extends StatefulWidget {
  /// 대회 설정에서 추가한 경기종목 목록 (없으면 빈 목록)
  final List<TournamentEvent> events;

  const ProgramSettingsPage({super.key, this.events = const []});

  @override
  State<ProgramSettingsPage> createState() => _ProgramSettingsPageState();
}

class _ProgramSettingsPageState extends State<ProgramSettingsPage> {
  final _titleFontController = TextEditingController();
  final _headerFontController = TextEditingController();
  final _bodyFontController = TextEditingController();
  final _systemPasswordController = TextEditingController();

  String? _tmpTitleFont;
  String? _tmpHeaderFont;
  String? _tmpBodyFont;

  /// 경기종목별 체크 상태 (종목 id → 체크 여부). 기본값 true.
  final Map<String, bool> _eventCheckState = {};

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
    final unchecked = eventUncheckedIdsNotifier.value;
    for (var e in widget.events) {
      _eventCheckState[e.id] = !unchecked.contains(e.id);
    }
  }

  void _applyEventCheck(String eventId, bool checked) {
    setState(() => _eventCheckState[eventId] = checked);
    final next = Set<String>.from(eventUncheckedIdsNotifier.value);
    if (checked) {
      next.remove(eventId);
    } else {
      next.add(eventId);
    }
    eventUncheckedIdsNotifier.value = next;
    saveEventDisplayChecked(next);
  }

  @override
  void dispose() {
    _titleFontController.dispose();
    _headerFontController.dispose();
    _bodyFontController.dispose();
    _systemPasswordController.dispose();
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
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
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

  /// 한 줄에 2개씩 경기종목 + 체크박스 배치
  Widget _buildEventCheckGrid() {
    if (widget.events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('대회 설정에서 추가한 종목이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      );
    }
    final list = widget.events;
    final rows = <Widget>[];
    for (int i = 0; i < list.length; i += 2) {
      final left = list[i];
      final right = i + 1 < list.length ? list[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _eventCheckTile(left)),
              if (right != null) ...[const SizedBox(width: 8), Expanded(child: _eventCheckTile(right))],
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _eventCheckTile(TournamentEvent event) {
    final checked = _eventCheckState[event.id] ?? true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _applyEventCheck(event.id, !checked),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: checked,
                  onChanged: (v) => _applyEventCheck(event.id, v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: const Color(0xFF1A535C),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(event.name, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 설정 콘텐츠: 세로로 3등분하여 왼쪽 1/3에 영역별 폰트 설정(여백 적게), 나머지 영역은 여유 공간
  Widget _buildSettingsContent() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.settings, color: Color(0xFF1A535C), size: 26),
                    SizedBox(width: 10),
                    Text('프로그램 설정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('모든 설정 저장 및 적용', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A535C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 왼쪽 1/3: 영역별 폰트 설정 (여백 적게)
                Expanded(
                  flex: 1,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('영역별 폰트 설정', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        const Text('경기 종목', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text('오늘 진행할 경기가 아닌 종목은 체크박스의 체크를 해제하시오.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        const SizedBox(height: 8),
                        _buildEventCheckGrid(),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        const Text('시스템관리 비밀번호', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _systemPasswordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  hintText: '비밀번호 입력',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () async {
                                final pwd = _systemPasswordController.text;
                                await saveSystemAdminPassword(pwd);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(pwd.isEmpty ? '비밀번호가 해제되었습니다.' : '시스템관리 비밀번호가 저장되었습니다.'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A535C),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                              child: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSettingInfoRow('프로그램 버전', 'v1.5.0'),
                        const SizedBox(height: 4),
                        const Center(child: Text('© 2024 탁구 대회 매니저', style: TextStyle(fontSize: 10, color: Colors.grey))),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                // 중간 1/3: 여유 영역 (추후 확장용)
                Expanded(flex: 1, child: Container(color: Colors.white)),
                const VerticalDivider(width: 1),
                // 오른쪽 1/3: 여유 영역 (추후 확장용)
                Expanded(flex: 1, child: Container(color: Colors.white)),
              ],
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
