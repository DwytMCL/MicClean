package com.dwight.micclean

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

/** Talks to the MicClean module through Magisk root. */
object Root {
    private const val CFG = "/data/adb/micclean/config"
    private const val TOOL = "/system/bin/micclean"

    data class Result(val ok: Boolean, val out: String)

    fun run(cmd: String): Result = try {
        val p = ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start()
        val out = p.inputStream.bufferedReader().readText()
        Result(p.waitFor() == 0, out.trim())
    } catch (e: Exception) {
        Result(false, e.message ?: "su failed")
    }

    /** null = no root; empty map = module missing */
    fun readConfig(): Map<String, Int>? {
        val r = run("[ -f $CFG ] && [ -d /data/adb/modules/micclean ] && [ ! -f /data/adb/modules/micclean/disable ] && cat $CFG || echo __MISSING__")
        if (!r.ok && r.out.isBlank()) return null
        if (r.out.contains("permission denied", true) || r.out.contains("not allowed", true)) return null
        if (r.out.contains("__MISSING__")) return emptyMap()
        return r.out.lines().mapNotNull { line ->
            val m = Regex("""^([A-Z_]+)=(-?\d+)""").find(line.trim()) ?: return@mapNotNull null
            m.groupValues[1] to m.groupValues[2].toInt()
        }.toMap()
    }

