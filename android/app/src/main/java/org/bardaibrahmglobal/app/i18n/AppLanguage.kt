package org.bardaibrahmglobal.app.i18n

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat

/** Languages supported from the first release. */
enum class AppLanguage(val tag: String) {
    ENGLISH("en"),
    GUJARATI("gu");

    companion object {
        /**
         * Maps a stored/system language tag list (e.g. "gu-IN,en") to a supported language.
         * Empty means "follow system", which resolves to Gujarati only if the device prefers it.
         */
        fun fromTags(tags: String, systemTag: String = ""): AppLanguage {
            val first = tags.split(',').firstOrNull { it.isNotBlank() }?.trim().orEmpty()
            val candidate = first.ifEmpty { systemTag }
            return if (candidate.lowercase().startsWith("gu")) GUJARATI else ENGLISH
        }
    }
}

/** Thin wrapper over AppCompat per-app locales; persistence is handled by AppCompat/Android. */
object LanguageController {
    fun current(systemTag: String): AppLanguage =
        AppLanguage.fromTags(AppCompatDelegate.getApplicationLocales().toLanguageTags(), systemTag)

    fun apply(language: AppLanguage) {
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(language.tag))
    }
}
