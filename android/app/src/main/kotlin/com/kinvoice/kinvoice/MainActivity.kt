package com.kinvoice.kinvoice

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.kinvoice.kinvoice/ambient_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAmbientService" -> {
                    AmbientAudioService.startService(this)
                    result.success(true)
                }
                "stopAmbientService" -> {
                    AmbientAudioService.stopService(this)
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(AmbientAudioService.isRunning)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
