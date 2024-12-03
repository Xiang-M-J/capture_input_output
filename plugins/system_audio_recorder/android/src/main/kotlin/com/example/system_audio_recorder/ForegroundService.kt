package com.foregroundservice

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.example.system_audio_recorder.SystemAudioRecorderPlugin

class ForegroundService : Service() {
    private val CHANNEL_ID = "ForegroundService Kotlin"
    private val REQUEST_CODE_MEDIA_PROJECTION = 1001
    // 静态方法，SystemAudioRecorderPlugin 会调用这些方法
    companion object {
        fun startService(context: Context, title: String, message: String) {
            try {
                val startIntent = Intent(context, ForegroundService::class.java)
                startIntent.putExtra("messageExtra", message)
                startIntent.putExtra("titleExtra", title)

                ContextCompat.startForegroundService(context, startIntent)

            } catch (err: Exception) {
                println("startService err");
                println(err);
            }
        }

        fun stopService(context: Context) {
            val stopIntent = Intent(context, ForegroundService::class.java)
            context.stopService(stopIntent)
        }
    }
    // 在 SystemAudioRecorderPlugin 调用 ActivityCompat.startActivityForResult 时调用
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            Log.i("ForegroundService", "onStartCommand")
            // Verification permission en Android 14 (SDK 34)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION)
                    != PackageManager.PERMISSION_GRANTED) {
                    Log.i("Foreground","MediaProjection permission not granted, requesting permission")

                    ActivityCompat.requestPermissions(
                        this as Activity,
                        arrayOf(Manifest.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION),
                        REQUEST_CODE_MEDIA_PROJECTION
                    )
                } else {
                    startForegroundServiceWithNotification(intent)
                }
            } else {
                startForegroundServiceWithNotification(intent)
            }

            return START_NOT_STICKY
        } catch (err: Exception) {
            Log.e("ForegroundService", "onStartCommand error: $err")
        }
        return START_STICKY
    }
    private fun startForegroundServiceWithNotification(intent: Intent?) {

        createNotificationChannel()
        val notificationIntent = Intent(this, SystemAudioRecorderPlugin::class.java)

        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_MUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentIntent(pendingIntent)
            .build()

        startForeground(1, notification)
        Log.i("ForegroundService", "startForegroundServiceWithNotification")
    }

    override fun onBind(intent: Intent): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID, "Foreground Service Channel", NotificationManager.IMPORTANCE_DEFAULT
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager!!.createNotificationChannel(serviceChannel)
        }
    }

}