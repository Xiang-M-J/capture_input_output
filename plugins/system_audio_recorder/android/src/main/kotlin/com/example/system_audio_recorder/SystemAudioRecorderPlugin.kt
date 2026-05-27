package com.example.system_audio_recorder

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.NoiseSuppressor
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import com.foregroundservice.ForegroundService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

class ByteArrayUtils{
    private val byteArray: MutableList<Byte> = mutableListOf()
    private val lock = Any()

    fun add(bytes: ByteArray){
        synchronized(lock){
            byteArray.addAll(bytes.toList())
        }
    }

    fun slice(length: Int): ByteArray{
        if (byteArray.size < length){
            throw IllegalArgumentException("length is too big")
        }

//        val result: MutableList<Byte> = mutableListOf()
//
//        for (i: Int in 0 until length){
//            result.add(byteArray.removeAt(0))
//        }
//        Log.i("Hll", result.size.toString())
//        return result.toByteArray()
        synchronized(lock){
            val slice = byteArray.subList(0, length).toByteArray()
            byteArray.subList(0, length).clear()
//            repeat(length) {byteArray.removeAt(0)}
            return slice
        }

    }

    fun test(length: Int): Boolean{
        synchronized(lock){
            return byteArray.size > length
        }
    }

    fun clear(){
        synchronized(lock){
            byteArray.clear()
        }
    }
}