    fun set(key: String, value: Int) = run("$TOOL set $key $value")
    fun reset() = run("$TOOL reset")
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val ctx = LocalContext.current
            val scheme = if (isSystemInDarkTheme()) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
            MaterialTheme(colorScheme = scheme) { App() }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun App() {
    val scope = rememberCoroutineScope()
    val snack = remember { SnackbarHostState() }
    var cfg by remember { mutableStateOf<Map<String, Int>?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }

    fun reload() = scope.launch {
        busy = true
        cfg = withContext(Dispatchers.IO) { Root.readConfig() }
        loaded = true; busy = false
    }

    fun apply(key: String, value: Int, label: String) = scope.launch {
        if (cfg?.get(key) == value) return@launch
        busy = true
        cfg = cfg?.plus(key to value)
        val r = withContext(Dispatchers.IO) { Root.set(key, value) }
        cfg = withContext(Dispatchers.IO) { Root.readConfig() }
        busy = false
        snack.showSnackbar(if (r.ok) "$label applied" else "Failed: ${r.out.lines().lastOrNull() ?: ""}")
    }

    LaunchedEffect(Unit) { reload() }

    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("MicClean") },
                actions = { IconButton(onClick = { reload() }) { Icon(Icons.Filled.Refresh, "Reload") } },
                scrollBehavior = scroll
            )
        },
        snackbarHost = { SnackbarHost(snack) }
    ) { pad ->
        Column(
            Modifier.padding(pad).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth()) else Spacer(Modifier.height(4.dp))
            val c = cfg
            when {
                !loaded -> {}
                c == null -> Notice("Root access needed", "Allow MicClean in the Magisk prompt, then tap reload.")
                c.isEmpty() -> Notice("Module not active", "Install or enable the MicClean module in Magisk, then reboot.")
                else -> Controls(c, enabled = !busy, onSet = ::apply, onReset = {
                    scope.launch {
                        busy = true
                        val r = withContext(Dispatchers.IO) { Root.reset() }
                        cfg = withContext(Dispatchers.IO) { Root.readConfig() }
                        busy = false
                        snack.showSnackbar(if (r.ok) "Defaults restored" else "Reset failed")
                    }
                })
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
fun Notice(title: String, body: String) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Warning, null)
            Spacer(Modifier.width(12.dp))
            Column {
                Text(title, style = MaterialTheme.typography.titleMedium)
                Text(body, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
fun Controls(c: Map<String, Int>, enabled: Boolean, onSet: (String, Int, String) -> Unit, onReset: () -> Unit) {
    Text(
        "Changes apply right away and restart audio for a second, so avoid changing them during a call.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    Section("Phone calls", "SIM and VoLTE calls, processed by the MediaTek modem") {
        GainSlider("Mic level", c["CALL_MIC_OFFSET"] ?: 0, -15, 6, enabled) { onSet("CALL_MIC_OFFSET", it, "Call mic level") }
        GainSlider("Speakerphone extra", c["CALL_SPK_OFFSET"] ?: 0, -10, 6, enabled) { onSet("CALL_SPK_OFFSET", it, "Speakerphone level") }
        Toggle("Dual-mic noise reduction", "Experimental. Uses the second mic to cancel room noise.",
            c["CALL_DUALMIC"] == 1, enabled) { onSet("CALL_DUALMIC", if (it) 1 else 0, "Dual-mic") }
    }

    Section("Internet calls", "Discord, WhatsApp, Messenger, Telegram, Meet") {
        GainSlider("Mic level", c["VOIP_MIC_OFFSET"] ?: 0, -15, 6, enabled) { onSet("VOIP_MIC_OFFSET", it, "Internet call mic level") }
        Toggle("AI noise suppression", "RNNoise, removes fans, traffic and room noise",
            c["VOIP_RNNOISE"] == 1, enabled) { onSet("VOIP_RNNOISE", if (it) 1 else 0, "AI noise suppression") }
        if (c["VOIP_RNNOISE"] == 1) StrengthPicker(c["VOIP_RNNOISE_STRENGTH"] ?: 2, enabled) {
            onSet("VOIP_RNNOISE_STRENGTH", it, "Noise suppression strength")
        }
        Toggle("MediaTek noise suppression", "Stock filter, not needed with AI noise suppression on",
            c["VOIP_NS"] == 1, enabled) { onSet("VOIP_NS", if (it) 1 else 0, "MediaTek noise suppression") }
        Toggle("Echo cancellation", "Stops the other person hearing themselves",
            c["VOIP_AEC"] == 1, enabled) { onSet("VOIP_AEC", if (it) 1 else 0, "Echo cancellation") }
        Toggle("Limiter", "Keeps loud peaks from blasting",
            c["VOIP_LIMITER"] == 1, enabled) { onSet("VOIP_LIMITER", if (it) 1 else 0, "Limiter") }
        Toggle("Auto gain", "Boosts quiet speech, but also background noise",
            c["VOIP_AGC"] == 1, enabled) { onSet("VOIP_AGC", if (it) 1 else 0, "Auto gain") }
    }

    OutlinedButton(onClick = onReset, enabled = enabled, modifier = Modifier.fillMaxWidth()) { Text("Reset to defaults") }
}

@Composable
fun Section(title: String, subtitle: String, content: @Composable ColumnScope.() -> Unit) {
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            content()
        }
    }
}

@Composable
fun GainSlider(label: String, value: Int, min: Int, max: Int, enabled: Boolean, onDone: (Int) -> Unit) {
    var v by remember(value) { mutableFloatStateOf(value.toFloat()) }
    Column {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            val d = v.roundToInt()
            Text(if (d == 0) "Stock" else "${if (d > 0) "+" else ""}$d dB",
                style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        }
        Slider(
            value = v, onValueChange = { v = it }, enabled = enabled,
            valueRange = min.toFloat()..max.toFloat(), steps = max - min - 1,
            onValueChangeFinished = { onDone(v.roundToInt()) }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StrengthPicker(value: Int, enabled: Boolean, onPick: (Int) -> Unit) {
    val labels = listOf("AI only", "Gentle", "Normal", "Strong")
    Column(Modifier.padding(vertical = 4.dp)) {
        Text("Strength", style = MaterialTheme.typography.bodyLarge)
        Text("Higher levels also mute keys and taps between your words",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            labels.forEachIndexed { i, l ->
                SegmentedButton(
                    selected = value == i, enabled = enabled,
                    onClick = { onPick(i) },
                    shape = SegmentedButtonDefaults.itemShape(i, labels.size)
                ) { Text(l, maxLines = 1) }
            }
        }
    }
}

@Composable
fun Toggle(label: String, desc: String, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Text(desc, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}
