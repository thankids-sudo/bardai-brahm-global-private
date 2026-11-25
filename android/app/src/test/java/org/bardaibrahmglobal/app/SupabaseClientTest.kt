package org.bardaibrahmglobal.app

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.bardaibrahmglobal.app.data.auth.AuthRepository
import org.bardaibrahmglobal.app.data.auth.InMemoryRefreshTokenStore
import org.bardaibrahmglobal.app.data.membership.ApplicationForm
import org.bardaibrahmglobal.app.data.membership.FormRules
import org.bardaibrahmglobal.app.data.membership.MembershipRepository
import org.bardaibrahmglobal.app.data.remote.BackendConfig
import org.bardaibrahmglobal.app.data.remote.BackendError
import org.bardaibrahmglobal.app.data.remote.SupabaseHttp
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** HTTP-level behaviour of the client against a scripted server. */
class SupabaseClientTest {
    private lateinit var server: MockWebServer
    private lateinit var http: SupabaseHttp
    private lateinit var store: InMemoryRefreshTokenStore
    private lateinit var auth: AuthRepository

    private val tokens = """{"access_token":"access-1","refresh_token":"refresh-1","expires_in":3600,"user":{"id":"u1"}}"""

    @Before fun setUp() {
        server = MockWebServer()
        server.start(java.net.InetAddress.getByName("127.0.0.1"), 0)
        http = SupabaseHttp(BackendConfig("http://127.0.0.1:${server.port}", "publishable-key"))
        store = InMemoryRefreshTokenStore()
        auth = AuthRepository(http, store)
    }

    @After fun tearDown() = server.shutdown()

    private fun json(code: Int, body: String) = MockResponse().setResponseCode(code).setBody(body)
        .addHeader("Content-Type", "application/json")

    @Test fun signInStoresOnlyTheRefreshToken() = runBlocking {
        server.enqueue(json(200, tokens))
        auth.signIn(" ann@example.test ", "pw")
        val req = server.takeRequest()
        assertEquals("/auth/v1/token?grant_type=password", req.path)
        assertEquals("publishable-key", req.getHeader("apikey"))
        assertTrue(req.body.readUtf8().contains("\"email\":\"ann@example.test\""))
        assertEquals("refresh-1", store.load())
        assertTrue(auth.isSignedIn)
    }

    @Test fun unconfirmedEmailIsRecognised() = runBlocking {
        server.enqueue(json(400, """{"code":400,"error_code":"email_not_confirmed","msg":"Email not confirmed"}"""))
        try { auth.signIn("a@example.test", "pw"); fail("expected error") } catch (e: BackendError.EmailNotConfirmed) { }
        assertFalse(auth.isSignedIn)
    }

    @Test fun wrongPasswordIsRecognised() = runBlocking {
        server.enqueue(json(400, """{"error":"invalid_grant","error_description":"Invalid login credentials"}"""))
        try { auth.signIn("a@example.test", "pw"); fail("expected error") } catch (e: BackendError.InvalidCredentials) { }
    }

    @Test fun signUpWithConfirmationReturnsNoSession() = runBlocking {
        server.enqueue(json(200, """{"id":"u2","email":"b@example.test","confirmation_sent_at":"2026-11-25T10:00:00Z"}"""))
        val outcome = auth.signUp("b@example.test", "long-enough-pw")
        assertEquals(org.bardaibrahmglobal.app.data.auth.SignUpOutcome.ConfirmationSent, outcome)
        assertTrue(server.takeRequest().path!!.contains("redirect_to=org.bardaibrahmglobal.app"))
        assertFalse(auth.isSignedIn)
    }

    @Test fun rpcSendsUserTokenAndApiSchemaHeaders() = runBlocking {
        server.enqueue(json(200, tokens))
        auth.signIn("a@example.test", "pw")
        server.takeRequest()
        server.enqueue(json(200, """[{"email_verified":true,"account_status":"active","member_code":null}]"""))
        val status = MembershipRepository(auth).myStatus()
        val req = server.takeRequest()
        assertEquals("/rest/v1/rpc/my_status", req.path)
        assertEquals("Bearer access-1", req.getHeader("Authorization"))
        assertEquals("api", req.getHeader("Accept-Profile"))
        assertEquals("api", req.getHeader("Content-Profile"))
        assertTrue(status.emailVerified)
        assertNull(status.memberCode)
    }

