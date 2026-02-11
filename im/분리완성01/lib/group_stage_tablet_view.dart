import 'package:flutter/material.dart';
import 'models.dart';

class GroupStageTabletView extends StatefulWidget {
  final String tournamentBaseTitle;
  final List<TournamentEvent> allEvents;
  final int initialEventIdx;
  final VoidCallback onDataChanged;

  const GroupStageTabletView({
    super.key,
    required this.tournamentBaseTitle,
    required this.allEvents,
    required this.initialEventIdx,
    required this.onDataChanged,
  });

  @override
  State<GroupStageTabletView> createState() => _GroupStageTabletViewState();
}

class _GroupStageTabletViewState extends State<GroupStageTabletView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('예선 관리 (태블릿/PC)')),
      body: const Center(child: Text('예선 조별 리그 태블릿용 디자인 (여러 조를 한눈에 배치)')),
    );
  }
}
