import 'package:shared_preferences/shared_preferences.dart';

const _kTotalSecondsKey   = 'stats_total_read_seconds';
const _kDocsOpenedKey     = 'stats_docs_opened';
const _kStreakCountKey    = 'stats_streak_days';
const _kLastActiveDateKey = 'stats_last_active_date'; // yyyy-MM-dd

class ReadingStats {
  final Duration totalReadTime;
  final int      documentsOpened;
  final int      currentStreak;

  const ReadingStats({
    required this.totalReadTime,
    required this.documentsOpened,
    required this.currentStreak,
  });
}

/// Tracks lightweight reading-engagement stats, purely local (no analytics
/// sent anywhere) — shown to the user in Settings as a small motivational
/// summary.
class ReadingStatsService {
  Future<ReadingStats> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    return ReadingStats(
      totalReadTime:   Duration(seconds: prefs.getInt(_kTotalSecondsKey) ?? 0),
      documentsOpened: prefs.getInt(_kDocsOpenedKey) ?? 0,
      currentStreak:   prefs.getInt(_kStreakCountKey) ?? 0,
    );
  }

  /// Call when the viewer screen closes, with how long it was open.
  /// Very short sessions (<3s — likely an accidental open/immediate back)
  /// are not counted, to keep the total meaningful.
  Future<void> recordSession(Duration elapsed) async {
    if (elapsed.inSeconds < 3) return;
    final prefs = await SharedPreferences.getInstance();
    final total = (prefs.getInt(_kTotalSecondsKey) ?? 0) + elapsed.inSeconds;
    await prefs.setInt(_kTotalSecondsKey, total);
  }

  /// Call once per successful document open.
  Future<void> recordDocumentOpened() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_kDocsOpenedKey) ?? 0) + 1;
    await prefs.setInt(_kDocsOpenedKey, count);
    await _recordDailyActivity(prefs);
  }

  Future<void> _recordDailyActivity(SharedPreferences prefs) async {
    final today = _dateKey(DateTime.now());
    final last  = prefs.getString(_kLastActiveDateKey);

    if (last == today) return; // already counted today

    final streak = prefs.getInt(_kStreakCountKey) ?? 0;
    if (last == null) {
      await prefs.setInt(_kStreakCountKey, 1);
    } else {
      final lastDate = _parseDateKey(last);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final isConsecutive = lastDate != null &&
          _dateKey(lastDate) == _dateKey(yesterday);
      await prefs.setInt(_kStreakCountKey, isConsecutive ? streak + 1 : 1);
    }
    await prefs.setString(_kLastActiveDateKey, today);
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}
