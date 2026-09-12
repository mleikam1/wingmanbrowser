package com.wingmanbrowser.wingman_browser

import org.junit.Assert.*
import org.junit.Test

class StrictSearchPolicyTest {
    @Test fun ordinaryPunctuationAndUnicodeRemainQueries() {
        for (query in listOf("Hello!", "C++!", "math !", "Chicago weather", "café science", "日本語")) {
            val url = strictSearchURL(query)
            assertNotNull(query, url)
            assertTrue(url!!.startsWith("https://safe.duckduckgo.com/?q="))
            assertTrue(url.endsWith("&kp=1&kac=-1"))
        }
    }
    @Test fun shortcutsAndControlsCannotEscapeStrictProvider() {
        for (query in listOf("!g cats", "cats !safeoff", "\\cats", "%21g cats", "%2521g cats", "！g cats", "cats \n dogs", "\uD800")) {
            assertNull(query, strictSearchURL(query))
        }
    }
    @Test fun limitsAreMeasuredBeforeEscaping() {
        assertNull(strictSearchURL(""))
        assertNotNull(strictSearchURL("a".repeat(512)))
        assertNull(strictSearchURL("a".repeat(513)))
        assertNull(strictSearchURL("界".repeat(400)))
    }
}
