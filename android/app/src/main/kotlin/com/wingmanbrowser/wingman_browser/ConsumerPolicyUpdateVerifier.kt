package com.wingmanbrowser.wingman_browser

import org.json.JSONObject
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.Instant
import java.util.Base64
import java.util.Locale

/** Authenticated immutable candidate; caller still must prepare/activate native rules. */
internal class VerifiedConsumerCandidate(
    val sequence: Long, val version: String, val generatedAt: String, val sha256: String,
    envelope: ByteArray, data: ByteArray
) {
    private val signedEnvelope = envelope.copyOf()
    private val content = data.copyOf()
    val envelope: ByteArray get() = signedEnvelope.copyOf()
    val data: ByteArray get() = content.copyOf()
}

/** No endpoint, browsing URL, preference key or caller checksum supplies trust. */
internal class ConsumerPolicyUpdateVerifier(
    trustedKeys: Map<String, ByteArray>,
    private val appVersion: String = "0.10.0",
    private val nowMillis: () -> Long = System::currentTimeMillis
) {
    private val keys = trustedKeys.mapValues { it.value.copyOf() }
    companion object {
        const val PURPOSE = "wingman-consumer-protection-v1"
        const val MAX_BYTES = 16 * 1024 * 1024
        private val required = setOf("sexual-explicit", "gambling", "alcohol-promotion", "recreational-drug-promotion", "tobacco-nicotine", "security-threat")
        private val label = Regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
        private fun decode(bytes: ByteArray) = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        private fun domain(value: String) = value.length <= 253 && value.contains('.') && value.split('.').all { label.matches(it) }
        fun supported(): Boolean = try { Signature.getInstance("Ed25519"); KeyFactory.getInstance("Ed25519"); true } catch (_: Exception) { false }
        private fun integer(json: JSONObject, name: String): Long {
            val number = json.get(name)
            require(number is Int || number is Long) { "integer-$name" }
            return (number as Number).toLong()
        }
        private fun version(value: String): List<Long> {
            require(Regex("^(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})$").matches(value)) { "app-version" }
            return value.split('.').map(String::toLong)
        }
    }

    fun verify(envelopeInput: ByteArray, dataInput: ByteArray): VerifiedConsumerCandidate {
        val envelope = envelopeInput.copyOf()
        val data = dataInput.copyOf()
        require(envelope.size in 1..65536 && data.size in 1..MAX_BYTES) { "release-size" }
        check(supported()) { "signature-unavailable" }
        val outer = JSONObject(decode(envelope))
        require(outer.length() == 3) { "envelope-schema" }
        val rawKey = keys[outer.getString("keyId")] ?: error("unknown-key")
        require(rawKey.size == 32) { "key-format" }
        val payload = Base64.getDecoder().decode(outer.getString("payload"))
        val signature = Base64.getDecoder().decode(outer.getString("signature"))
        require(payload.size in 1..65536 && signature.size == 64) { "signature-format" }
        val prefix = byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00)
        val publicKey = KeyFactory.getInstance("Ed25519").generatePublic(X509EncodedKeySpec(prefix + rawKey))
        require(Signature.getInstance("Ed25519").run { initVerify(publicKey); update(payload); verify(signature) }) { "signature" }
        val manifest = JSONObject(decode(payload))
        require(manifest.getString("purpose") == PURPOSE && integer(manifest, "schemaVersion") == 1L) { "purpose" }
        val sequence = integer(manifest, "sequence")
        val releaseVersion = manifest.getString("version")
        val generatedAt = manifest.getString("generatedAt")
        val generated = Instant.parse(generatedAt)
        val digest = manifest.getString("sha256")
        require(sequence in 2..2147483647L && Regex("^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,79}$").matches(releaseVersion)) { "release-version" }
        require(generatedAt.endsWith("Z") && generated.toEpochMilli() <= nowMillis() + 86400000L) { "release-time" }
        val running = version(appVersion); val minimum = version(manifest.getString("minimumAppVersion"))
        val firstDifference = running.indices.firstOrNull { running[it] != minimum[it] }
        require(firstDifference == null || running[firstDifference] > minimum[firstDifference]) { "minimum-app-version" }
        require(manifest.getString("filename") == "consumer-$sequence.json" && integer(manifest, "bytes") == data.size.toLong() && Regex("^[a-f0-9]{64}$").matches(digest)) { "data-metadata" }
        require(manifest.getString("license").length in 1..4096) { "license-metadata" }
        require(MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) } == digest) { "data-integrity" }
        val json = JSONObject(decode(data))
        require(integer(json, "schemaVersion") == 1L && integer(json, "sequence") == sequence && json.getString("version") == releaseVersion && Instant.parse(json.getString("generatedAt")) == generated) { "content-metadata" }
        val categories = json.getJSONObject("categories")
        require(categories.length() == required.size) { "categories" }
        required.forEach { category ->
            val entries = categories.getJSONArray(category)
            require(entries.length() in 1..500000) { "category-size" }
            for (i in 0 until entries.length()) require(domain(entries.getString(i))) { "category-domain" }
        }
        val paths = json.getJSONArray("pathRules")
        for (i in 0 until paths.length()) {
            val row = paths.getJSONObject(i); val path = row.getString("pathPrefix")
            require(domain(row.getString("host")) && row.getString("category") in required && path.startsWith('/') && !path.contains('%') && !path.contains('?') && path == path.lowercase(Locale.ROOT)) { "path-rule" }
        }
        val trackers = json.getJSONArray("trackers")
        for (i in 0 until trackers.length()) require(domain(trackers.getString(i))) { "tracker-domain" }
        return VerifiedConsumerCandidate(sequence, releaseVersion, generatedAt, digest, envelope, data)
    }
}