/** SystemAudioRecorderPlugin */
class SystemAudioRecorderPlugin : MethodCallHandler, PluginRegistry.ActivityResultListener,
    FlutterPlugin,
    ActivityAware {

    private lateinit var channel: MethodChannel
    private var mProjectionManager: MediaProjectionManager? = null
    private var mMediaProjection: MediaProjection? = null
    private var mFileName: String? = ""
    private val RECORD_REQUEST_CODE = 333
    var TAG: String = "system_audio_recorder"
    private var eventSink: EventSink? = null

    private lateinit var _result: Result

    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var activityBinding: ActivityPluginBinding? = null;
    private var iRecordingThread: Thread? = null
    private var oRecordingThread: Thread? = null
    private var fRecordingThread: Thread? = null

    //    private var recordingThread: Thread? = null
//    private var recordingThread: Thread? = null
    private var bufferSize = 512
    private var mAudioRecord: AudioRecord? = null
    private var mAudioFormat: AudioFormat? = null
    private var isRecording: Boolean = false
    private var sampleRate: Int = 16000
    private var micRecord: AudioRecord? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var binaryMessenger: BinaryMessenger? = null
    private lateinit var eventChannel: EventChannel
    private val readBufferSize: Int = 512
    private val bufferSizeInBytes: Int = 1280

    private var syncStart: Boolean = true
//    @Volatile
//    private var queue1: ArrayBlockingQueue<ByteArray> = ArrayBlockingQueue(10)  // 队列1
//    @Volatile
//    private var queue2: ArrayBlockingQueue<ByteArray> = ArrayBlockingQueue(10)

    private var array1: ByteArrayUtils = ByteArrayUtils()

    private var array2: ByteArrayUtils = ByteArrayUtils()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
//    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "system_audio_recorder")
//    channel.setMethodCallHandler(this)
        pluginBinding = flutterPluginBinding
        binaryMessenger = flutterPluginBinding.binaryMessenger

//    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "")
        eventChannel = EventChannel(binaryMessenger, "system_audio_recorder/audio_stream")
        eventChannel.setStreamHandler(
            object : StreamHandler {
                override fun onListen(args: Any, events: EventSink?) {
                    Log.i(TAG, "Adding listener")
                    eventSink = events
                    if (eventSink == null) {
                        Log.e(TAG, "EventSink is null")
                    }
                }
                override fun onCancel(args: Any) {
                    eventSink = null
                }
            }
        )
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    // 在 ForegroundService 的startCommand执行完后执行
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == RECORD_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                mMediaProjection = mProjectionManager?.getMediaProjection(resultCode, data!!)
                _result.success(true)
                return true
            } else {
                _result.success(false)
            }
        }
        return false
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun onMethodCall(call: MethodCall, result: Result) {
        val appContext = pluginBinding!!.applicationContext

        if (call.method == "getPlatformVersion") {
            result.success("Android ${Build.VERSION.RELEASE}")
        }
        else if (call.method == "openRecorder"){
            val sampleRate = call.argument<Int?>("sampleRate")
            if (sampleRate != null){
                this.sampleRate = sampleRate
            }
            val bufferSize = call.argument<Int?>("bufferSize")
            if (bufferSize != null){
                this.bufferSize = bufferSize
            }
//            openInputRecorder()

            mAudioFormat = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(this.sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .build()
        }
        else if (call.method == "requestRecord") {
            try {
                _result = result

                ForegroundService.startService(appContext, "开始录音", "开始录音")
                mProjectionManager =
                    appContext.getSystemService(
                        Context.MEDIA_PROJECTION_SERVICE
                    ) as MediaProjectionManager?

                val permissionIntent = mProjectionManager?.createScreenCaptureIntent()
                Log.i(TAG, "startActivityForResult")
                // 调用 ForegroundService的 startCommand 方法
                ActivityCompat.startActivityForResult(
                    activityBinding!!.activity,
                    permissionIntent!!,
                    RECORD_REQUEST_CODE,
                    null
                )
//                Log.i(TAG, "openOutputRecorder")

            } catch (e: Exception) {
                Log.e(TAG, "Error onMethodCall startRecord: ${e.message}")
                result.success(false)
            }
        } else if (call.method == "startRecord") {
            try {
                val isStart = startRecording()
                if (isStart){
                    result.success(true)
                }else{
                    result.success(false)
                }
            } catch (e: Exception) {
                result.success(false)
            }
        } else if (call.method == "stopRecord") {
            Log.i(TAG, "stopRecord")
            try {
                ForegroundService.stopService(appContext)
                if (mAudioRecord != null) {
                    stopRecording()
                    result.success(mFileName)
                } else {
                    result.success("")
                }
            } catch (e: Exception) {
                result.success("")
            }
        } else if (call.method == "dispose"){
            Log.i(TAG, "dispose")
            try {
                dispose()
            }catch (e: Exception){
                e.printStackTrace()
            }
        }
        else {
            result.notImplemented()
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    fun openInputRecorder(){
        if (micRecord == null){
            micRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSizeInBytes
            )
//            if (NoiseSuppressor.isAvailable()){
//                Log.i(TAG, "NoiseSuppressor is available")
//                noiseSuppressor = NoiseSuppressor.create(micRecord!!.audioSessionId)
//                noiseSuppressor!!.setEnabled(true);
//            }else{
//                Log.i(TAG, "NoiseSuppressor is not available")
//            }
        }
    }

    @RequiresApi(api = Build.VERSION_CODES.Q)
    fun openOutputRecorder(mProjection: MediaProjection): Boolean{
        if (mAudioRecord == null) {
            Log.i(TAG, "openOutputRecorder")
            mAudioFormat = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(this.sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .build()
            val config: AudioPlaybackCaptureConfiguration
            try {
                config = AudioPlaybackCaptureConfiguration.Builder(mProjection)
                    .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(AudioAttributes.USAGE_GAME)
                    .build()
            } catch (e: NoClassDefFoundError) {
                return false
            }
            mAudioRecord = AudioRecord.Builder().setAudioFormat(mAudioFormat!!)
                .setBufferSizeInBytes(bufferSizeInBytes).setAudioPlaybackCaptureConfig(config)
                .build()
        }
        return true
    }


    @RequiresApi(api = Build.VERSION_CODES.Q)
    fun startRecording(): Boolean {
        Log.i(TAG, "startRecording")
//        openInputRecorder()
        openOutputRecorder(mMediaProjection!!)
//        if (mAudioRecord == null || micRecord == null) {
//           return false
//        }
        if (mAudioRecord == null){
            return false
        }

        mAudioRecord!!.startRecording()
//        micRecord!!.startRecording()

        isRecording = true
//        iRecordingThread = Thread({ saveData(micRecord, array1, 0) }, "Input Audio Capture")
//        oRecordingThread = Thread({ saveData(mAudioRecord, array2, 1)}, "Output Audio Capture")
//        fRecordingThread = Thread({ recording()}, "send data")

        oRecordingThread = Thread({sendData(mAudioRecord)}, "Send output capture")

//        iRecordingThread!!.start()
        oRecordingThread!!.start()
//        fRecordingThread!!.start()
        return true
    }

    private fun recording() {
        try {
            while (isRecording){
//                if (array1.test(bufferSize) && array2.test(bufferSize)){
//
//                    val data1 = array1.slice(bufferSize)
//                    val data2 = array2.slice(bufferSize)
//                    activityBinding!!.activity.runOnUiThread {
//                        val map = mapOf("input" to data1, "output" to data2)
//                        eventSink?.success(map)
//                    }
//                }
                if (array2.test(bufferSize)){

                    val data2 = array2.slice(bufferSize)
                    activityBinding!!.activity.runOnUiThread {
                        eventSink?.success(data2)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun sendData(audioRecord: AudioRecord?) {
        try {

            val buffer = ByteArray(readBufferSize)
            while (isRecording) {
                val read = audioRecord?.read(buffer, 0, readBufferSize) ?: 0

                if (read > 0){

//                    if (syncStart){
//                        startTime[index] = true
//                    }
                    val data = buffer.copyOf(read)
                    activityBinding!!.activity.runOnUiThread {
                        eventSink?.success(data)
                    }

//                    array.add(data)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun saveData(audioRecord: AudioRecord?, array: ByteArrayUtils, index: Int) {
        try {

            val buffer = ByteArray(readBufferSize)
            while (isRecording) {
                val read = audioRecord?.read(buffer, 0, readBufferSize) ?: 0

                if (read > 0){

//                    if (syncStart){
//                        startTime[index] = true
//                    }

                    val data = buffer.copyOf(read)
                    array.add(data)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopRecording() {

        isRecording = false
        syncStart = true
//        startTime[0] = false
//        startTime[1] = false
        array1.clear()
        array2.clear()
        mAudioRecord!!.stop()
        mAudioRecord!!.release()
        if (mAudioRecord != null){
            mAudioRecord = null
        }
        if (micRecord != null){
            micRecord!!.stop()
            micRecord!!.release()
            micRecord = null
        }

        iRecordingThread = null
        oRecordingThread = null
        fRecordingThread = null
    }

    private fun dispose(){
        if (mAudioRecord != null){
            mAudioRecord!!.stop()
            mAudioRecord!!.release()
            mAudioRecord = null
        }
        if (micRecord != null){
            micRecord!!.stop()
            micRecord!!.release()
            micRecord = null
        }
        iRecordingThread = null
        oRecordingThread = null
        fRecordingThread = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
//    if (channel != null) {
//      channel.setMethodCallHandler(null);
//      channel = null;
//    }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding;
        channel = MethodChannel(pluginBinding!!.binaryMessenger, "system_audio_recorder")
        channel.setMethodCallHandler(this)
        activityBinding!!.addActivityResultListener(this);
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding;
    }

    override fun onDetachedFromActivity() {}
}
