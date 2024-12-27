package com.example.import_rknn

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** ImportRknnPlugin */
class ImportRknnPlugin: FlutterPlugin, MethodCallHandler {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
        private lateinit var channel : MethodChannel
    private var specSize: Int = 1 * 2 * 1 * 257
    private var stateSize: Int = 4 * 1 * 64 * 64

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "import_rknn")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "getPlatformVersion") {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        }else if(call.method == "test"){
            val text: String = stringFromJNI()
            setFloat16()
            result.success(text)
        }else if (call.method == "initModel"){
            val modelData = call.argument<ByteArray>("modelData")
            val modelLength = call.argument<Int>("modelLength")
//      Log.i("hello", "success in receiving data")
            if (modelData != null && modelLength != null) {
                val status = initModel(modelData, modelLength)
                result.success(status)
            } else {
                result.success(false)
            }
        }
        else if (call.method == "reset"){
            reset()
            result.success(true);
        }
        else if (call.method == "inference"){
            val mic = call.argument<FloatArray>("mic")
            val ref = call.argument<FloatArray>("ref")
//            val h = call.argument<FloatArray>("h")
//            val c = call.argument<FloatArray>("c")

//            val spec = FloatArray(specSize)
//            val w = FloatArray(specSize)
//            val ho = FloatArray(stateSize)
//            val co = FloatArray(stateSize)

            if (mic != null && ref != null){
//                val timeCost = measureTimeMillis {
//
//                }
//                inference(mic, ref, spec)
                val spec: FloatArray = inferenceWithOutput(mic, ref);
//                for (s: Float in spec){
//                    Log.i("kotlin", s.toString())
//                }
//                Log.i("kotlin", spec.toString())
                result.success(spec)
                // c端大概用时30ms左右，java端耗时与c端基本相同，传入flutter端大概会额外耗费2ms左右
//                Log.i("java", "java cost time: $timeCost")
            }
        }else if (call.method == "destroy"){
            destroy()
            result.success(true);
        }
//        else if (call.method == "initMobileNet"){
//            val modelData = call.argument<ByteArray>("modelData")
//            if (modelData != null){
//                initMobileModel(modelData);
//            }
//            result.success(true)
//        }else if (call.method == "runInference"){
//            val img = call.argument<ByteArray>("img")
//            Log.i("hello", "img has loaded")
//            if (img != null){
//                runInference(img)
//            }
//            result.success(true)
//        }
        else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private external fun stringFromJNI(): String
    private external fun initModel(modelData: ByteArray, modelLength: Int): Boolean
    private external fun destroy(): Void
    private external fun inference(mic: FloatArray, ref: FloatArray, spec: FloatArray): Int

    external fun inferenceWithOutput(mic: FloatArray, ref: FloatArray): FloatArray

    private external fun reset(): Void

    private external fun setFloat16(): Void
//    external fun initMobileModel(modelData: ByteArray): Boolean
//    external fun runInference(imgData: ByteArray): Boolean
    companion object {
        // Used to load the 'test_rknn' library on application startup.
        init {
            System.loadLibrary("test_rknn")
        }
    }
}
