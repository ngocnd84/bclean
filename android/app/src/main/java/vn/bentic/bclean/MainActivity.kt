package vn.bentic.bclean

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import vn.bentic.bclean.ui.Analytics
import vn.bentic.bclean.ui.AppRoot
import vn.bentic.bclean.ui.AppViewModel
import vn.bentic.bclean.ui.BcleanTheme

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Analytics.log("app_open")
        setContent {
            BcleanTheme {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    Box(Modifier.fillMaxSize()) { AppRoot(vm) }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        vm.refreshAccess()
        vm.refreshStorage()
    }
}
