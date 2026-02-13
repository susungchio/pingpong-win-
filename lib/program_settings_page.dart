import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'main.dart';
import 'models.dart';
import 'file_utils.dart';
import 'database_service.dart';

class ProgramSettingsPage extends StatefulWidget {
  final List<TournamentEvent> events;
  final String? currentFileName;
  final Function(File) onLoadFromFile;
  final Function(File, String) onDeleteFile;
  final Function(File, String) onEditTitle;
  final Function(String)? onDeleteEvent;

  const ProgramSettingsPage({
    super.key,
    this.events = const [],
    this.currentFileName,
    required this.onLoadFromFile,
    required this.onDeleteFile,
    required this.onEditTitle,
    this.onDeleteEvent,
  });

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

  final Map<String, bool> _eventCheckState = {};
  List<Map<String, dynamic>> _savedTournaments = [];
  String? _currentFile;
  final TextEditingController _dataPathController = TextEditingController();

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
    _dataPathController.text = FileUtils.currentBaseDir;
    _refreshSavedList();
  }

  Future<void> _refreshSavedList() async {
    try {
      final dataPath = await FileUtils.getDataDirPath();
      final directory = Directory(dataPath);
      if (!await directory.exists()) return;
      final entities = await directory.list().toList();
      final files = entities.where((f) => f.path.contains('tournament_') && f.path.endsWith('.json')).toList();
      List<Map<String, dynamic>> tempInfos = [];
      for (var f in files) {
        try {
          final content = await File(f.path).readAsString();
          final data = jsonDecode(content);
          tempInfos.add({
            'file': File(f.path),
            'title': data['title'] ?? '제목 없음',
            'fileName': f.path.split(Platform.pathSeparator).last,
            'updated': data['lastUpdated'] ?? '',
          });
        } catch (_) {}
      }
      tempInfos.sort((a, b) => (b['updated'] as String).compareTo(a['updated'] as String));
      setState(() { _savedTournaments = tempInfos; });
    } catch (e) { debugPrint('Refresh list error: $e'); }
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
    _dataPathController.dispose();
    super.dispose();
  }

  Widget _sidebarItem(IconData icon, String label, bool isSelected, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.amber : Colors.white, size: 20),
      title: Text(label, style: TextStyle(color: isSelected ? Colors.amber : Colors.white, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
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
          _sidebarItem(Icons.edit_document, '대회 설정 및 참가 등록', false, () => Navigator.pop(context)),
          _sidebarItem(Icons.storage_rounded, '기초 선수 DB 관리', false, () => Navigator.pop(context)),
          _sidebarItem(Icons.settings_applications_rounded, '프로그램 설정', true, () {}),
          const Spacer(),
          const Divider(color: Colors.white24, height: 1),
          const Padding(padding: EdgeInsets.all(16.0), child: Text('프로그램 설정', style: TextStyle(color: Colors.white24, fontSize: 10))),
        ],
      ),
    );
  }

  Widget _buildFontSettingRow(String label, String? currentVal, void Function(String?) onChanged, TextEditingController controller, Map<String, String?> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 32,
                  child: DropdownButtonFormField<String?>(
                    value: options.values.contains(currentVal) ? currentVal : null,
                    isDense: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0)),
                    items: options.entries.map((e) => DropdownMenuItem(value: e.value, child: Text(e.key, style: TextStyle(fontSize: 12, fontFamily: e.value)))).toList(),
                    onChanged: onChanged,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: '직접 입력', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0), isDense: true),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) => onChanged(v.isEmpty ? null : v),
                  ),
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

  Widget _buildEventCheckGrid() {
    if (widget.events.isEmpty) return Padding(padding: const EdgeInsets.only(top: 4), child: Text('대회 설정에서 추가한 종목이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)));
    final list = widget.events; final rows = <Widget>[];
    for (int i = 0; i < list.length; i += 2) {
      final left = list[i]; final right = i + 1 < list.length ? list[i + 1] : null;
      rows.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: _eventCheckTile(left)), if (right != null) ...[const SizedBox(width: 8), Expanded(child: _eventCheckTile(right))]])));
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
              SizedBox(width: 22, height: 22, child: Checkbox(value: checked, onChanged: (v) => _applyEventCheck(event.id, v ?? false), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, activeColor: const Color(0xFF1A535C))),
              const SizedBox(width: 6),
              Expanded(child: Text(event.name, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), onPressed: () => _handleDeleteEvent(event), padding: EdgeInsets.zero, constraints: const BoxConstraints(), tooltip: '종목 삭제'),
            ],
          ),
        ),
      ),
    );
  }

  void _handleDeleteEvent(TournamentEvent event) async {
    final savedPassword = await FileUtils.getAdminPassword();
    if (!mounted) return;
    final pwController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('시스템 비밀번호 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('경기종목을 삭제하려면 시스템 비밀번호를 입력하세요.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            TextField(controller: pwController, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: '시스템 비밀번호', border: OutlineInputBorder()), onSubmitted: (_) { if (pwController.text == savedPassword) { Navigator.pop(ctx); _confirmDeleteEvent(event); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('비밀번호가 틀렸습니다.'), backgroundColor: Colors.redAccent)); } }),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(onPressed: () { if (pwController.text == savedPassword) { Navigator.pop(ctx); _confirmDeleteEvent(event); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('비밀번호가 틀렸습니다.'), backgroundColor: Colors.redAccent)); } }, child: const Text('확인')),
        ],
      ),
    );
  }

  void _confirmDeleteEvent(TournamentEvent event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('경기종목 삭제'),
        content: Text('[${event.name}] 종목을 삭제하시겠습니까?\n\n※ 등록된 선수 명단이 함께 삭제됩니다.', style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(onPressed: () {
            Navigator.pop(ctx);
            if (widget.onDeleteEvent != null) {
              widget.onDeleteEvent!(event.id);
              _eventCheckState.remove(event.id);
              final next = Set<String>.from(eventUncheckedIdsNotifier.value);
              next.remove(event.id);
              eventUncheckedIdsNotifier.value = next;
              saveEventDisplayChecked(next);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('[${event.name}] 종목이 삭제되었습니다.'), duration: const Duration(seconds: 1)));
            }
          }, child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildSavedTournamentsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('저장된 대회 목록', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
        const SizedBox(height: 12),
        Container(
          height: 250,
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
          child: _savedTournaments.isEmpty
              ? const Center(child: Text('저장된 대회가 없음', style: TextStyle(color: Colors.grey, fontSize: 12)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _savedTournaments.length,
                  itemBuilder: (context, index) {
                    final info = _savedTournaments[index]; final bool isCurrent = _currentFile == info['fileName'];
                    return Card(
                      elevation: isCurrent ? 2 : 0, margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isCurrent ? const Color(0xFF1A535C) : Colors.transparent, width: 2)),
                      color: isCurrent ? Colors.white : Colors.white.withOpacity(0.7),
                      child: ListTile(
                        dense: true, leading: Icon(isCurrent ? Icons.check_circle : Icons.description_outlined, color: isCurrent ? const Color(0xFF1A535C) : Colors.grey, size: 20),
                        title: Text(info['title'], style: TextStyle(fontSize: 14, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? const Color(0xFF1A535C) : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('최근 수정: ${info['updated'].toString().split('T')[0]}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.edit_note, size: 20, color: Colors.blueGrey), onPressed: () => widget.onEditTitle(info['file'], info['title']).then((_) => _refreshSavedList()), tooltip: '제목 수정'),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent), onPressed: () => widget.onDeleteFile(info['file'], info['fileName']).then((_) => _refreshSavedList()), tooltip: '삭제'),
                        ]),
                        onTap: () async { await widget.onLoadFromFile(info['file']); setState(() { _currentFile = info['fileName']; }); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('[${info['title']}] 대회를 불러왔습니다.'), duration: const Duration(seconds: 1))); },
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
      ],
    );
  }

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
                const Row(children: [Icon(Icons.settings, color: Color(0xFF1A535C), size: 26), SizedBox(width: 10), Text('프로그램 설정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
                ElevatedButton.icon(
                  onPressed: () async {
                    // 관리자 비밀번호 확인
                    final isAuthorized = await _checkAdminPassword();
                    if (!isAuthorized) return;

                    final newSettings = FontSettings(titleFont: _tmpTitleFont, headerFont: _tmpHeaderFont, bodyFont: _tmpBodyFont);
                    appFontNotifier.value = newSettings;
                    await saveFontSettings(newSettings);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('영역별 폰트 설정이 저장 및 적용되었습니다.'), duration: Duration(seconds: 1)));
                  },
                  icon: const Icon(Icons.done_all, size: 18), label: const Text('모든 설정 저장 및 적용', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 1,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSavedTournamentsList(),
                        const SizedBox(height: 12),
                        const Text('영역별 폰트 설정', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                        const SizedBox(height: 10),
                        _buildFontSettingRow('대제목 (메인 이름)', _tmpTitleFont, (v) => setState(() { _tmpTitleFont = v; _titleFontController.text = v ?? ''; }), _titleFontController, _fontOptions),
                        _buildFontSettingRow('타이틀 (소제목/항목)', _tmpHeaderFont, (v) => setState(() { _tmpHeaderFont = v; _headerFontController.text = v ?? ''; }), _headerFontController, _fontOptions),
                        _buildFontSettingRow('내용 (선수 이름/일반)', _tmpBodyFont, (v) => setState(() { _tmpBodyFont = v; _bodyFontController.text = v ?? ''; }), _bodyFontController, _fontOptions),
                        const SizedBox(height: 12), const Divider(height: 1), const SizedBox(height: 10),
                        const Text('경기 종목', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                        const SizedBox(height: 6), Text('오늘 진행할 경기가 아닌 종목은 체크박스의 체크를 해제하시오.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        const SizedBox(height: 8), _buildEventCheckGrid(),
                        const SizedBox(height: 16), const Divider(height: 1), const SizedBox(height: 14),
                        const Text('시스템관리 비밀번호', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: TextField(controller: _systemPasswordController, obscureText: true, decoration: const InputDecoration(hintText: '비밀번호 입력', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true), style: const TextStyle(fontSize: 13))),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () async {
                                // 관리자 비밀번호 확인 (기존 비밀번호가 있는 경우)
                                final savedPassword = await FileUtils.getAdminPassword();
                                if (savedPassword.isNotEmpty && savedPassword != '1234') {
                                  final isAuthorized = await _checkAdminPassword();
                                  if (!isAuthorized) return;
                                }

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
                        const SizedBox(height: 16), _buildSettingInfoRow('프로그램 버전', 'v1.5.0'),
                        const SizedBox(height: 4), const Center(child: Text('© 2024 탁구 대회 매니저', style: TextStyle(fontSize: 10, color: Colors.grey))),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 1,
                  child: Container(color: Colors.white),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 1,
                  child: _buildPathSettingsPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 관리자 비밀번호 확인 다이얼로그
  Future<bool> _checkAdminPassword() async {
    final savedPassword = await FileUtils.getAdminPassword();
    
    // 비밀번호가 설정되지 않은 경우 바로 통과
    if (savedPassword.isEmpty || savedPassword == '1234') {
      return true;
    }

    final pwController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('시스템 관리자 비밀번호 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '이 작업을 수행하려면 시스템 관리자 비밀번호를 입력하세요.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pwController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '시스템 관리자 비밀번호',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (pwController.text == savedPassword) {
                  Navigator.pop(ctx, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('비밀번호가 틀렸습니다.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              if (pwController.text == savedPassword) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('비밀번호가 틀렸습니다.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  // 데이터 저장 경로 설정 패널
  Widget _buildPathSettingsPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.folder_outlined, color: Color(0xFF1A535C), size: 20),
              SizedBox(width: 8),
              Text(
                '데이터 저장 경로',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '대회 데이터가 저장되는 기본 경로를 설정합니다.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dataPathController,
                        decoration: InputDecoration(
                          hintText: '경로를 입력하거나 선택하세요',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                          if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
                            setState(() {
                              _dataPathController.text = selectedDirectory;
                            });
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('경로 선택 중 오류가 발생했습니다: $e'),
                                backgroundColor: Colors.redAccent,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('폴더 선택', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A535C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _dataPathController.text = FileUtils.currentBaseDir;
                        });
                      },
                      child: const Text('초기화', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        // 관리자 비밀번호 확인
                        final isAuthorized = await _checkAdminPassword();
                        if (!isAuthorized) return;

                        final newPath = _dataPathController.text.trim();
                        if (newPath.isEmpty) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('경로를 입력하세요.'),
                                backgroundColor: Colors.orange,
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                          return;
                        }

                        // 경로 유효성 검사
                        try {
                          final dir = Directory(newPath);
                          if (!await dir.exists()) {
                            // 디렉토리가 없으면 생성 시도
                            await dir.create(recursive: true);
                          }

                          // 경로 저장
                          await FileUtils.setBaseDir(newPath);
                          
                          // DB 재연결 (새 경로의 DB 사용)
                          try {
                            final dbService = DatabaseService();
                            await dbService.reconnectDatabase();
                          } catch (e) {
                            debugPrint('DB 재연결 오류: $e');
                          }
                          
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('데이터 저장 경로가 변경되었습니다.\n새 경로: $newPath\n\n※ 프로그램을 재시작하면 모든 기능이 새 경로에서 동작합니다.'),
                                duration: const Duration(seconds: 3),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('경로 설정 중 오류가 발생했습니다: $e'),
                                backgroundColor: Colors.redAccent,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A535C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        '경로 저장',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '현재 경로: ${FileUtils.currentBaseDir}\n\n※ 경로 변경 후 프로그램을 재시작하면 새 경로가 적용됩니다.',
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                  ),
                ),
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
      body: Row(children: [_buildSidebar(), Expanded(child: _buildSettingsContent())]),
    );
  }
}
