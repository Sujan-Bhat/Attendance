package com.example.attendance_app

import android.content.Context
import android.graphics.BitmapFactory
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class FaceBridge(private val context: Context, flutterEngine: FlutterEngine) {
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attendance_app/offline")
    private val verifier = OfflineFaceVerifier(context)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSavedFace" -> {
                    val saved = LocalFaceStore.load(context)
                    result.success(saved != null)
                }
                "registerOffline" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath == null) {
                        result.error("INVALID_ARGS", "imagePath is required", null)
                        return@setMethodCallHandler
                    }
                    val bitmap = BitmapFactory.decodeFile(imagePath)
                    if (bitmap == null) {
                        result.error("INVALID_IMAGE", "Could not decode image", null)
                        return@setMethodCallHandler
                    }
                    val embedding = verifier.extractEmbedding(bitmap)
                    LocalFaceStore.save(context, embedding)
                    result.success(true)
                }
                "verifyOffline" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath == null) {
                        result.error("INVALID_ARGS", "imagePath is required", null)
                        return@setMethodCallHandler
                    }
                    val bitmap = BitmapFactory.decodeFile(imagePath)
                    if (bitmap == null) {
                        result.error("INVALID_IMAGE", "Could not decode image", null)
                        return@setMethodCallHandler
                    }
                    val saved = LocalFaceStore.load(context)
                    if (saved == null) {
                        result.error("NO_SAVED_FACE", "No face registered offline", null)
                        return@setMethodCallHandler
                    }
                    val live = verifier.extractEmbedding(bitmap)
                    val success = verifier.verify(live, saved)
                    val similarity = verifier.cosineSimilarity(live, saved)
                    
                    result.success(mapOf("success" to success, "similarity" to similarity.toDouble()))
                }
                else -> result.notImplemented()
            }
        }
    }
}
