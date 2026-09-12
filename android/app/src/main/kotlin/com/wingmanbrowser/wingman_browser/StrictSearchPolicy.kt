package com.wingmanbrowser.wingman_browser

import java.net.URLEncoder
import java.text.Normalizer
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** Independent serialization. Provider SafeSearch is separate from category filtering. */
internal fun strictSearchURL(input: String): String? {
    val value = input.trim()
    if (value.isEmpty() || value.codePointCount(0, value.length) > 512 || value.toByteArray(Charsets.UTF_8).size > 1024) return null
    if (value.any { it.code < 32 || it.code in 127..159 || it.code in 0x2028..0x202e || it.code in 0x2066..0x2069 }) return null
    var i = 0
    while (i < value.length) {
        if (Character.isHighSurrogate(value[i])) { if (++i >= value.length || !Character.isLowSurrogate(value[i])) return null }
        else if (Character.isLowSurrogate(value[i])) return null
        i++
    }
    var probe = value
    val encodedRun = Regex("(?:%[0-9a-fA-F]{2})+")
    try {
        for (round in 0..8) {
            probe = Normalizer.normalize(probe, Normalizer.Form.NFKC)
            if (probe.trimStart().startsWith('\\') || Regex("(^|[^a-zA-Z0-9_])![a-zA-Z0-9_]").containsMatchIn(probe) || probe.any { it.code < 32 || it.code in 127..159 }) return null
            if (!encodedRun.containsMatchIn(probe)) break
            if (round == 8) return null
            probe = encodedRun.replace(probe) { match ->
                val bytes = ByteArray(match.value.length / 3) { n -> match.value.substring(n * 3 + 1, n * 3 + 3).toInt(16).toByte() }
                Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
            }
        }
    } catch (_: Exception) { return null }
    val encoded = URLEncoder.encode(value, "UTF-8").replace("+", "%20").replace("%7E", "~")
    return "https://safe.duckduckgo.com/?q=$encoded&kp=1&kac=-1"
}
