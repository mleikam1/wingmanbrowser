package com.wingmanbrowser.wingman_browser

import android.content.Context
import android.os.Build
import io.flutter.FlutterInjector
import org.json.JSONObject
import java.util.UUID

/** Native verification and two-phase activation. Preferences contain receipts, never signing trust. */
internal class ConsumerPolicyUpdates(
    private val context: Context,
    private val policy: ConsumerProtectionPolicy,
    private val quiesce: (() -> Unit) -> Unit,
) {
    private data class Receipt(val sequence: Long, val sha256: String)
    private data class Prepared(
        val candidate: ConsumerProtectionPolicy.Snapshot,
        val prior: ConsumerProtectionPolicy.Snapshot,
        val priorReceipt: Receipt,
        val priorPrevious: Receipt,
        var activated: Boolean = false,
    )
    private val preferences = context.getSharedPreferences("consumer_policy_receipts", Context.MODE_PRIVATE)
    private val tokens = mutableMapOf<String, Prepared>()
    private val keys: Map<String, ByteArray> by lazy {
        try {
            val path = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/policy/consumer_update_keys.json")
            val json = JSONObject(context.assets.open(path).bufferedReader().use { it.readText() })
            check(json.getInt("schemaVersion") == 1)
            val values = json.getJSONObject("keys")
            values.keys().asSequence().associateWith { name ->
                android.util.Base64.decode(values.getString(name), android.util.Base64.NO_WRAP).also { check(it.size == 32) }
            }
        } catch (_: Exception) { emptyMap() }
    }
    private fun validateReceipts() {
        if (preferences.all.isEmpty()) return
        val required = setOf("current_sequence", "current_sha256", "previous_sequence", "previous_sha256", "highest")
        check(preferences.all.keys.containsAll(required))
        val current = receipt("current"); val previous = receipt("previous"); val highest = preferences.getLong("highest", 0)
        val hash = Regex("^[a-f0-9]{64}$")
        check(current.sequence in 1..2147483647L && previous.sequence in 1..2147483647L && highest in maxOf(current.sequence, previous.sequence)..2147483647L)
        check(hash.matches(current.sha256) && hash.matches(previous.sha256))
    }
    fun generationReady(): Boolean = try {
        val snapshot = policy.currentSnapshot()
        if (preferences.all.isEmpty()) snapshot.sequence == 1L && snapshot.sha256 == ConsumerProtectionPolicy.SHA256
        else {
            validateReceipts()
            val current = receipt("current")
            snapshot.sequence == current.sequence && snapshot.sha256 == current.sha256
        }
    } catch (_: Exception) { false }
    fun supported() = Build.VERSION.SDK_INT >= 33 && ConsumerPolicyUpdateVerifier.supported()
    private fun receipt(prefix: String) = Receipt(preferences.getLong("${prefix}_sequence", 1), preferences.getString("${prefix}_sha256", ConsumerProtectionPolicy.SHA256)!!)
    private fun persist(current: Receipt, previous: Receipt, highest: Long): Boolean = preferences.edit()
        .putLong("current_sequence", current.sequence).putString("current_sha256", current.sha256)
        .putLong("previous_sequence", previous.sequence).putString("previous_sha256", previous.sha256)
        .putLong("highest", highest).commit()

    fun prepare(envelope: ByteArray, data: ByteArray, restore: Boolean): Map<String, Any> {
        check(supported() && policy.valid())
        validateReceipts()
        val candidate = ConsumerPolicyUpdateVerifier(keys, BuildConfig.VERSION_NAME).verify(envelope, data)
        val incoming = Receipt(candidate.sequence, candidate.sha256)
        val highest = preferences.getLong("highest", 1)
        val current = receipt("current"); val previous = receipt("previous")
        check(candidate.sequence > highest || (restore && (incoming == current || incoming == previous)))
        val parsed = policy.parseSnapshot(candidate.data, candidate.sha256)
        check(parsed.sequence == candidate.sequence)
        // Bounded preparation: a new attempt discards an uncommitted token, never the active snapshot.
        tokens.clear()
        val token = UUID.randomUUID().toString()
        tokens[token] = Prepared(parsed, policy.currentSnapshot(), current, previous)
        return mapOf("ready" to true, "token" to token, "sequence" to parsed.sequence, "sha256" to parsed.sha256)
    }
    fun activate(token: String): Map<String, Any> {
        val prepared = checkNotNull(tokens[token])
        if (!prepared.activated) {
            quiesce {
                val incoming = Receipt(prepared.candidate.sequence, prepared.candidate.sha256)
                val previous = if (incoming == prepared.priorReceipt) prepared.priorPrevious else prepared.priorReceipt
                check(persist(incoming, previous, maxOf(preferences.getLong("highest", 1), incoming.sequence)))
                policy.activate(prepared.candidate)
                prepared.activated = true
            }
        }
        return mapOf("activated" to true, "sequence" to prepared.candidate.sequence, "sha256" to prepared.candidate.sha256)
    }
    fun discard(token: String) { tokens.remove(token) }
    fun revert(token: String): Map<String, Any> {
        val prepared = checkNotNull(tokens[token])
        if (prepared.activated) {
            quiesce {
                check(persist(prepared.priorReceipt, prepared.priorPrevious, preferences.getLong("highest", 1)))
                policy.activate(prepared.prior)
                prepared.activated = false
            }
        }
        tokens.remove(token)
        return mapOf("reverted" to true)
    }
}
