package com.formuladoc.app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Single entry point activity using Flutter's Android v2 embedding.
 *
 * Exposes two MethodChannels:
 *   • `formuladoc/wmf` — WMF-to-PNG conversion for legacy Equation Editor
 *     3.x / MathType objects embedded in DOCX files.
 *   • `formuladoc/shortcuts` — relays which static app shortcut (long-press
 *     launcher icon → "Gần đây" / "Chọn file") launched the activity, if any.
 *
 * Shortcut handling uses a PULL model (Dart calls `getPendingShortcutAction`
 * once at startup) rather than a push/invokeMethod-from-native model, since
 * pushing immediately in onCreate()/onNewIntent() would race with the
 * Flutter engine + Dart-side channel listener not being ready yet. The
 * activity uses launchMode="singleTop" (see AndroidManifest.xml), so a
 * shortcut tap while the app is already running arrives via onNewIntent()
 * rather than a fresh onCreate() — both paths are handled here.
 */
class MainActivity : FlutterActivity() {

    private val WMF_CHANNEL = "formuladoc/wmf"
    private val SHORTCUTS_CHANNEL = "formuladoc/shortcuts"
    private val renderer = WmfRenderer()

    private var pendingShortcutAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingShortcutAction = intent?.getStringExtra("shortcut_action")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = intent.getStringExtra("shortcut_action")
        if (action != null) pendingShortcutAction = action
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WMF_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "renderWmf" -> {
                        val wmfBytes = call.arguments as? ByteArray
                        if (wmfBytes == null) {
                            result.error("INVALID_ARG", "Expected ByteArray argument", null)
                            return@setMethodCallHandler
                        }
                        // Run on background thread to avoid blocking the UI
                        Thread {
                            try {
                                val png = renderer.render(wmfBytes)
                                runOnUiThread {
                                    if (png != null) result.success(png)
                                    else result.error("RENDER_FAILED", "WMF render returned null", null)
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("RENDER_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHORTCUTS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingShortcutAction" -> {
                        // Consume-once: clear after reading so a Dart hot
                        // restart or later re-read doesn't re-trigger the
                        // same shortcut action repeatedly.
                        val action = pendingShortcutAction
                        pendingShortcutAction = null
                        result.success(action)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

