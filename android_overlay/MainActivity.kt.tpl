package __PACKAGE__

import android.content.Context
import android.net.ConnectivityManager
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ru.iskolesil/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeBytes" -> {
                        val path = call.argument<String>("path")
                        if (path == null) result.error("ARG", "path", null)
                        else result.success(StatFs(path).availableBytes)
                    }
                    "isMetered" -> {
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        result.success(cm.isActiveNetworkMetered)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
