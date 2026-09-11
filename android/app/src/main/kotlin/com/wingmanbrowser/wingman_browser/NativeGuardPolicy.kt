package com.wingmanbrowser.wingman_browser

import android.icu.text.IDNA
import java.util.Locale
import java.net.InetAddress

/** IDNA utility only. Native live-content policy and its legacy overrides are removed. */
class NativeGuardPolicy private constructor() {
    companion object {
        private val idna = IDNA.getUTS46Instance(IDNA.NONTRANSITIONAL_TO_ASCII or IDNA.USE_STD3_RULES or IDNA.CHECK_BIDI or IDNA.CHECK_CONTEXTJ)
        fun normalizeHost(input: String): String? {
            if (input.isEmpty() || input.length > 1024 || input.any { it.isWhitespace() || it.code < 33 || it.code == 127 || it in "/\\@?#%" }) return null
            var raw = input.lowercase(Locale.ROOT)
            if (raw.startsWith('[') && raw.endsWith(']')) raw = raw.substring(1, raw.length - 1)
            if (raw.contains(':')) {
                if (!raw.matches(Regex("^[0-9a-f:.]+$"))) return null
                val bytes = try { InetAddress.getByName(raw).address } catch (_: Exception) { return null }
                val ipv6 = if (bytes.size == 4) ByteArray(16).also { it[10] = -1; it[11] = -1; bytes.copyInto(it, 12) } else bytes
                if (ipv6.size != 16) return null
                val words = (0..7).map { ((ipv6[it * 2].toInt() and 255) shl 8) or (ipv6[it * 2 + 1].toInt() and 255) }
                var best = -1; var length = 1; var i = 0
                while (i < 8) { if (words[i] != 0) { i++; continue }; val start = i; while (i < 8 && words[i] == 0) i++; if (i - start > length) { best = start; length = i - start } }
                if (best < 0) return words.joinToString(":") { it.toString(16) }
                return words.take(best).joinToString(":") { it.toString(16) } + "::" + words.drop(best + length).joinToString(":") { it.toString(16) }
            }
            val info = IDNA.Info()
            val output = StringBuilder()
            raw = raw.replace('\u3002', '.').replace('\uff0e', '.').replace('\uff61', '.').removeSuffix(".")
            idna.nameToASCII(raw, output, info)
            val host = output.toString().lowercase(Locale.ROOT)
            val labels = host.split('.')
            if (info.hasErrors() || host.isEmpty() || host.length > 253 || labels.any { it.isEmpty() || it.length > 63 || it.startsWith('-') || it.endsWith('-') }) return null
            if (labels.all { it.matches(Regex("^([0-9]+|0x[0-9a-f]+)$")) } && (labels.size != 4 || labels.any { !it.matches(Regex("^(0|[1-9][0-9]{0,2})$")) || (it.toIntOrNull() ?: 256) > 255 })) return null
            return host
        }
    }
}
