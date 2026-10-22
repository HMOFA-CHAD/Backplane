package dev.backplane.mobile

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun ViewStartupBanner(m: AppModel) {
    val hub = m.screen?.hub.orEmpty()
    val key = if (hub.isNotEmpty()) hub.takeIf { m.startup[it] == StartupPolicy.COMPATIBILITY_REQUIRED }
        else m.startup.keys.sorted().firstOrNull { m.startup[it] == StartupPolicy.COMPATIBILITY_REQUIRED }
    if (key != null) Surface {
        Column(Modifier.fillMaxWidth().padding(10.dp)) {
            // a hub without views (older than 0.12.0): it needs an update;
            // the app never downloads a hub's whole history
            Text("This hub needs an update · $key", style = MaterialTheme.typography.labelSmall)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = { m.retryView(key) }) { Text("Retry") }
            }
        }
    }
}
