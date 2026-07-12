# ProGuard / R8 rules for FormulaDoc release builds.
#
# Currently INERT: minifyEnabled is set to false in app/build.gradle for the
# first release (see the comment there for why). These rules are wired up
# and ready for when minification is enabled after on-device testing.

# Flutter's own engine + plugin embedding classes are already covered by
# the Flutter Gradle plugin's bundled default rules — no extra keep rules
# needed for the framework itself.

# This app's own native bridge code (MainActivity, WmfRenderer) uses plain
# Kotlin method calls dispatched by string comparison (`when (call.method)`),
# not reflection — so it does not need explicit keep rules to survive R8
# renaming.

# If a specific plugin crashes only in release (never in debug) after
# minification is enabled, that is the classic signature of a missing
# consumer ProGuard rule for that plugin. The fix is almost always to add a
# -keep rule for the exact class named in the stack trace, e.g.:
#   -keep class com.example.someplugin.** { *; }
