import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kFontSizeKey   = 'pref_base_font_size';
const double kMinFontSize     = 11.0;
const double kMaxFontSize     = 26.0;
const double kDefaultFontSize = 16.0;

/// Global base font size for document text (persisted across sessions).
final fontSizeProvider =
    StateNotifierProvider<FontSizeNotifier, double>(
  (ref) => FontSizeNotifier(),
  name: 'fontSizeProvider',
);

class FontSizeNotifier extends StateNotifier<double> {
  FontSizeNotifier() : super(kDefaultFontSize) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_kFontSizeKey);
    if (saved != null) state = saved.clamp(kMinFontSize, kMaxFontSize);
  }

  Future<void> setSize(double size) async {
    state = size.clamp(kMinFontSize, kMaxFontSize);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontSizeKey, state);
  }

  Future<void> reset() => setSize(kDefaultFontSize);
}
