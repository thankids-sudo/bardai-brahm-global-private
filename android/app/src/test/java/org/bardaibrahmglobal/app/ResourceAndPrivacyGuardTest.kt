package org.bardaibrahmglobal.app

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import kotlinx.coroutines.runBlocking
import org.bardaibrahmglobal.app.data.remote.BackendConfig
import org.bardaibrahmglobal.app.preview.PreviewChapterRepository
import org.bardaibrahmglobal.app.preview.PreviewEventRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * Guards: both languages are complete; the app asks for no permission beyond internet;
 * the backend must be https; preview screens present no invented records as live data.
 * Unit tests run with the module directory as the working directory.
 */
class ResourceAndPrivacyGuardTest {

    private fun strings(path: String): Map<String, String> {
        val file = File(path)
        assertTrue("Missing $path", file.exists())
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        return (0 until nodes.length).associate {
            val e = nodes.item(it) as Element
            e.getAttribute("name") to e.textContent
        }
    }

    private val english = strings("src/main/res/values/strings.xml")
    private val gujarati = strings("src/main/res/values-gu/strings.xml")

    @Test fun everyEnglishStringHasGujarati() {
        assertEquals(emptySet<String>(), english.keys - gujarati.keys)
    }

    @Test fun noOrphanGujaratiStrings() {
        assertEquals(emptySet<String>(), gujarati.keys - english.keys)
    }

    @Test fun noBlankTranslations() {
        val blank = (english + gujarati.mapKeys { "gu:" + it.key }).filterValues { it.isBlank() }.keys
        assertEquals(emptySet<String>(), blank)
    }

    @Test fun formatPlaceholdersMatch() {
        val placeholder = Regex("%\\d+\\$[sd]")
        english.forEach { (key, en) ->
            assertEquals(
                "Placeholder mismatch in $key",
                placeholder.findAll(en).map { it.value }.toSet(),
                placeholder.findAll(gujarati.getValue(key)).map { it.value }.toSet(),
            )
        }
    }

    @Test fun gujaratiFileIsActuallyGujarati() {
        // Catch copy-paste of English into values-gu: most entries must contain Gujarati script.
        val gujaratiBlock = Regex("[\\u0A80-\\u0AFF]")
        val share = gujarati.values.count { gujaratiBlock.containsMatchIn(it) }.toDouble() / gujarati.size
        assertTrue("Only ${(share * 100).toInt()}% of values-gu strings use Gujarati script", share > 0.9)
    }

    @Test fun internetIsTheOnlyPermission() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        val permissions = Regex("uses-permission[^>]*android:name=\"([^\"]+)\"").findAll(manifest).map { it.groupValues[1] }.toList()
        assertEquals(listOf("android.permission.INTERNET"), permissions)
    }

    @Test fun backendRequiresHttpsAndAKey() {
        assertFalse(BackendConfig("", "").isConfigured)
        assertFalse(BackendConfig("https://example.supabase.co", "").isConfigured)
        assertFalse(BackendConfig("http://example.supabase.co", "key").isConfigured)
        assertTrue(BackendConfig("https://example.supabase.co", "key").isConfigured)
        assertTrue(BackendConfig("http://127.0.0.1:54321", "key").isConfigured)
    }

    @Test fun backupsStayDisabled() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertTrue(manifest.contains("android:allowBackup=\"false\""))
    }

    @Test fun previewRepositoriesHoldNoInventedRecords() = runBlocking {
        assertTrue(PreviewChapterRepository().chapters().isEmpty())
        assertTrue(PreviewEventRepository().upcomingEvents().isEmpty())
    }
}
