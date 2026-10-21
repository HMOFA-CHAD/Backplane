package dev.backplane.mobile

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

// Never queue a cached action. The shared envelope separately validates hub,
// owner, current conversation and allowed actions before doing anything.
private fun mailCurrent(m: AppModel, mail: MailroomModel): Boolean =
    MailroomAction.currentReady(m.contentReady, m.links.any { Pairing.key(it) == mail.hub }, mail, m.screen?.bot?.mailroom)

private fun mailAct(m: AppModel, mail: MailroomModel, action: String, value: String = "",
                    draft: String? = null, recipient: String? = null, quiet: Boolean = false): Boolean {
    val current = m.screen?.bot?.mailroom
    if (!MailroomAction.currentReady(m.contentReady, m.links.any { Pairing.key(it) == mail.hub }, mail, current) ||
        !MailroomAction.actionAllowed(current, action, value, recipient)) return false
    val request = MailroomAction.request(mail, action, value, draft, recipient)
    if (quiet) m.quiet("mailroom-action", request) else m.act("mailroom-action", request)
    return true
}

@Composable
fun MailroomScreen(m: AppModel, mail: MailroomModel) {
    val lang = LocalBackplaneLanguage.current
    val active = mailCurrent(m, mail)
    Column(Modifier.fillMaxSize()) {
        Text(mail.machine, Modifier.padding(horizontal = 16.dp, vertical = 6.dp), style = MaterialTheme.typography.labelMedium)
        if (!mail.online) Text(NativeMessages.native_mailroom_machine_offline(lang), Modifier.padding(horizontal = 16.dp))
        HorizontalDivider()
        // Keys prevent text or recipients crossing owner, hub incarnation or conversation.
        key(mail.hub, mail.origin, mail.owner, mail.body?.id ?: "") {
            if (mail.body == null) MailroomList(m, mail, active) else MailroomConversation(m, mail, mail.body, active)
        }
    }
}

@Composable
private fun ColumnScope.MailroomList(m: AppModel, mail: MailroomModel, active: Boolean) {
    val lang = LocalBackplaneLanguage.current
    var query by remember { mutableStateOf(mail.query) }
    LaunchedEffect(mail.query) { query = mail.query }
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(query, { query = it }, Modifier.weight(1f), singleLine = true, label = { Text(NativeMessages.common_search(lang)) })
        TextButton(onClick = { mailAct(m, mail, "mail-search", query) }, enabled = active) { Text(NativeMessages.common_search(lang)) }
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf("" to NativeMessages.viewer_layers_all(lang), "unread" to NativeMessages.native_plane_unread(lang),
            "act" to NativeMessages.native_mailroom_act(lang), "fyi" to NativeMessages.native_mailroom_fyi(lang)).forEach { (id, label) ->
            FilterChip(selected = mail.status == id, onClick = { mailAct(m, mail, "mail-filter", id) }, enabled = active, label = { Text(label) })
        }
    }
    if (mail.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
    LazyColumn(Modifier.weight(1f).fillMaxWidth()) {
        if (mail.rows.isEmpty()) item { Text(if (mail.loading) NativeMessages.viewer_loading(lang) else NativeMessages.native_bot_messages_empty(lang), Modifier.padding(16.dp)) }
        items(mail.rows, key = { it.id }) { row ->
            TextButton(onClick = { mailAct(m, mail, "mail-open", row.id) }, enabled = active, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.fillMaxWidth().padding(8.dp)) {
                    Text(row.subject, style = if (row.unread) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyLarge)
                    Text(row.who, style = MaterialTheme.typography.labelMedium)
                    Text(row.head, maxLines = 2, style = MaterialTheme.typography.bodyMedium)
                }
            }
            HorizontalDivider()
        }
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        TextButton(onClick = { mailAct(m, mail, "mail-window", (mail.first - 50).coerceAtLeast(0).toString()) }, enabled = active && !mail.loading && mail.first > 0) { Text(NativeMessages.common_earlier(lang)) }
        Text(NativeMessages.native_mailroom_page(lang, (if (mail.total == 0) 0 else mail.first + 1).toString(), (mail.first + mail.rows.size).toString(), mail.total.toString()))
        TextButton(onClick = { mailAct(m, mail, "mail-window", (mail.first + 50).toString()) }, enabled = active && !mail.loading && mail.first + mail.rows.size < mail.total) { Text(NativeMessages.native_mailroom_later(lang)) }
    }
}

