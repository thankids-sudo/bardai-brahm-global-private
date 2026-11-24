package org.bardaibrahmglobal.app

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import java.util.Locale
import org.bardaibrahmglobal.app.i18n.AppLanguage
import org.bardaibrahmglobal.app.i18n.LanguageController
import org.bardaibrahmglobal.app.preview.PreviewChapterRepository
import org.bardaibrahmglobal.app.preview.PreviewEventRepository
import org.bardaibrahmglobal.app.ui.BardaiApp
import org.bardaibrahmglobal.app.ui.theme.BardaiTheme

/**
 * AppCompatActivity (not plain ComponentActivity) so per-app language changes apply
 * immediately and persist across restarts on all supported Android versions.
 */
class MainActivity : AppCompatActivity() {

    // M1 binds preview repositories only. Real implementations arrive with M2.
    private val chapterRepository = PreviewChapterRepository()
    private val eventRepository = PreviewEventRepository()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val language = LanguageController.current(Locale.getDefault().toLanguageTag())
        val versionName = packageManager.getPackageInfo(packageName, 0).versionName ?: ""

        setContent {
            BardaiTheme {
                BardaiApp(
                    language = language,
                    onLanguageSelected = { selected: AppLanguage ->
                        if (selected != language) LanguageController.apply(selected)
                    },
                    chapterRepository = chapterRepository,
                    eventRepository = eventRepository,
                    versionName = versionName,
                )
            }
        }
    }
}
