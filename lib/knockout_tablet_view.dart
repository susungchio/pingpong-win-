import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'knockout_print_logic.dart';
import 'group_stage_page.dart';
import 'knockout_page.dart';
import 'dart:math' as math;

class KnockoutTabletView extends StatefulWidget {
  final String tournamentTitle;
  final List<Round> rounds;
  final VoidCallback onDataChanged;
  final List<TournamentEvent> events;

  const KnockoutTabletView({
    super.key,
    required this.tournamentTitle,
    required this.rounds,
    required this.onDataChanged,
    required this.events,
  });

  @override
  State<KnockoutTabletView> createState() => _KnockoutTabletViewState();
}

class _KnockoutTabletViewState extends State<KnockoutTabletView> {
  // 단체전일 경우 넓이를 30% 크게 설정
  double get matchWidth => _isTeamMatch ? 220.0 * 1.3 : 220.0;
  // 단체전일 경우 라운드 간 간격도 30% 증가하여 연결선 위치 맞춤
  double get roundWidth => _isTeamMatch ? 280.0 * 1.3 : 280.0;
  
  // 단체전일 경우 박스 크기를 크게 설정
  double get matchHeight => _isTeamMatch ? 240.0 : 110.0;
  double get itemHeight => _isTeamMatch ? 320.0 : 170.0;

  final Set<String> _selectedMatchIds = {};
  // 대진표 뷰: 휠 = 세로 스크롤, Ctrl+휠 = 확대/축소
  double _bracketScale = 1.0;
  double _bracketOffsetX = 0.0;
  double _bracketOffsetY = 0.0;
  bool _bracketPointerDown = false;
  // 스티키 패널 (예선전과 동일: 오른쪽 고정, 투명도·온오프)
  bool _stickyPanelVisible = true;
  double _stickyPanelOpacity = 1.0;
  late final ScrollController _stickyScrollController;
  static final Map<String, double> _savedStickyScrollOffsets = {};
  // 종목별 본선 뷰(확대/위치) 상태 저장
  static final Map<String, double> _savedBracketScales = {};
  static final Map<String, Offset> _savedBracketOffsets = {};
  double _lastBracketViewW = 0;
  double _lastBracketViewH = 0;
  double _lastContentW = 0;
  double _lastContentH = 0;
  double _lastMinTx = 0;
  double _lastMaxTx = 0;
  double _lastMinTy = 0;
  double _lastMaxTy = 0;

  // 대회 기본 제목 추출 (예: "23회 대회 - 남자 단식" -> "23회 대회")
  String get _tournamentBaseTitle {
    if (widget.tournamentTitle.contains(' - ')) {
      return widget.tournamentTitle.split(' - ').first;
    }
    return widget.tournamentTitle;
  }

  // 현재 종목명 추출
  String get _eventName {
    if (widget.tournamentTitle.contains(' - ')) {
      return widget.tournamentTitle.split(' - ').last;
    }
    return widget.tournamentTitle;
  }

  bool get _isTeamMatch => _eventName.contains('단체');

  // 스티키 스크롤 상태를 종목별로 기억하기 위한 키
  String get _stickyEventKey => '$_tournamentBaseTitle - $_eventName';

  @override
  void initState() {
    super.initState();
    // 스티키 패널 스크롤 복원
    final initialOffset = _savedStickyScrollOffsets[_stickyEventKey] ?? 0.0;
    _stickyScrollController = ScrollController(initialScrollOffset: initialOffset);
    _stickyScrollController.addListener(() {
      _savedStickyScrollOffsets[_stickyEventKey] = _stickyScrollController.offset;
    });

    // 본선 확대/위치 상태 복원
    final savedScale = _savedBracketScales[_stickyEventKey];
    final savedOffset = _savedBracketOffsets[_stickyEventKey];
    if (savedScale != null) {
      _bracketScale = savedScale;
    }
    if (savedOffset != null) {
      _bracketOffsetX = savedOffset.dx;
      _bracketOffsetY = savedOffset.dy;
    }
  }

  @override
  void dispose() {
    _stickyScrollController.dispose();
    super.dispose();
  }

