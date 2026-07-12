import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global theme-mode state.
/// Changing this immediately re-renders the entire app's MaterialApp.
final themeModeProvider = StateProvider<ThemeMode>(
  (ref) => ThemeMode.system,
  name: 'themeModeProvider',
);