    @Test fun databaseRefusalsMapToTypedErrors() = runBlocking {
        server.enqueue(json(200, tokens))
        auth.signIn("a@example.test", "pw")
        val membership = MembershipRepository(auth)
        val cases = listOf(
            """{"code":"42501","message":"not secretary of this chapter"}""" to BackendError.NotAllowed::class,
            """{"code":"23505","message":"duplicate"}""" to BackendError.AlreadyExists::class,
            """{"code":"55000","message":"not pending"}""" to BackendError.WrongState::class,
            """{"code":"22023","message":"invalid"}""" to BackendError.InvalidInput::class,
        )
        for ((body, expected) in cases) {
            server.enqueue(json(if (body.contains("42501")) 403 else 400, body))
            try {
                membership.reviewQueue(); fail("expected $expected")
            } catch (e: BackendError) {
                assertEquals(expected, e::class)
            }
        }
    }

    @Test fun expiredTokenIsRefreshedOnceAndTheCallRetried() = runBlocking {
        server.enqueue(json(200, tokens))
        auth.signIn("a@example.test", "pw")
        server.enqueue(json(401, """{"code":"PGRST303","message":"JWT expired"}"""))
        server.enqueue(json(200, """{"access_token":"access-2","refresh_token":"refresh-2","expires_in":3600}"""))
        server.enqueue(json(200, "[]"))
        assertTrue(MembershipRepository(auth).myRoles().isEmpty())
        server.takeRequest()                                   // sign-in
        assertEquals("Bearer access-1", server.takeRequest().getHeader("Authorization"))
        assertEquals("/auth/v1/token?grant_type=refresh_token", server.takeRequest().path)
        assertEquals("Bearer access-2", server.takeRequest().getHeader("Authorization"))
        assertEquals("refresh-2", store.load())
    }

    @Test fun failedRefreshSignsOutAndForgetsTheToken() = runBlocking {
        server.enqueue(json(200, tokens))
        auth.signIn("a@example.test", "pw")
        server.enqueue(json(401, """{"code":"PGRST303","message":"JWT expired"}"""))
        server.enqueue(json(400, """{"error":"invalid_grant","error_description":"Refresh token revoked"}"""))
        try { MembershipRepository(auth).myRoles(); fail("expected sign-out") } catch (e: BackendError.NotSignedIn) { }
        assertFalse(auth.isSignedIn)
        assertNull(store.load())
    }

    @Test fun noNetworkCallsWhenNotConfigured() = runBlocking {
        val offline = AuthRepository(SupabaseHttp(BackendConfig("", "")), InMemoryRefreshTokenStore())
        try { offline.signIn("a@example.test", "pw"); fail("expected NotConfigured") } catch (e: BackendError.NotConfigured) { }
        assertEquals(0, server.requestCount)
    }

    @Test fun emailLinkTokensAreAccepted() = runBlocking {
        val ok = auth.acceptCallbackFragment("access_token=a1&expires_in=3600&refresh_token=r1&token_type=bearer&type=signup")
        assertTrue(ok)
        assertTrue(auth.isSignedIn)
        assertEquals("r1", store.load())
        assertFalse(AuthRepository(http, InMemoryRefreshTokenStore()).acceptCallbackFragment("error=access_denied"))
    }

    @Test fun formRules() {
        val ok = ApplicationForm("ch", "Ann", "Testbhai", "1985", "Gam", "City", "IN")
        assertTrue(FormRules.problems(ok, 2026).isEmpty())
        assertTrue(FormRules.problems(ok.copy(birthYear = ""), 2026).isEmpty())   // optional
        assertEquals(listOf("chapter"), FormRules.problems(ok.copy(chapterId = null), 2026))
        assertEquals(listOf("surname"), FormRules.problems(ok.copy(surname = "  "), 2026))
        assertEquals(listOf("birthYear"), FormRules.problems(ok.copy(birthYear = "2099"), 2026))
        assertEquals(listOf("presentCountry"), FormRules.problems(ok.copy(presentCountry = "IND"), 2026))
        assertTrue(FormRules.isEmail("a.b@example.org"))
        assertFalse(FormRules.isEmail("not an email"))
        assertFalse(FormRules.isStrongEnough("short"))
    }
}
