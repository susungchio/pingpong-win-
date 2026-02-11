import 'dart:math';
import 'models.dart';

class TournamentLogic {
  static List<Group> generateGroups(List<Player> players, TournamentSettings settings) {
    List<Player> shuffledPlayers = List.from(players);
    if (settings.randomSeeding) shuffledPlayers.shuffle();
    int total = shuffledPlayers.length;
    if (total == 0) return [];
    int groupCount = (total / settings.groupSize).ceil();
    List<int> distribution = List.filled(groupCount, total ~/ groupCount);
    for (int i = 0; i < total % groupCount; i++) distribution[i]++;
    List<Group> groups = [];
    int currentIdx = 0;
    for (int i = 0; i < groupCount; i++) {
      int count = distribution[i];
      List<Player> groupPlayers = shuffledPlayers.sublist(currentIdx, currentIdx + count);
      currentIdx += count;
      groups.add(Group(name: '예선 ${i + 1}조', players: groupPlayers, matches: generateRoundRobin(groupPlayers, i + 1)));
    }
    return groups;
  }

  // 기존 기록 유지하며 경기 동기화
  static void syncGroupMatches(Group group, int groupIdx) {
    group.matches.removeWhere((m) => !group.players.contains(m.player1) || !group.players.contains(m.player2));
    for (int i = 0; i < group.players.length; i++) {
      for (int j = i + 1; j < group.players.length; j++) {
        Player p1 = group.players[i];
        Player p2 = group.players[j];
        bool exists = group.matches.any((m) => (m.player1?.id == p1.id && m.player2?.id == p2.id) || (m.player1?.id == p2.id && m.player2?.id == p1.id));
        if (!exists) {
          group.matches.add(Match(id: 'G${groupIdx}_${p1.id.substring(0,2)}${p2.id.substring(0,2)}', player1: p1, player2: p2));
        }
      }
    }
  }

  static List<Match> generateRoundRobin(List<Player> players, int groupIdx) {
    List<Match> matches = [];
    int n = players.length;
    List<List<int>> order = [];
    if (n == 3) order = [[0, 2], [1, 2], [0, 1]];
    else if (n == 4) order = [[0, 3], [1, 2], [0, 2], [1, 3], [0, 1], [2, 3]];
    else if (n == 5) order = [[0, 4], [1, 3], [0, 2], [4, 3], [1, 2], [0, 3], [4, 2], [1, 0], [3, 2], [4, 1]];
    else { for (int i = 0; i < n; i++) { for (int j = i + 1; j < n; j++) { order.add([i, j]); } } }
    for (var pair in order) {
      if (pair[0] < n && pair[1] < n) {
        matches.add(Match(id: 'G${groupIdx}_${pair[0]}${pair[1]}', player1: players[pair[0]], player2: players[pair[1]]));
      }
    }
    return matches;
  }

  static Map<Player, Map<String, int>> getRankingStats(Group group) {
    Map<Player, Map<String, int>> stats = { for (var p in group.players) p: {'wins': 0, 'won': 0, 'lost': 0, 'diff': 0, 'withdrawn': 0} };
    for (var match in group.matches) {
      if (match.status == MatchStatus.withdrawal) {
        if (match.score1 == -1 && match.player1 != null) stats[match.player1!]!['withdrawn'] = 1;
        if (match.score2 == -1 && match.player2 != null) stats[match.player2!]!['withdrawn'] = 1;
        continue;
      }
      if (match.status == MatchStatus.completed && match.player1 != null && match.player2 != null) {
        stats[match.player1!]!['won'] = stats[match.player1!]!['won']! + match.score1;
        stats[match.player1!]!['lost'] = stats[match.player1!]!['lost']! + match.score2;
        stats[match.player2!]!['won'] = stats[match.player2!]!['won']! + match.score2;
        stats[match.player2!]!['lost'] = stats[match.player2!]!['lost']! + match.score1;
        if (match.winner != null) stats[match.winner!]!['wins'] = stats[match.winner!]!['wins']! + 1;
      }
    }
    for (var p in group.players) { stats[p]!['diff'] = stats[p]!['won']! - stats[p]!['lost']!; }
    return stats;
  }

