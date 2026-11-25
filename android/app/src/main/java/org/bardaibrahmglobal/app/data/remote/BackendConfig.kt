package org.bardaibrahmglobal.app.data.remote

import org.bardaibrahmglobal.app.BuildConfig

/**
 * Where the backend lives. Values come from the build (CI secrets), never from source code.
 * Plain http is accepted only for a backend on this machine (local tests); everything else must be https.
 */
data class BackendConfig(val baseUrl: String, val publishableKey: String) {

    val isConfigured: Boolean
        get() = publishableKey.isNotBlank() && (baseUrl.startsWith("https://") || isLocal(baseUrl))

    companion object {
        fun fromBuild(): BackendConfig =
            BackendConfig(BuildConfig.SUPABASE_URL.trim().trimEnd('/'), BuildConfig.SUPABASE_PUBLISHABLE_KEY.trim())

        private fun isLocal(url: String): Boolean =
            url.startsWith("http://127.0.0.1") || url.startsWith("http://localhost")
    }
}
