package dev.backplane.mobile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

// The viewer's Review tab (client.bend's Rp, mobile/view.bend's Rv.json): a
// chip per page, the page's title and the report as Markdown (the apps'
// own; its tables scroll sideways), or what to say while there is none.
// Refresh sits at the bottom, under the thumb.
@Composable
fun ReviewScreen(m: AppModel, v: Viewer, r: ReviewPage) {
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface).statusBarsPadding().navigationBarsPadding()) {
        ViewerChoices(m, v)
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (t in r.tabs) FilterChip(t.on, onClick = { m.act("rv-page", t.page) }, label = { Text(t.label) })
        }
        Text(r.title, Modifier.padding(horizontal = 16.dp, vertical = 8.dp), style = MaterialTheme.typography.titleMedium, maxLines = 2)
        HorizontalDivider()
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (r.blocks.isNotEmpty() && !r.busy) {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) { Markdown(r.blocks) }
            } else {
                Column(Modifier.align(Alignment.Center).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    if (r.busy) CircularProgressIndicator()
                    Text(r.note, color = MaterialTheme.colorScheme.outline, textAlign = TextAlign.Center)
                }
            }
        }
        HorizontalDivider()
        Button(onClick = { m.act("rv-run", "") }, enabled = !r.busy, modifier = Modifier.fillMaxWidth().padding(12.dp)) {
            Icon(Icons.Filled.Refresh, null)
            Text("  Refresh")
        }
    }
}

// The viewer's source choices, each as wide as its words (six of them do not
// fit a phone side by side), the row scrolling sideways, the picked one in view
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChoiceRow(choices: List<Choice>, picked: String, modifier: Modifier = Modifier, pick: (String) -> Unit) {
    val scroll = rememberScrollState()
    LaunchedEffect(picked) { if (picked == choices.lastOrNull()?.value) scroll.scrollTo(scroll.maxValue) else scroll.scrollTo(0) }
    Row(modifier.horizontalScroll(scroll)) {
        SingleChoiceSegmentedButtonRow {
            choices.forEachIndexed { i, c ->
                SegmentedButton(selected = c.value == picked, onClick = { pick(c.value) },
                    shape = SegmentedButtonDefaults.itemShape(i, choices.size), icon = {}) {
                    Text(c.label, maxLines = 1, softWrap = false, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}
