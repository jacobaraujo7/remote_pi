package work.jacobmoura.remotepi

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hardware volume keys as a text-size shortcut.
 *
 * The keys are CONSUMED here rather than merely observed: while enabled, volume
 * up/down steps the app's text size and does NOT change media volume. That can
 * only be decided natively, because it has to happen synchronously — before the
 * system handles the key — so Dart pushes the enablement down (`setEnabled`) and
 * receives the presses back (`volumeKey`). Settings → Display carries the toggle
 * that gives the keys back to the system.
 *
 * [dispatchKeyEvent] rather than `onKeyDown` because it is the first stop for
 * hardware keys, and because consuming only ACTION_DOWN would let the matching
 * ACTION_UP still reach the system.
 *
 * iOS is untouched: it has no equivalent of this channel, so the Dart side sees
 * a missing plugin and does nothing.
 */
class MainActivity : FlutterActivity() {
    private var volumeKeysEnabled = false
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setEnabled" -> {
                            volumeKeysEnabled = call.arguments as? Boolean ?: false
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeKeysEnabled) {
            val direction =
                when (event.keyCode) {
                    KeyEvent.KEYCODE_VOLUME_UP -> "up"
                    KeyEvent.KEYCODE_VOLUME_DOWN -> "down"
                    else -> null
                }
            if (direction != null) {
                // Fire once per physical press; repeats (key held down) are
                // swallowed so the shortcut doesn't race through the scale.
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    channel?.invokeMethod("volumeKey", direction)
                }
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    companion object {
        private const val CHANNEL = "work.jacobmoura.remotepi/volume_keys"
    }
}
