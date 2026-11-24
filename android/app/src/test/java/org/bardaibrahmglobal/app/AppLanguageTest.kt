package org.bardaibrahmglobal.app

import org.bardaibrahmglobal.app.i18n.AppLanguage
import org.junit.Assert.assertEquals
import org.junit.Test

class AppLanguageTest {
    @Test fun storedGujaratiWins() = assertEquals(AppLanguage.GUJARATI, AppLanguage.fromTags("gu", "en-US"))
    @Test fun regionalGujaratiTagIsGujarati() = assertEquals(AppLanguage.GUJARATI, AppLanguage.fromTags("gu-IN,en"))
    @Test fun storedEnglishOverridesGujaratiDevice() = assertEquals(AppLanguage.ENGLISH, AppLanguage.fromTags("en", "gu-IN"))
    @Test fun emptyFollowsGujaratiDevice() = assertEquals(AppLanguage.GUJARATI, AppLanguage.fromTags("", "gu-IN"))
    @Test fun unsupportedDeviceLanguageFallsBackToEnglish() = assertEquals(AppLanguage.ENGLISH, AppLanguage.fromTags("", "hi-IN"))
    @Test fun blankEntriesIgnored() = assertEquals(AppLanguage.GUJARATI, AppLanguage.fromTags(" ,gu", "en"))
}
