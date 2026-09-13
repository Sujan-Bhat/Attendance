package com.example.attendance_app

import android.content.Context
import android.util.Base64
import java.nio.ByteBuffer
import java.nio.ByteOrder

object LocalFaceStore {
    private const val PREF_KEY = "local_face_embedding"

    fun save(context: Context, embedding: FloatArray) {
        val bb = ByteBuffer.allocate(embedding.size * 4).order(ByteOrder.LITTLE_ENDIAN)
        for (v in embedding) bb.putFloat(v)
        val base64 = Base64.encodeToString(bb.array(), Base64.DEFAULT)
        val prefs = context.getSharedPreferences("face_prefs", Context.MODE_PRIVATE)
        prefs.edit().putString(PREF_KEY, base64).apply()
    }

    fun load(context: Context): FloatArray? {
        val prefs = context.getSharedPreferences("face_prefs", Context.MODE_PRIVATE)
        val base64 = prefs.getString(PREF_KEY, null) ?: return null
        val bytes = Base64.decode(base64, Base64.DEFAULT)
        val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        val floats = FloatArray(bytes.size / 4)
        for (i in floats.indices) floats[i] = bb.float
        return floats
    }
}
