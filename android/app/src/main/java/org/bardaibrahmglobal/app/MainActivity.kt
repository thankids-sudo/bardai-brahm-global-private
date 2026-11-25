package org.bardaibrahmglobal.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import java.util.Locale
import org.bardaibrahmglobal.app.data.auth.AuthRepository
import org.bardaibrahmglobal.app.data.auth.KeystoreRefreshTokenStore
import org.bardaibrahmglobal.app.data.membership.MembershipRepository
import org.bardaibrahmglobal.app.data.remote.BackendConfig
import org.bardaibrahmglobal.app.data.remote.SupabaseHttp
import org.bardaibrahmglobal.app.i18n.AppLanguage
import org.bardaibrahmglobal.app.i18n.LanguageController
import org.bardaibrahmglobal.app.preview.PreviewChapterRepository
import org.bardaibrahmglobal.app.preview.PreviewEventRepository
import org.bardaibrahmglobal.app.ui.BardaiApp
import org.bardaibrahmglobal.app.ui.account.AccountSection
import org.bardaibrahmglobal.app.ui.account.AccountViewModel
import org.bardaibrahmglobal.app.ui.account.asActions
import org.bardaibrahmglobal.app.ui.theme.BardaiTheme

/**
 * AppCompatActivity (not plain ComponentActivity) so per-app language changes apply
 * immediately and persist across restarts on all supported Android versions.
 */
class MainActivity : AppCompatActivity() {

    // Chapters and events tabs remain previews until their screens are connected.
    private val chapterRepository = PreviewChapterRepository()
    private val eventRepository = PreviewEventRepository()
    private val backend = BackendConfig.fromBuild()

    private val accountViewModel: AccountViewModel by viewModels {
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                val auth = AuthRepository(SupabaseHttp(backend), KeystoreRefreshTokenStore(applicationContext))
                return AccountViewModel(backend.isConfigured, auth, MembershipRepository(auth)) as T
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val language = LanguageController.current(Locale.getDefault().toLanguageTag())
        val versionName = packageManager.getPackageInfo(packageName, 0).versionName ?: ""
        if (savedInstanceState == null) handleAuthCallback(intent)

        setContent {
            BardaiTheme {
                val accountState by accountViewModel.state.collectAsStateWithLifecycle()
                BardaiApp(
                    language = language,
                    onLanguageSelected = { selected: AppLanguage ->
                        if (selected != language) LanguageController.apply(selected)
                    },
                    chapterRepository = chapterRepository,
                    eventRepository = eventRepository,
                    versionName = versionName,
                    backendConnected = backend.isConfigured,
                    account = { AccountSection(accountState, accountViewModel.asActions()) },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthCallback(intent)
    }

    private fun handleAuthCallback(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme == "org.bardaibrahmglobal.app" && data.host == "auth-callback") {
            accountViewModel.handleAuthCallback(data.encodedFragment)
        }
    }
}
