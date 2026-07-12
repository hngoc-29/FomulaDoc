import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

const double kMinLineSpacing = 1.0;
const double kMaxLineSpacing = 2.0;
const double kDefaultLineSpacing = 1.2; // matches the previous hardcoded value

const double kMinMargin = 0.0;
const double kMaxMargin = 40.0;
const double kDefaultMargin = 20.0; // matches AppConstants.documentHorizontalPadding

const _kReadingThemeKey = 'pref_reading_theme_mode';
const _kLineSpacingKey  = 'pref_line_spacing';
const _kMarginKey       = 'pref_reading_margin';

/// Reading-surface theme (Light / Sepia / Dark / High-contrast).
/// Independent of the app's system theme — persists across sessions.
final readingThemeProvider =
    StateNotifierProvider<ReadingThemeNotifier, ReadingThemeMode>(
  (ref) => ReadingThemeNotifier(),
  name: 'readingThemeProvider',
);

class ReadingThemeNotifier extends StateNotifier<ReadingThemeMode> {
  ReadingThemeNotifier() : super(ReadingThemeMode.light) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kReadingThemeKey);
    if (saved == null) return;
    state = ReadingThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ReadingThemeMode.light,
    );
  }

  Future<void> setMode(ReadingThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReadingThemeKey, mode.name);
  }
}

/// Line-height multiplier for document text (1.0–2.0).
final lineSpacingProvider =
    StateNotifierProvider<_DoublePrefNotifier, double>(
  (ref) => _DoublePrefNotifier(
    key: _kLineSpacingKey,
    initial: kDefaultLineSpacing,
    min: kMinLineSpacing,
    max: kMaxLineSpacing,
  ),
  name: 'lineSpacingProvider',
);

/// Horizontal reading margin in logical pixels (0–40).
final readingMarginProvider =
    StateNotifierProvider<_DoublePrefNotifier, double>(
  (ref) => _DoublePrefNotifier(
    key: _kMarginKey,
    initial: kDefaultMargin,
    min: kMinMargin,
    max: kMaxMargin,
  ),
  name: 'readingMarginProvider',
);

/// Generic persisted-double notifier, shared by line spacing and margin
/// (both are "a clamped double, saved under one SharedPreferences key").
class _DoublePrefNotifier extends StateNotifier<double> {
  final String key;
  final double min;
  final double max;

  _DoublePrefNotifier({
    required this.key,
    required double initial,
    required this.min,
    required this.max,
  }) : super(initial) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(key);
    if (saved != null) state = saved.clamp(min, max);
  }

  Future<void> setValue(double value) async {
    state = value.clamp(min, max);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, state);
  }

  Future<void> reset(double defaultValue) => setValue(defaultValue);
}