@Composable
private fun ColumnScope.MailroomConversation(m: AppModel, mail: MailroomModel, body: MailroomBody, active: Boolean) {
    val lang = LocalBackplaneLanguage.current
    var draft by remember { mutableStateOf(body.draft) }
    var recipient by remember { mutableStateOf(body.to) }
    var submitted by remember { mutableStateOf(false) }
    var picker by remember { mutableStateOf(false) }
    var previousDraft by remember { mutableStateOf(body.draft) }
    // Preserve edits until the correlated shared model commits or returns error.
    LaunchedEffect(body.draft, body.sendState) {
        if (draft == previousDraft) draft = body.draft
        previousDraft = body.draft
        if (body.sendState == "filed" || body.sendState == "error" || body.sendState == "failed") submitted = false
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        TextButton(onClick = { mailAct(m, mail, "mail-close") }, enabled = active) { Text(NativeMessages.tour_back(lang)) }
        Text(body.subject, Modifier.weight(1f).padding(12.dp), style = MaterialTheme.typography.titleMedium)
    }
    if (body.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
    LazyColumn(Modifier.weight(1f).fillMaxWidth()) {
        if (body.previousAnchor.isNotEmpty() || body.remoteEarlier) item {
            TextButton(onClick = {
                if (body.previousAnchor.isNotEmpty()) mailAct(m, mail, "mail-body-window", body.previousAnchor)
                else mailAct(m, mail, "mail-more")
            }, enabled = active && !body.loading) { Text(NativeMessages.common_earlier(lang)) }
        }
        items(body.messages, key = { it.id }) { message ->
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                Text(message.who, style = MaterialTheme.typography.labelMedium)
                // The projection includes full text, not a row preview.
                Text(message.text, style = MaterialTheme.typography.bodyMedium)
                if (message.sourceURI.isNotEmpty()) TextButton(onClick = { if (mailCurrent(m, mail)) m.act("ref-open", MailroomAction.sourceRequest(mail, message.sourceURI)) }, enabled = active) { Text(NativeMessages.native_mailroom_open_source(lang)) }
            }
            HorizontalDivider()
        }
        if (body.nextAnchor.isNotEmpty()) item {
            TextButton(onClick = { mailAct(m, mail, "mail-body-window", body.nextAnchor) }, enabled = active && !body.loading) { Text(NativeMessages.native_mailroom_later(lang)) }
        }
    }
    Box {
        TextButton(onClick = { picker = true }, enabled = active) { Text(body.targets.firstOrNull { it.address == recipient }?.label ?: NativeMessages.native_mailroom_recipient(lang)) }
        DropdownMenu(expanded = picker, onDismissRequest = { picker = false }) {
            body.targets.forEach { target -> DropdownMenuItem(text = { Text(target.label) }, onClick = {
                if (mailAct(m, mail, "mail-to", target.address)) recipient = target.address
                picker = false
            }) }
        }
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(draft, { draft = it; mailAct(m, mail, "bfield", "mrreply\u001f" + it, quiet = true) }, Modifier.weight(1f), enabled = active,
            label = { Text(NativeMessages.review_reply(lang)) }, maxLines = 6)
        TextButton(onClick = { if (mailAct(m, mail, "mail-send", draft = draft, recipient = recipient)) submitted = true },
            enabled = active && !submitted && !MailroomAction.busy(body.sendState) && recipient.isNotEmpty() && draft.isNotBlank()) { Text(NativeMessages.composer_send(lang)) }
    }
    val status = when (body.sendState) {
        "sending", "pending" -> NativeMessages.native_thread_sending(lang)
        "ack", "accepted" -> NativeMessages.native_mailroom_accepted_unconfirmed(lang)
        "unknown" -> NativeMessages.native_mailroom_outcome_unknown(lang)
        "error", "failed" -> NativeMessages.native_thread_send_failed(lang)
        else -> ""
    }
    if (status.isNotEmpty()) Text(status, Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.labelSmall)
}
