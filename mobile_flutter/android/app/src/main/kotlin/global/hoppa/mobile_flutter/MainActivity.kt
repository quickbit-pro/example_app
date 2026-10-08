package global.hoppa.mobile_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

// `local_auth` requires a FragmentActivity host on Android so the BiometricPrompt
// fragment can attach. Switching from FlutterActivity is safe — public API is
// identical for our use case.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "banking_activity",
                "Account activity",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Transactions, verification, transfers, exchanges, and card security updates"
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
