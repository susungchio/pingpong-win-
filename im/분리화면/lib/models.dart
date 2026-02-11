import 'dart:math';

class Player {
  final String id;
  final String name;
  final String affiliation;

  Player({required this.id, required this.name, required this.affiliation});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Player && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

enum MatchStatus { pending, inProgress, completed, withdrawal }

class Match {
  final String id;
  Player? player1;
  Player? player2;
  int score1;
  int score2;
  MatchStatus status;
  Player? winner;
  String? nextMatchId;
  int? nextMatchSlot; // 1: player1, 2: player2
  int printCount; // [추가] 인쇄 횟수 추적

  Match({
    required this.id,
    this.player1,
    this.player2,
    this.score1 = 0,
    this.score2 = 0,
    this.status = MatchStatus.pending,
    this.winner,
    this.nextMatchId,
    this.nextMatchSlot,
    this.printCount = 0, // [기본값 0]
  });

  bool get isBye => (player1 == null && player2 != null) || (player1 != null && player2 == null);
}

class Group {
  final String name;
  final List<Player> players;
  final List<Match> matches;

  Group({required this.name, required this.players, required this.matches});
}

class Round {
  final String name;
  final List<Match> matches;

  Round({required this.name, required this.matches});
}

class TournamentSettings {
  int groupSize; // 예선 조별 인원 (3-5)
  int advancingCount; // 본선 진출 인원 (2-5)
  int setsToWin; // 2: 3전 2선승, 3: 5전 3선승
  bool randomSeeding;

  TournamentSettings({
    this.groupSize = 3,
    this.advancingCount = 2,
    this.setsToWin = 2,
    this.randomSeeding = true,
  });
}

/// 여러 경기 종목(이벤트)을 관리하기 위한 클래스
class TournamentEvent {
  final String id;
  String name; // 경기 종목 이름 (예: 남자 1~3부)
  int teamSize; // [추가] 1: 개인전, 2~5: 단체전 인원
  List<Player> players;
  List<Group>? groups;
  List<Round>? knockoutRounds;
  List<Player>? lastQualified;
  TournamentSettings settings;

  TournamentEvent({
    required this.id,
    required this.name,
    this.teamSize = 1, // 기본값은 개인전(1)
    List<Player>? players,
    this.groups,
    this.knockoutRounds,
    this.lastQualified,
    TournamentSettings? settings,
  }) : this.players = players ?? [],
       this.settings = settings ?? TournamentSettings();
}
