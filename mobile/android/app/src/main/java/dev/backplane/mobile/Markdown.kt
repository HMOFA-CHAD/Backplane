package dev.backplane.mobile

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp

// Draws the markdown blocks Md.render made (p, h3-h5, ul/li, pre, code,
// strong, a) with native text styles. A web link opens in the browser; a
// tap on a file's link asks for its menu ("file-menu" with the path).

fun plain(bs: List<Block>): String = buildString {
    for (b in bs) when (b) {
        is Block.Txt -> append(b.text)
        is Block.El -> append(plain(b.kids))
    }
}

// what a tapped file link does (the thread's model, where there is one)
val LocalFileTap = staticCompositionLocalOf<((String) -> Unit)?> { null }

@Composable
private fun inline(bs: List<Block>): AnnotatedString {
    val code = MaterialTheme.colorScheme.surfaceVariant
    val accent = MaterialTheme.colorScheme.primary
    val tap = LocalFileTap.current
    val style = TextLinkStyles(SpanStyle(color = accent, textDecoration = TextDecoration.Underline))
    fun AnnotatedString.Builder.go(xs: List<Block>) {
        for (b in xs) when (b) {
            is Block.Txt -> append(b.text)
            is Block.El -> when {
                b.tag == "code" -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = code)) { go(b.kids) }
                b.tag == "strong" -> withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { go(b.kids) }
                b.tag == "a" && b.href != null && b.file && tap != null ->
                    withLink(LinkAnnotation.Clickable(b.href, style) { tap(b.href) }) { go(b.kids) }
                b.tag == "a" && b.href != null && !b.file -> withLink(LinkAnnotation.Url(b.href, style)) { go(b.kids) }
                else -> go(b.kids)
            }
        }
    }
    return buildAnnotatedString { go(bs) }
}

@Composable
fun Markdown(blocks: List<Block>, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (b in blocks) MdBlock(b)
    }
}

@Composable
private fun MdBlock(b: Block) {
    val t = MaterialTheme.typography
    when (b) {
        is Block.Txt -> Text(b.text, style = t.bodyLarge)
        is Block.El -> when (b.tag) {
            "p" -> Text(inline(b.kids), style = t.bodyLarge)
            "h3" -> Text(inline(b.kids), style = t.titleLarge)
            "h4" -> Text(inline(b.kids), style = t.titleMedium)
            "h5" -> Text(inline(b.kids), style = t.titleSmall)
            "ul" -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                for (li in b.kids) if (li is Block.El) Row {
                    Text("•  ", style = t.bodyLarge)
                    Text(inline(li.kids), style = t.bodyLarge)
                }
            }
            "pre" -> Surface(color = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
                Text(plain(b.kids), style = t.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    softWrap = false,
                    modifier = Modifier.horizontalScroll(rememberScrollState()).padding(12.dp))
            }
            // the web page's copy button: long-press the message instead
            "button" -> Unit
            else -> for (k in b.kids) MdBlock(k)
        }
    }
}
