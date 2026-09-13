package com.example.attendance_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import android.graphics.Bitmap
import android.graphics.BitmapFactory

class MainActivity : FlutterFragmentActivity() {

    private val CAMERA_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var currentPhotoPath: String? = null
    private var scanModeOffline = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attendance_app/camera")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "captureImage" -> {
                        pendingResult = result
                        dispatchTakePictureIntent()
                    }
                    "setScanMode" -> {
                        // expects a boolean argument "offline"
                        val offline = call.argument<Boolean>("offline") ?: false
                        scanModeOffline = offline
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
            
        // Initialize the offline face verifier bridge
        FaceBridge(this, flutterEngine)
    }

    private fun dispatchTakePictureIntent() {
        val takePictureIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        if (takePictureIntent.resolveActivity(packageManager) != null) {
            val photoFile: File? = try {
                createImageFile()
            } catch (ex: Exception) {
                null
            }
            photoFile?.also {
                val photoURI: Uri = FileProvider.getUriForFile(
                    this,
                    "${packageName}.fileprovider",
                    it
                )
                takePictureIntent.putExtra(MediaStore.EXTRA_OUTPUT, photoURI)
                startActivityForResult(takePictureIntent, CAMERA_REQUEST_CODE)
            } ?: run {
                pendingResult?.error("FILE_ERROR", "Could not create image file", null)
                pendingResult = null
            }
        } else {
            pendingResult?.error("NO_CAMERA", "No camera app available", null)
            pendingResult = null
        }
    }

    private fun createImageFile(): File {
        val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val storageDir = getExternalFilesDir(Environment.DIRECTORY_PICTURES)
        return File.createTempFile("JPEG_${timeStamp}_", ".jpg", storageDir).apply {
            currentPhotoPath = absolutePath
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CAMERA_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && currentPhotoPath != null) {
                pendingResult?.success(currentPhotoPath)
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
            currentPhotoPath = null
        }
    }
}