  /// 현재 본선 뷰 상태(확대/위치)를 종목별로 저장
  void _saveBracketViewState() {
    _savedBracketScales[_stickyEventKey] = _bracketScale;
    _savedBracketOffsets[_stickyEventKey] = Offset(_bracketOffsetX, _bracketOffsetY);
  }

  void _toggleMatchSelection(String matchId) {
    setState(() {
      if (_selectedMatchIds.contains(matchId)) {
        _selectedMatchIds.remove(matchId);
      } else {
        _selectedMatchIds.add(matchId);
        _propagateSelectionBackward(matchId);
      }
    });
  }

  void _propagateSelectionBackward(String targetMatchId) {
    for (int r = 1; r < widget.rounds.length; r++) {
      bool foundInRound = widget.rounds[r].matches.any((m) => m.id == targetMatchId);
      if (foundInRound) {
        for (var prevMatch in widget.rounds[r - 1].matches) {
          if (prevMatch.nextMatchId == targetMatchId) {
            bool isFinished = prevMatch.status == MatchStatus.completed || prevMatch.status == MatchStatus.withdrawal;
            if (!isFinished) {
              _selectedMatchIds.add(prevMatch.id);
              _propagateSelectionBackward(prevMatch.id);
            }
          }
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // rounds 비어 있으면 대진표 없음(크래시 방지)
    if (widget.rounds.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFF1A535C),
          foregroundColor: Colors.white,
          title: Text('$_tournamentBaseTitle - $_eventName', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('예선전', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text('메인', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ],
        ),
        body: const Center(child: Text('대진 정보가 없습니다.', style: TextStyle(fontSize: 16, color: Colors.grey))),
      );
    }
    int firstCount = widget.rounds[0].matches.length;
    const topBase = 20.0 + _roundLabelBottomPadding;
    // 마지막 경기 카드 하단까지 포함하도록 높이 계산 (축소 시에도 전체 박스가 보이도록)
    final lastCardBottom = (firstCount - 0.5) * itemHeight + topBase + matchHeight;
    double totalH = lastCardBottom + 100, totalW = (widget.rounds.length + 1) * roundWidth;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1A535C),
        foregroundColor: Colors.white,
        title: Text('$_tournamentBaseTitle - $_eventName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('예선전', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('메인', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: Icon(_stickyPanelVisible ? Icons.visibility : Icons.visibility_off, color: Colors.white),
            tooltip: _stickyPanelVisible ? '경기 입력 패널 숨기기' : '경기 입력 패널 보기',
            onPressed: () => setState(() => _stickyPanelVisible = !_stickyPanelVisible),
          ),
          if (_selectedMatchIds.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () async {
                await KnockoutPrintLogic.showPrintPreview(
                  context,
                  widget.tournamentTitle,
                  widget.rounds,
                  _selectedMatchIds,
                  () { setState(() {}); widget.onDataChanged(); },
                );
                setState(() => _selectedMatchIds.clear());
              },
              icon: const Icon(Icons.print, color: Colors.amber, size: 20),
              label: Text('${_selectedMatchIds.length}개 경기 출력', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
      body: Column(
        children: [
          // 경기 종목 나열 — 한글 세로 잘림 방지: 커스텀 칩으로 높이·패딩 완전 제어
          Material(
            elevation: 2,
            color: Colors.white,
            child: Container(
              height: 88,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              alignment: Alignment.centerLeft,
              child: widget.events.isEmpty
                  ? const Center(child: Text('등록된 종목이 없습니다.', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.events.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final e = widget.events[index];
                        final isSelected = e.name == _eventName;
                        return Material(
                          color: isSelected ? const Color(0xFF1A535C) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: isSelected
                                ? null
                                : () {
                                    final hasKnockout = e.knockoutRounds != null && e.knockoutRounds!.isNotEmpty;
                                    if (hasKnockout) {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => KnockoutPage(
                                                  tournamentTitle: '$_tournamentBaseTitle - ${e.name}',
                                                  rounds: e.knockoutRounds!,
                                                  onDataChanged: widget.onDataChanged,
                                                  events: widget.events,
                                                )),
                                      );
                                    } else {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => GroupStagePage(
                                                  tournamentBaseTitle: _tournamentBaseTitle,
                                                  allEvents: widget.events,
                                                  initialEventIdx: index,
                                                  onDataChanged: widget.onDataChanged,
                                                )),
                                      );
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Center(
                                child: Text(
                                  e.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : Colors.black87,
                                    height: 1.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          // 대진표 영역 + 오른쪽 스티키 패널 (예선전과 동일 위치)
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  right: 200,
                  bottom: 0,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const padding = 60.0;
                      final contentW = totalW + padding * 2;
                      final contentH = totalH + padding * 2;
                      final viewW = constraints.maxWidth;
                      final viewH = constraints.maxHeight;
                      final minTx = viewW - contentW * _bracketScale >= 0 ? 0.0 : viewW - contentW * _bracketScale;
                      final maxTx = 0.0;
                      final minTy = viewH - contentH * _bracketScale >= 0 ? 0.0 : viewH - contentH * _bracketScale;
                      final maxTy = 0.0;
                      _lastBracketViewW = viewW;
                      _lastBracketViewH = viewH;
                      _lastContentW = contentW;
                      _lastContentH = contentH;
                      _lastMinTx = minTx;
                      _lastMaxTx = maxTx;
                      _lastMinTy = minTy;
                      _lastMaxTy = maxTy;

                      // 축소 후에도 맨 아래까지 스크롤되도록: 표시/스크롤 모두 클램프된 값 사용
                      final clampedTx = _bracketOffsetX.clamp(minTx, maxTx).toDouble();
                      final clampedTy = _bracketOffsetY.clamp(minTy, maxTy).toDouble();

                      return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => setState(() => _bracketPointerDown = true),
                  onPointerUp: (_) => setState(() => _bracketPointerDown = false),
                  onPointerCancel: (_) => setState(() => _bracketPointerDown = false),
                  onPointerMove: (e) {
                    if (!_bracketPointerDown) return;
                    setState(() {
                      final curX = _bracketOffsetX.clamp(minTx, maxTx);
                      final curY = _bracketOffsetY.clamp(minTy, maxTy);
                      _bracketOffsetX = (curX + e.delta.dx).clamp(minTx, maxTx).toDouble();
                      _bracketOffsetY = (curY + e.delta.dy).clamp(minTy, maxTy).toDouble();
                      _saveBracketViewState();
                    });
                  },
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent) return;
                    final e = event as PointerScrollEvent;
                    final dy = e.scrollDelta.dy;
                    final dx = e.scrollDelta.dx;
                    final ctrl = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.control) ||
                        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
                    if (ctrl) {
                      setState(() {
                        final factor = dy > 0 ? 0.9 : 1.1;
                        _bracketScale = (_bracketScale * factor).clamp(0.5, 2.5).toDouble();
                        final newMinTx = viewW - contentW * _bracketScale >= 0 ? 0.0 : viewW - contentW * _bracketScale;
                        final newMinTy = viewH - contentH * _bracketScale >= 0 ? 0.0 : viewH - contentH * _bracketScale;
                        _bracketOffsetX = clampedTx.clamp(newMinTx, maxTx).toDouble();
                        _bracketOffsetY = clampedTy.clamp(newMinTy, maxTy).toDouble();
                        _saveBracketViewState();
                      });
                    } else {
                      setState(() {
                        final curX = _bracketOffsetX.clamp(minTx, maxTx);
                        final curY = _bracketOffsetY.clamp(minTy, maxTy);
                        final shift = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shift) ||
                            HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
                            HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                        _bracketOffsetX = (curX - (shift ? dy : dx)).clamp(minTx, maxTx).toDouble();
                        _bracketOffsetY = (curY - (shift ? dx : dy)).clamp(minTy, maxTy).toDouble();
                        _saveBracketViewState();
                      });
                    }
                  },
                  child: SizedBox.expand(
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topLeft,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          child: ClipRect(
                            child: Transform(
                              transform: Matrix4.identity()
                                ..scale(_bracketScale)
                                ..translate(clampedTx, clampedTy),
                              alignment: Alignment.topLeft,
                              child: Container(
                                width: contentW,
                                height: contentH,
                                padding: const EdgeInsets.all(padding),
                                child: Stack(clipBehavior: Clip.none, children: [
                                  CustomPaint(
                                    size: Size(totalW, totalH),
                                    painter: BracketLinkPainter(
                                      rounds: widget.rounds,
                                      matchWidth: matchWidth,
                                      matchHeight: matchHeight,
                                      roundWidth: roundWidth,
                                      itemHeight: itemHeight,
                                      activeColor: const Color(0xFF4ECDC4),
                                    ),
                                  ),
                                  ..._buildBracketNodes(),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                    },
                  ),
                ),
                if (_stickyPanelVisible)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: SizedBox(
                      width: 200,
                      child: _buildKnockoutStickyPanel(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 오른쪽 스티키 패널: 라운드별 경기 점수 입력용 빨간 박스, 투명도 조절·온오프
  Widget _buildKnockoutStickyPanel() {
    return Opacity(
      opacity: _stickyPanelOpacity.clamp(0.0, 1.0),
      child: Material(
        elevation: 4,
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: const Color(0xFF1A535C),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.sports_esports, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('경기 입력', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        const Text('투명도', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        Expanded(
                          child: Slider(
                            value: _stickyPanelOpacity,
                            onChanged: (v) => setState(() => _stickyPanelOpacity = v),
                            activeColor: Colors.white,
                            inactiveColor: Colors.white24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
            child: ListView(
              controller: _stickyScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (int r = 0; r < widget.rounds.length; r++) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(widget.rounds[r].name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A535C))),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(widget.rounds[r].matches.length, (m) => _buildStickyMatchBox(widget.rounds[r].matches[m], r, m)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  /// 스티키 패널 내 경기 박스: 종료=연한 파란, 진행 가능=빨간, 대기=회색. 클릭 시 해당 경기로만 이동(점수 다이얼로그 없음)
  Widget _buildStickyMatchBox(Match match, int roundIdx, int matchIdx) {
    final isFinished = match.status == MatchStatus.completed || match.status == MatchStatus.withdrawal;
    final canInput = match.player1 != null && match.player2 != null && !isFinished;
    final notReady = match.player1 == null || match.player2 == null;

    Color boxColor;
    Color borderColor;
    Color textColor;
    if (isFinished) {
      boxColor = const Color(0xFF4ECDC4).withOpacity(0.75);
      borderColor = const Color(0xFF4ECDC4);
      textColor = Colors.white;
    } else if (canInput) {
      boxColor = Colors.red.shade400;
      borderColor = Colors.red.shade700;
      textColor = Colors.white;
    } else {
      boxColor = Colors.grey.shade300;
      borderColor = Colors.grey.shade500;
      textColor = Colors.grey.shade700;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _scrollToMatch(roundIdx, matchIdx),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Text('${matchIdx + 1}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
        ),
      ),
    );
  }

  /// 스티키에서 경기 클릭 시 대진표 뷰를 해당 경기 위치로 이동
  void _scrollToMatch(int roundIdx, int matchIdx) {
    const padding = 60.0;
    final topBase = 20.0 + _roundLabelBottomPadding;
    final matchLeft = roundIdx * roundWidth;
    final topPos = (matchIdx * math.pow(2, roundIdx) + (math.pow(2, roundIdx) - 1) / 2) * itemHeight + topBase;
    final matchTop = topPos - 32;
    final matchX = padding + matchLeft;
    final matchY = padding + matchTop;
    final cardH = matchHeight + 32;
    final centerX = matchX + matchWidth / 2;
    final centerY = matchY + cardH / 2;
    final targetOffsetX = (_lastBracketViewW / 2) - centerX * _bracketScale;
    final targetOffsetY = (_lastBracketViewH / 2) - centerY * _bracketScale;
    setState(() {
      _bracketOffsetX = targetOffsetX.clamp(_lastMinTx, _lastMaxTx).toDouble();
      _bracketOffsetY = targetOffsetY.clamp(_lastMinTy, _lastMaxTy).toDouble();
      _saveBracketViewState();
    });
  }

  /// 128강 등 라운드 라벨과 최상단 경기 박스 사이 여백(픽셀)
  static const double _roundLabelBottomPadding = 30.0;

  List<Widget> _buildBracketNodes() {
    List<Widget> nodes = [];
    final topBase = 20.0 + _roundLabelBottomPadding; // 라벨 하단 30px 여백 후 경기 시작
    for (int r = 0; r < widget.rounds.length; r++) {
      nodes.add(Positioned(
          left: r * roundWidth,
          top: 0,
          child: Container(
              width: matchWidth,
              alignment: Alignment.center,
              child: Text(widget.rounds[r].name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A535C))))));
      for (int m = 0; m < widget.rounds[r].matches.length; m++) {
        double topPos = (m * math.pow(2, r) + (math.pow(2, r) - 1) / 2) * itemHeight + topBase;
        nodes.add(Positioned(left: r * roundWidth, top: topPos - 32, child: _buildMatchCard(widget.rounds[r].matches[m], r, m)));
      }
    }
    return nodes;
  }

  Widget _buildMatchCard(Match m, int roundIndex, int matchIndex) {
    bool isSelected = _selectedMatchIds.contains(m.id);
    bool isFinished = m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal;
    bool isFixed = m.player1 != null && m.player2 != null;
    
    Color cardColor = Colors.white;
    Color borderColor = Colors.grey.shade300;
    double borderWidth = 1.5;
    List<BoxShadow> shadows = [];

    if (isSelected) {
      cardColor = Colors.green.withOpacity(0.05);
      borderColor = Colors.green;
      borderWidth = 2.5;
    } else if (isFinished) {
      borderColor = const Color(0xFF4ECDC4);
      borderWidth = 2.0;
      shadows = [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))];
    } else if (isFixed) {
      cardColor = const Color(0xFFF7D9DD);
      borderColor = const Color(0xFFFF6B6B).withOpacity(0.5);
      borderWidth = 2.0;
      shadows = [BoxShadow(color: const Color(0xFFFF6B6B).withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))];
    }

    bool showIcon = false;
    if (m.status == MatchStatus.pending) {
      if (roundIndex == 0) { showIcon = !m.isBye; } 
      else if (roundIndex == 1) { showIcon = true; } 
      else {
        int start = matchIndex * 4;
        int end = (matchIndex + 1) * 4;
        bool ancestorsFinished = true;
        List<Match> grandParentMatches = widget.rounds[roundIndex - 2].matches;
        for (int i = start; i < end; i++) {
          if (i < grandParentMatches.length) {
            Match gpMatch = grandParentMatches[i];
            if (!(gpMatch.status == MatchStatus.completed || gpMatch.status == MatchStatus.withdrawal)) { ancestorsFinished = false; break; }
          }
        }
        showIcon = ancestorsFinished;
      }
    }
    if (showIcon && m.nextMatchId != null && _selectedMatchIds.contains(m.nextMatchId)) { showIcon = false; }
    if (_isTeamMatch && (m.player1 == null || m.player2 == null)) { showIcon = false; }

    return SizedBox(
      width: matchWidth,
      height: matchHeight + 32,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          if (showIcon)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleMatchSelection(m.id),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.green : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: isSelected ? Colors.green : Colors.blueGrey.withOpacity(0.3)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Icon(isSelected ? Icons.check : Icons.print, size: 18, color: isSelected ? Colors.white : Colors.blueGrey),
                    ),
                    if (m.printCount > 0)
                      Positioned(
                        right: -2, top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Text('${m.printCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Container(
              width: matchWidth,
              height: matchHeight,
              decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: shadows),
              child: InkWell(
                  onTap: (m.player1 == null || m.player2 == null) ? null : () {
                          setState(() {
                            _selectedMatchIds.remove(m.id);
                            if (m.status == MatchStatus.pending) m.status = MatchStatus.inProgress;
                          });
                          _showKnockoutScoreDialog(m);
                        },
                  onLongPress: showIcon ? () => _toggleMatchSelection(m.id) : null,
                  child: Column(children: [
                    _playerRow(m.player1, m.score1, m.winner == m.player1 && m.player1 != null, m.status == MatchStatus.withdrawal && m.score1 == -1),
                    const Divider(height: 1),
                    _playerRow(m.player2, m.score2, m.winner == m.player2 && m.player2 != null, m.status == MatchStatus.withdrawal && m.score2 == -1)
                  ]))),
        ],
      ),
    );
  }

  /// 경기 점수를 경기종목 버튼 색상(0xFF1A535C)의 동그라미에 프린트 아이콘처럼 표시
  Widget _scoreCircle(String text, bool isWinner, {bool withdrawn = false}) {
    final bgColor = withdrawn ? Colors.red.shade300 : (isWinner ? const Color(0xFF1A535C) : Colors.grey.shade300);
    final fgColor = (isWinner || withdrawn) ? Colors.white : Colors.black87;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: Colors.black26, width: 1),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: text.length > 2 ? 11 : 16, color: fgColor)),
    );
  }

  String _formatTeamMembers(String names) {
    if (names.isEmpty) return "";
    List<String> list = names.split(',').map((s) => s.trim()).toList();
    List<String> lines = [];
    // 한 줄에 2명씩, 최대 3줄까지 표시 (최대 6명)
    for (int i = 0; i < list.length && i < 6; i += 2) {
      if (i + 1 < list.length) {
        lines.add("${list[i]}, ${list[i+1]}");
      } else {
        lines.add(list[i]);
      }
    }
    return lines.join('\n');
  }

  Widget _playerRow(Player? p, int s, bool isW, bool withdrawn) {
    if (_isTeamMatch) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: isW ? const Color(0xFF1A535C).withOpacity(0.1) : Colors.transparent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 클럽명 표시
                    Text(
                      p?.affiliation ?? (p == null ? 'BYE' : 'TBD'), 
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 18, 
                        color: isW ? const Color(0xFF1A535C) : Colors.black
                      ), 
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 6),
                    // 선수명 표시 (한 줄에 2명씩, 최대 3줄)
                    if (p != null) 
                      ...List.generate(
                        (p.name.split(',').length / 2).ceil().clamp(0, 3),
                        (rowIndex) {
                          final startIdx = rowIndex * 2;
                          final endIdx = (startIdx + 2 < p.name.split(',').length) ? startIdx + 2 : p.name.split(',').length;
                          final teamMembers = p.name.split(',').map((s) => s.trim()).toList();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    teamMembers[startIdx],
                                    style: TextStyle(
                                      fontSize: 12, 
                                      color: isW ? const Color(0xFF1A535C) : Colors.black87, 
                                      fontWeight: FontWeight.w600
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (endIdx > startIdx + 1) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      teamMembers[startIdx + 1],
                                      style: TextStyle(
                                        fontSize: 12, 
                                        color: isW ? const Color(0xFF1A535C) : Colors.black87, 
                                        fontWeight: FontWeight.w600
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              _scoreCircle(withdrawn ? '기권' : '$s', isW),
            ],
          ),
        ),
      );
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        color: isW ? const Color(0xFF4ECDC4).withOpacity(0.1) : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, 
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text(p?.name ?? (p == null ? 'BYE' : 'TBD'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isW ? const Color(0xFF1A535C) : Colors.black), overflow: TextOverflow.ellipsis), 
                  if (p != null) 
                    Text(p.affiliation, style: TextStyle(fontSize: 13, color: isW ? const Color(0xFF1A535C) : Colors.black87, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)
                ]
              )
            ),
            _scoreCircle(withdrawn ? '기권' : '$s', isW, withdrawn: withdrawn),
          ],
        ),
      ),
    );
  }

  void _showKnockoutScoreDialog(Match m) {
    int s1 = m.score1 == -1 ? 0 : m.score1;
    int s2 = m.score2 == -1 ? 0 : m.score2;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
          builder: (context, setS) => Container(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Expanded(child: _playerPopupInfo(m.player1, textAlign: TextAlign.right)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('VS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey))),
                    Expanded(child: _playerPopupInfo(m.player2, textAlign: TextAlign.left)),
                  ]),
                  const SizedBox(height: 40),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_counter((v) => setS(() => s1 = v), s1), const Text(':', style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold)), _counter((v) => setS(() => s2 = v), s2)]),
                  const SizedBox(height: 30),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    ElevatedButton.icon(onPressed: () => setS(() { s1 = -1; s2 = 0; }), icon: const Icon(Icons.flag), label: const Text('P1 기권'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red)),
                    ElevatedButton.icon(onPressed: () => setS(() { s1 = 0; s2 = -1; }), icon: const Icon(Icons.flag), label: const Text('P2 기권'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red)),
                  ]),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        m.score1 = s1; m.score2 = s2;
                        if (s1 == -1 || s2 == -1) { m.status = MatchStatus.withdrawal; m.winner = s1 == -1 ? m.player2 : m.player1; }
                        else { m.status = MatchStatus.completed; m.winner = s1 > s2 ? m.player1 : m.player2; }
                        TournamentLogic.updateKnockoutWinner(widget.rounds, m);
                      });
                      Navigator.pop(context); widget.onDataChanged();
                    },
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 64), backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('점수 저장 및 확정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  )
                ]),
              )),
    );
  }

  Widget _playerPopupInfo(Player? p, {required TextAlign textAlign}) => Column(
          crossAxisAlignment: textAlign == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(_isTeamMatch ? (p?.affiliation ?? "TBD") : (p?.name ?? "TBD"), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            Text(_isTeamMatch ? (p?.name ?? "") : (p?.affiliation ?? ""), style: const TextStyle(fontSize: 15, color: Colors.orange, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
          ]);

  Widget _counter(Function(int) onU, int v) => Column(children: [
        IconButton(onPressed: () => onU(v + 1), icon: const Icon(Icons.add_circle, color: Color(0xFF4ECDC4), size: 56)),
        Text(v == -1 ? '기권' : '$v', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),
        IconButton(onPressed: () => onU(v > 0 ? v - 1 : 0), icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 56)),
      ]);
}