  static List<Player> getGroupRankings(Group group) {
    var stats = getRankingStats(group);
    List<Player> ranked = List.from(group.players);
    ranked.sort((a, b) {
      if (stats[a]!['withdrawn'] != stats[b]!['withdrawn']) return stats[a]!['withdrawn']!.compareTo(stats[b]!['withdrawn']!);
      int winCompare = stats[b]!['wins']!.compareTo(stats[a]!['wins']!);
      if (winCompare != 0) return winCompare;
      return stats[b]!['diff']!.compareTo(stats[a]!['diff']!);
    });
    return ranked;
  }

  static List<Round> generateKnockout(List<Player> qualifiedPlayers) {
    if (qualifiedPlayers.isEmpty) return [];
    int bracketSize = 2;
    while (bracketSize < qualifiedPlayers.length) bracketSize *= 2;
    List<Player?> seededPlayers = List.filled(bracketSize, null);
    List<int> seedOrder = _getSeedOrder(bracketSize);
    for (int i = 0; i < qualifiedPlayers.length; i++) { seededPlayers[seedOrder[i] - 1] = qualifiedPlayers[i]; }
    List<Round> rounds = [];
    List<Match> firstMatches = [];
    for (int i = 0; i < bracketSize ~/ 2; i++) {
      Player? p1 = seededPlayers[i * 2]; Player? p2 = seededPlayers[i * 2 + 1];
      Match m = Match(id: 'R1_M$i', player1: p1, player2: p2);
      if (p1 != null && p2 == null) { m.winner = p1; m.status = MatchStatus.completed; }
      else if (p1 == null && p2 != null) { m.winner = p2; m.status = MatchStatus.completed; }
      else if (p1 == null && p2 == null) { m.status = MatchStatus.completed; }
      firstMatches.add(m);
    }
    rounds.add(Round(name: '${bracketSize}강', matches: firstMatches));
    int currentMatchesCount = bracketSize ~/ 4;
    int roundIdx = 2;
    while (currentMatchesCount >= 1) {
      String rName = currentMatchesCount == 1 ? '결승' : '${currentMatchesCount * 2}강';
      List<Match> currentMatches = List.generate(currentMatchesCount, (i) => Match(id: 'R${roundIdx}_M$i'));
      for (int i = 0; i < currentMatchesCount; i++) {
        rounds[roundIdx - 2].matches[i * 2].nextMatchId = currentMatches[i].id;
        rounds[roundIdx - 2].matches[i * 2].nextMatchSlot = 1;
        rounds[roundIdx - 2].matches[i * 2 + 1].nextMatchId = currentMatches[i].id;
        rounds[roundIdx - 2].matches[i * 2 + 1].nextMatchSlot = 2;
      }
      rounds.add(Round(name: rName, matches: currentMatches));
      currentMatchesCount ~/= 2; roundIdx++;
    }
    _propagateWinners(rounds);
    return rounds;
  }

  static List<int> _getSeedOrder(int size) {
    List<int> seeds = [1];
    int currentSize = 1;
    while (currentSize < size) {
      List<int> nextSeeds = []; int nextSum = currentSize * 2 + 1;
      for (int s in seeds) { nextSeeds.add(s); nextSeeds.add(nextSum - s); }
      seeds = nextSeeds; currentSize *= 2;
    }
    return seeds;
  }

  static void _propagateWinners(List<Round> rounds) {
    for (int r = 0; r < rounds.length - 1; r++) {
      for (var m in rounds[r].matches) {
        if (m.status == MatchStatus.completed && m.winner != null && m.nextMatchId != null) {
          Match next = rounds[r + 1].matches.firstWhere((nm) => nm.id == m.nextMatchId);
          if (m.nextMatchSlot == 1) next.player1 = m.winner; else next.player2 = m.winner;
        }
      }
    }
  }

  static void updateKnockoutWinner(List<Round> rounds, Match m) {
    if (m.winner == null || m.nextMatchId == null) return;
    for (int i = 0; i < rounds.length - 1; i++) {
      try {
        Match next = rounds[i + 1].matches.firstWhere((nm) => nm.id == m.nextMatchId);
        if (m.nextMatchSlot == 1) next.player1 = m.winner; else next.player2 = m.winner;
        break;
      } catch (_) {}
    }
  }
}
