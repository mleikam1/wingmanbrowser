package com.wingmanbrowser.wingman_browser

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** Independent native serialization. This grants only the separate search surface. */
internal fun strictSearchURL(input: String): String? {
    if (input.length > 8192) return null
    var offset = 0
    while (offset < input.length) {
        val unit = input[offset]
        if (Character.isHighSurrogate(unit)) {
            if (offset + 1 >= input.length || !Character.isLowSurrogate(input[offset + 1])) return null
            offset += 2
        } else {
            if (Character.isLowSurrogate(unit)) return null
            offset++
        }
    }
    val scalars = input.codePoints().toArray()
    if (scalars.any(::searchControl)) return null
    var start = 0
    var end = scalars.size
    while (start < end && searchTrimSpace(scalars[start])) start++
    while (end > start && searchTrimSpace(scalars[end - 1])) end--
    if (end - start !in 1..512) return null
    val value = String(scalars, start, end - start)
    val bytes = value.toByteArray(Charsets.UTF_8)
    if (bytes.size > 1024) return null
    val encodedRun = Regex("(?:%[0-9a-fA-F]{2})+")
    var probe = value
    try {
        for (round in 0..8) {
            probe = buildString {
                probe.codePoints().forEach { scalar ->
                    appendCodePoint(when (scalar) { in 0xff01..0xff5e -> scalar - 0xfee0; 0xfe57 -> 0x21; 0xfe68 -> 0x5c; else -> scalar })
                }
            }
            if (probe.codePoints().anyMatch { searchControl(it) || it == 0x21 || it == 0x5c }) return null
            if (!encodedRun.containsMatchIn(probe)) {
                val encoded = buildString {
                    bytes.forEach { signed ->
                        val byte = signed.toInt() and 0xff
                        if (byte in 0x41..0x5a || byte in 0x61..0x7a || byte in 0x30..0x39 || byte in intArrayOf(0x2d, 0x2e, 0x5f, 0x7e)) append(byte.toChar())
                        else { append('%'); append("0123456789ABCDEF"[byte shr 4]); append("0123456789ABCDEF"[byte and 15]) }
                    }
                }
                return "https://safe.duckduckgo.com/lite/?q=$encoded&kp=1"
            }
            if (round == 8) return null
            probe = encodedRun.replace(probe) { match ->
                val data = ByteArray(match.value.length / 3) { index -> match.value.substring(index * 3 + 1, index * 3 + 3).toInt(16).toByte() }
                Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(data)).toString()
            }
        }
    } catch (_: Exception) { return null }
    return null
}

private fun searchControl(value: Int) = value <= 0x1f || value in 0x7f..0x9f || value == 0x061c || value == 0x200e || value == 0x200f || value in 0x2028..0x202e || value in 0x2066..0x2069
private fun searchTrimSpace(value: Int) = value == 0x20 || value == 0xa0 || value == 0x1680 || value in 0x2000..0x200a || value == 0x202f || value == 0x205f || value == 0x3000 || value == 0xfeff
