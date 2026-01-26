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
