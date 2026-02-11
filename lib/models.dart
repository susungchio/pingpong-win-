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

class MasterPlayer {
  final int? id; 
  final String playerNumber;
  final String city;        
  final String affiliation; 
  final String name;        
  final String gender;      
  final String tier;        
  final String points;

  MasterPlayer({
    this.id,
    required this.playerNumber,
    required this.city,
    required this.affiliation,
    required this.name,
    required this.gender,
    required this.tier,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'playerNumber': playerNumber,
    'city': city,
    'affiliation': affiliation,
    'name': name,
    'gender': gender,
    'tier': tier,
    'points': points,
  };

  factory MasterPlayer.fromJson(Map<String, dynamic> json) => MasterPlayer(
    id: json['id'],
    playerNumber: json['playerNumber']?.toString() ?? '',
    city: json['city'] ?? '',
    affiliation: json['affiliation'] ?? '',
    name: json['name'] ?? '',
    gender: json['gender'] ?? '',
    tier: json['tier'] ?? '',
    points: json['points'] ?? '',
  );

  String get uniqueKey => '$name|$affiliation';
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
  int? nextMatchSlot; 
  int printCount; 

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
    this.printCount = 0,
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
  int groupSize; 
  int advancingCount; 
  int setsToWin; 
  bool randomSeeding;
  bool skipGroupStage;
  /// 부수설정 패널 표시 여부 (체크 시 17가지 부수 체크 목록 확장)
  bool showTierFilter;
  /// 부수설정에서 선택된 부수 명칭 목록 (1개 이상이면 아이콘/텍스트 강조)
  List<String> allowedTiers;

  TournamentSettings({
    this.groupSize = 3,
    this.advancingCount = 2,
    this.setsToWin = 2,
    this.randomSeeding = true,
    this.skipGroupStage = false,
    this.showTierFilter = false,
    List<String>? allowedTiers,
  }) : allowedTiers = allowedTiers ?? [];
}

class TournamentEvent {
  final String id;
  String name; 
  int teamSize; 
  List<Player> players;
  List<Group>? groups;
  List<Round>? knockoutRounds;
  List<Player>? lastQualified;
  TournamentSettings settings;

  TournamentEvent({
    required this.id,
    required this.name,
    this.teamSize = 1,
    List<Player>? players,
    this.groups,
    this.knockoutRounds,
    this.lastQualified,
    TournamentSettings? settings,
  }) : this.players = players ?? [],
       this.settings = settings ?? TournamentSettings();
}
