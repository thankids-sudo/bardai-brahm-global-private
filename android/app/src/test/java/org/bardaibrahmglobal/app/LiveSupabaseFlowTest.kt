package org.bardaibrahmglobal.app

import java.sql.DriverManager
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.bardaibrahmglobal.app.data.auth.AuthRepository
import org.bardaibrahmglobal.app.data.auth.InMemoryRefreshTokenStore
import org.bardaibrahmglobal.app.data.auth.SignUpOutcome
import org.bardaibrahmglobal.app.data.membership.ApplicationForm
import org.bardaibrahmglobal.app.data.membership.MembershipRepository
import org.bardaibrahmglobal.app.data.membership.ReviewDecision
import org.bardaibrahmglobal.app.data.remote.BackendConfig
import org.bardaibrahmglobal.app.data.remote.BackendError
import org.bardaibrahmglobal.app.data.remote.SupabaseHttp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

/**
 * The app's real networking code against a LOCAL Supabase stack (started by CI with `supabase start`).
 * Skipped unless BBG_LIVE_SUPABASE_URL, BBG_LIVE_SUPABASE_KEY and BBG_LIVE_DB_URL are set.
 * The database connection is used only for operator steps the app can never do
 * (confirming test emails, creating chapters, the one-time admin bootstrap).
 */
class LiveSupabaseFlowTest {
    private val url = System.getenv("BBG_LIVE_SUPABASE_URL").orEmpty()
    private val key = System.getenv("BBG_LIVE_SUPABASE_KEY").orEmpty()
    private val db = System.getenv("BBG_LIVE_DB_URL").orEmpty()

    @Before fun requireLiveBackend() = assumeTrue(url.isNotBlank() && key.isNotBlank() && db.isNotBlank())

    private fun sql(statement: String, vararg args: Any?): List<List<Any?>> =
        DriverManager.getConnection(db).use { c ->
            c.prepareStatement(statement).use { ps ->
                args.forEachIndexed { i, a -> ps.setObject(i + 1, a) }
                if (!ps.execute()) return emptyList()
                ps.resultSet.use { rs ->
                    val rows = mutableListOf<List<Any?>>()
                    while (rs.next()) rows += (1..rs.metaData.columnCount).map { rs.getObject(it) }
                    rows
                }
            }
        }

    private fun newAuth() = AuthRepository(SupabaseHttp(BackendConfig(url, key)), InMemoryRefreshTokenStore())
    private fun confirmEmail(email: String) = sql("update auth.users set email_confirmed_at = now() where lower(email) = lower(?)", email)
    private fun accountId(email: String) = sql("select id from app.accounts where lower(email) = lower(?)", email).single()[0].toString()

    @Test fun signUpApplyCorrectApproveThroughTheAppClient() = runBlocking {
        val run = UUID.randomUUID().toString().take(8)
        val adminEmail = "live-admin-$run@example.test"
        val secEmail = "live-sec-$run@example.test"
        val annEmail = "live-ann-$run@example.test"
        val pw = "Live-Test-Password-9"

        // Sign-up through the app client; the project requires email confirmation.
        val admin = newAuth(); val sec = newAuth(); val ann = newAuth()
        assertEquals(SignUpOutcome.ConfirmationSent, admin.signUp(adminEmail, pw))
        assertEquals(SignUpOutcome.ConfirmationSent, sec.signUp(secEmail, pw))
        assertEquals(SignUpOutcome.ConfirmationSent, ann.signUp(annEmail, pw))
        try { ann.signIn(annEmail, pw); fail("sign-in must wait for email confirmation") } catch (e: BackendError.EmailNotConfirmed) { }
        listOf(adminEmail, secEmail, annEmail).forEach { confirmEmail(it) }

        // Operator setup: chapters and the one-time global admin bootstrap.
        val global = sql("insert into app.chapters (level, name_en, name_gu, accepts_applications) values ('global', 'Live Global', 'લાઇવ વૈશ્વિક', false) returning id").single()[0].toString()
        val city = sql("insert into app.chapters (level, parent_id, name_en, name_gu, country_code) values ('city', ?::uuid, 'Live City', 'લાઇવ શહેર', 'IN') returning id", global).single()[0].toString()
        sql("select app.bootstrap_global_admin(?)", adminEmail)

        admin.signIn(adminEmail, pw)
        admin.rpc("grant_role", buildJsonObject {
            put("p_account", accountId(secEmail)); put("p_role", "chapter_secretary"); put("p_chapter", city)
        })

        // Applicant: verified, not yet a member, cannot use the directory.
        ann.signIn(annEmail, pw)
        val annApi = MembershipRepository(ann)
        val status = annApi.myStatus()
        assertTrue(status.emailVerified)
        assertNull(status.membershipStatus)
        assertTrue(annApi.chapters().any { it.id == city && it.hasSecretary })
        try { ann.rpc("directory_search", buildJsonObject { put("p_query", "Live") }); fail("non-member searched the directory") }
        catch (e: BackendError.NotAllowed) { }
        try { ann.rpc("grant_role", buildJsonObject { put("p_account", accountId(annEmail)); put("p_role", "global_admin"); put("p_chapter", null as String?) }); fail("self-promotion") }
        catch (e: BackendError.NotAllowed) { }

        val form = ApplicationForm(city, "Ann", "Livebhai", "1988", "Gam", "Live City", "in")
        assertNotNull(annApi.submit(form))
        assertEquals("pending", annApi.myApplication()?.status)
        try { annApi.submit(form); fail("second open application") } catch (e: BackendError.AlreadyExists) { }

        // Secretary asks for a correction; applicant fixes and resends.
        sec.signIn(secEmail, pw)
        val secApi = MembershipRepository(sec)
        assertTrue(secApi.myRoles().any { it.role == "chapter_secretary" && it.chapterId == city })
        val item = secApi.reviewQueue().single { it.surname == "Livebhai" }
        assertEquals("IN", item.presentCountry)
        secApi.review(item.applicationId, ReviewDecision.CORRECTION, "Please write your full surname")
        val returned = annApi.myApplication()!!
        assertEquals("correction_requested", returned.status)
        assertEquals("Please write your full surname", returned.reviewerNote)
        annApi.resubmit(returned.id, form.copy(surname = "Livebhai Patel"))

        // Applicant cannot approve anything; the secretary approves.
        try { annApi.review(returned.id, ReviewDecision.APPROVE, ""); fail("applicant approved") } catch (e: BackendError.NotAllowed) { }
        secApi.review(item.applicationId, ReviewDecision.APPROVE, "")
        val member = annApi.myStatus()
        assertEquals("approved", member.membershipStatus)
        assertTrue(member.memberCode!!.startsWith("BBG-"))

        // A stored refresh token restores the session (real refresh against Supabase Auth).
        val store = InMemoryRefreshTokenStore()
        AuthRepository(SupabaseHttp(BackendConfig(url, key)), store).signIn(annEmail, pw)
        val restored = AuthRepository(SupabaseHttp(BackendConfig(url, key)), store)
        assertTrue(restored.restore())
        assertEquals("approved", MembershipRepository(restored).myStatus().membershipStatus)

        // Sign-out ends access.
        ann.signOut()
        assertFalse(ann.isSignedIn)
        try { annApi.myStatus(); fail("signed-out call succeeded") } catch (e: BackendError.NotSignedIn) { }
    }
}
