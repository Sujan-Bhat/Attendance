package com.example.attendance_app

import android.content.Context
import android.graphics.Bitmap
import kotlin.math.sqrt

/**
 * Stub implementation of OfflineFaceVerifier.
 * TFLite model integration will be added once the model file is available.
 */
class OfflineFaceVerifier(context: Context) {

    fun extractEmbedding(bitmap: Bitmap): FloatArray {
        // Stub: returns a zero embedding until TFLite model is added
        return FloatArray(128) { 0f }
    }

    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        var dot = 0f; var normA = 0f; var normB = 0f
        for (i in a.indices) {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        val denom = sqrt(normA) * sqrt(normB)
        return if (denom == 0f) 0f else dot / denom
    }

    fun verify(live: FloatArray, stored: FloatArray, threshold: Float = 0.75f): Boolean {
        // Since we don't have a real TFLite model (assets/mobilefacenet.tflite is 0 bytes),
        // we will mock a successful match for offline testing purposes.
        return true
    }
}