class BracketLinkPainter extends CustomPainter {
  final List<Round> rounds; final double matchWidth, matchHeight, roundWidth, itemHeight; final Color activeColor;
  BracketLinkPainter({required this.rounds, required this.matchWidth, required this.matchHeight, required this.roundWidth, required this.itemHeight, required this.activeColor});
  @override
  void paint(Canvas canvas, Size size) {
    final pBase = Paint()..color = Colors.grey.shade300..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final pActive = Paint()..color = activeColor..strokeWidth = 2.5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (int r = 0; r < rounds.length - 1; r++) {
      for (int m = 0; m < rounds[r].matches.length; m++) {
        final match = rounds[r].matches[m]; if (match.nextMatchId == null) continue;
        final nextMatch = rounds[r + 1].matches.firstWhere((nm) => nm.id == match.nextMatchId);

        const double topBase = 20.0 + 30.0; // 128강 라벨과 경기 박스 사이 30px 여백
        double sX = r * roundWidth + matchWidth, sY = (m * math.pow(2, r) + (math.pow(2, r) - 1) / 2) * itemHeight + topBase + (matchHeight / 2);
        double eX = (r + 1) * roundWidth, eY = (m ~/ 2 * math.pow(2, r + 1) + (math.pow(2, r + 1) - 1) / 2) * itemHeight + topBase + (matchHeight / 2);

        // 활성화 조건 수정: 현재 경기가 완료되었고 다음 경기가 시작되었을 때 + 다음 경기가 완료되었다면 승자 경로만 활성화
        bool isActive = (match.status == MatchStatus.completed || match.status == MatchStatus.withdrawal) && nextMatch.status != MatchStatus.pending;
        if (isActive && (nextMatch.status == MatchStatus.completed || nextMatch.status == MatchStatus.withdrawal)) {
          // 다음 경기가 끝났다면, 현재 경기의 승자가 다음 경기의 승자와 같을 때만 유지
          isActive = (nextMatch.winner != null && match.winner != null && nextMatch.winner!.id == match.winner!.id);
        }

        final path = Path()..moveTo(sX, sY)..lineTo(startXMid(sX, eX), sY)..lineTo(startXMid(sX, eX), eY)..lineTo(eX, eY);
        canvas.drawPath(path, isActive ? pActive : pBase);
      }
    }
  }

  double startXMid(double sX, double eX) => sX + (eX - sX) / 2;

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
