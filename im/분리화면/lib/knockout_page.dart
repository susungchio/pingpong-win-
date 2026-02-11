import 'package:flutter/material.dart';
import 'models.dart';
import 'knockout_mobile_view.dart';
import 'knockout_tablet_view.dart';

class KnockoutPage extends StatelessWidget {
  final String tournamentTitle;
  final List<Round> rounds;
  final VoidCallback onDataChanged;
  final List<TournamentEvent> events;

  const KnockoutPage({
    super.key,
    required this.tournamentTitle,
    required this.rounds,
    required this.onDataChanged,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    // 화면 너비 600px 기준으로 모바일/태블릿 분기
    bool isTablet = MediaQuery.of(context).size.width > 600;

    if (isTablet) {
      return KnockoutTabletView(
        tournamentTitle: tournamentTitle,
        rounds: rounds,
        onDataChanged: onDataChanged,
        events: events,
      );
    } else {
      return KnockoutMobileView(
        tournamentTitle: tournamentTitle,
        rounds: rounds,
        onDataChanged: onDataChanged,
        events: events,
      );
    }
  }
}
