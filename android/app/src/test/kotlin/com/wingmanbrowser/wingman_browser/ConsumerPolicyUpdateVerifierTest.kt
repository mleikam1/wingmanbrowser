package com.wingmanbrowser.wingman_browser

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.time.Instant
import java.util.Base64

class ConsumerPolicyUpdateVerifierTest {
    private val pair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
    private val publicKey = pair.public.encoded.takeLast(32).toByteArray()
    private val time = "2026-09-11T12:00:00.000Z"
    private val verifier = ConsumerPolicyUpdateVerifier(mapOf("fixture-only" to publicKey), nowMillis = { Instant.parse(time).toEpochMilli() })
    private val categories = listOf("sexual-explicit", "gambling", "alcohol-promotion", "recreational-drug-promotion", "tobacco-nicotine", "security-threat")
    private fun release(changeManifest: (JSONObject) -> Unit = {}, changeData: (JSONObject) -> Unit = {}): Pair<ByteArray, ByteArray> {
        val content = JSONObject().put("schemaVersion", 1).put("sequence", 2).put("version", "fixture-2").put("generatedAt", time)
            .put("categories", JSONObject().also { json -> categories.forEach { json.put(it, JSONArray(listOf("$it.fixture.test"))) } })
            .put("pathRules", JSONArray().put(JSONObject().put("host", "mixed.fixture.test").put("pathPrefix", "/promotion").put("category", "gambling")))
            .put("trackers", JSONArray(listOf("tracker.fixture.test")))
        changeData(content)
        val data = content.toString().toByteArray()
        val hash = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
        val metadata = JSONObject().put("purpose", ConsumerPolicyUpdateVerifier.PURPOSE).put("schemaVersion", 1).put("sequence", 2)
            .put("version", "fixture-2").put("generatedAt", time).put("minimumAppVersion", "0.10.0")
            .put("filename", "consumer-2.json").put("sha256", hash).put("bytes", data.size).put("license", "Synthetic test only")
        changeManifest(metadata)
        val payload = metadata.toString().toByteArray()
        val signature = Signature.getInstance("Ed25519").run { initSign(pair.private); update(payload); sign() }
        return JSONObject().put("keyId", "fixture-only").put("payload", Base64.getEncoder().encodeToString(payload))
            .put("signature", Base64.getEncoder().encodeToString(signature)).toString().toByteArray() to data
    }

    @Test fun verifiesSignedSyntheticReleaseAndReturnsCopies() {
        val (envelope, data) = release()
        val candidate = verifier.verify(envelope, data)
        assertEquals(2L, candidate.sequence)
        assertEquals("fixture-2", candidate.version)
        val copy = candidate.data; copy[0] = 0
        assertArrayEquals(data, candidate.data)
    }
    @Test fun unknownKeyAndChangedSignatureAreRejected() {
        val (envelope, data) = release()
        assertThrows(Exception::class.java) { ConsumerPolicyUpdateVerifier(emptyMap()).verify(envelope, data) }
        val changed = JSONObject(String(envelope)).put("signature", Base64.getEncoder().encodeToString(ByteArray(64))).toString().toByteArray()
        assertThrows(Exception::class.java) { verifier.verify(changed, data) }
    }
    @Test fun changedOrTruncatedBytesAreRejected() {
        val (envelope, data) = release()
        val changed = data.copyOf(); changed[0] = 0
        assertThrows(Exception::class.java) { verifier.verify(envelope, changed) }
        assertThrows(Exception::class.java) { verifier.verify(envelope, data.copyOf(data.size - 1)) }
    }
    @Test fun signedMetadataCannotChangePurposeOrEscapeDirectory() {
        for ((key, value) in listOf("purpose" to "guard-v1", "filename" to "../consumer-2.json", "minimumAppVersion" to "99.0.0", "generatedAt" to "2099-01-01T00:00:00Z")) {
            val (envelope, data) = release(changeManifest = { it.put(key, value) })
            assertThrows(key, Exception::class.java) { verifier.verify(envelope, data) }
        }
    }
    @Test fun signedContentMustMatchManifestAndRetainEveryCategory() {
        for (change in listOf<(JSONObject) -> Unit>(
            { it.put("sequence", 3) }, { it.put("version", "other") },
            { it.getJSONObject("categories").remove("gambling"); Unit },
            { it.getJSONObject("categories").put("gambling", JSONArray()); Unit },
            { it.getJSONArray("pathRules").getJSONObject(0).put("category", "unknown"); Unit },
            { it.put("trackers", JSONArray(listOf("bad domain"))) }
        )) {
            val (envelope, data) = release(changeData = change)
            assertThrows(Exception::class.java) { verifier.verify(envelope, data) }
        }
    }
}
