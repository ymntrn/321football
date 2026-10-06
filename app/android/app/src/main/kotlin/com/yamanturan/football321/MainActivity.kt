package com.yamanturan.football321

import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "football321/asset_copy",
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method != "copy") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val asset = call.argument<String>("asset")
            val dest = call.argument<String>("dest")
            if (asset == null || dest == null) {
                result.error("bad_args", "asset and dest are required", null)
                return@setMethodCallHandler
            }
            copyAsset(channel, asset, dest, result)
        }
    }

    /**
     * Streams a bundled Flutter asset to [dest] in 1 MB chunks, off the main
     * thread, reporting progress back to Dart.
     *
     * This replaces `rootBundle.load()`, which pulls the whole 62 MB database
     * into memory before a byte is written — slow on a cold start and a real
     * memory spike on a small phone.
     *
     * Writes to `<dest>.part` and renames at the end, so a copy killed half
     * way never leaves a truncated database where the real one should be.
     * (The version stamp is only written after this returns, so the next
     * launch would redo the copy regardless.)
     */
    private fun copyAsset(
        channel: MethodChannel,
        asset: String,
        dest: String,
        result: MethodChannel.Result,
    ) {
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
        Thread {
            try {
                val tmp = File("$dest.part")
                var total = -1L
                assets.open(key).use { input ->
                    // For an asset stream, available() is the remaining
                    // UNCOMPRESSED length, so this is the true total even
                    // though the APK stores the file compressed.
                    total = input.available().toLong().takeIf { it > 0 } ?: -1L
                    FileOutputStream(tmp).use { out ->
                        val buffer = ByteArray(1 shl 20)
                        var done = 0L
                        var reported = 0L
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            out.write(buffer, 0, n)
                            done += n
                            // Every 2 MB: often enough to move the bar
                            // smoothly, rare enough not to flood the channel.
                            if (done - reported >= (2L shl 20)) {
                                reported = done
                                val d = done
                                val t = total
                                runOnUiThread {
                                    channel.invokeMethod(
                                        "progress",
                                        mapOf("done" to d, "total" to t),
                                    )
                                }
                            }
                        }
                        out.fd.sync()
                    }
                }
                val target = File(dest)
                if (target.exists() && !target.delete()) {
                    throw IOException("could not replace $dest")
                }
                if (!tmp.renameTo(target)) {
                    throw IOException("could not rename ${tmp.name}")
                }
                runOnUiThread { result.success(total) }
            } catch (e: Exception) {
                runOnUiThread { result.error("copy_failed", e.message, null) }
            }
        }.start()
    }
}
