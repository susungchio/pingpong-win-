import 'package:flutter/material.dart';
import 'models.dart';
import 'group_stage_mobile_view.dart';
import 'group_stage_tablet_view.dart';

class GroupStagePage extends StatelessWidget {
  final String tournamentBaseTitle;
  final List<TournamentEvent> allEvents;
  final int initialEventIdx;
  final VoidCallback onDataChanged;

  const GroupStagePage({
    super.key,
    required this.tournamentBaseTitle,
    required this.allEvents,
    required this.initialEventIdx,
    required this.onDataChanged,
  });

  @override
  Widget build(BuildContext context) {
    bool isTablet = MediaQuery.of(context).size.width > 600;

    if (isTablet) {
      return GroupStageTabletView(
        tournamentBaseTitle: tournamentBaseTitle,
        allEvents: allEvents,
        initialEventIdx: initialEventIdx,
        onDataChanged: onDataChanged,
      );
    } else {
      return GroupStageMobileView(
        tournamentBaseTitle: tournamentBaseTitle,
        allEvents: allEvents,
        initialEventIdx: initialEventIdx,
        onDataChanged: onDataChanged,
      );
    }
  }
}
