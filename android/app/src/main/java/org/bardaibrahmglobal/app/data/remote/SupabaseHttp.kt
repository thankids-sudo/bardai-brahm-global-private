package org.bardaibrahmglobal.app.data.remote

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

@Serializable
data class TokenResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("expires_in") val expiresIn: Long = 3600,
    val user: AuthUser? = null,
)

@Serializable
data class AuthUser(val id: String, val email: String? = null)

/**
 * Minimal client for Supabase Auth (GoTrue) and the database API (PostgREST, schema `api` only).
 * No business rules here: the database enforces them.
 */
class SupabaseHttp(
    private val config: BackendConfig,
    private val client: OkHttpClient = defaultClient(),
) {
    val json = Json { ignoreUnknownKeys = true; explicitNulls = false }
    private val jsonType = "application/json; charset=utf-8".toMediaType()

    /** Returns tokens if the project does not require email confirmation; null if a link was emailed. */
    suspend fun signUp(email: String, password: String, redirectTo: String): TokenResponse? {
        val body = buildJsonObject { put("email", email); put("password", password) }
        val res = authCall("signup?redirect_to=" + java.net.URLEncoder.encode(redirectTo, "UTF-8"), body, null)
        val obj = res.jsonObject
        return if (obj.containsKey("access_token")) json.decodeFromJsonElement(TokenResponse.serializer(), obj) else null
    }

    suspend fun signInWithPassword(email: String, password: String): TokenResponse {
        val body = buildJsonObject { put("email", email); put("password", password) }
        return json.decodeFromJsonElement(TokenResponse.serializer(), authCall("token?grant_type=password", body, null))
    }

    suspend fun refresh(refreshToken: String): TokenResponse {
        val body = buildJsonObject { put("refresh_token", refreshToken) }
        return json.decodeFromJsonElement(TokenResponse.serializer(), authCall("token?grant_type=refresh_token", body, null))
    }

    suspend fun resendConfirmation(email: String, redirectTo: String) {
        val body = buildJsonObject { put("type", "signup"); put("email", email) }
        authCall("resend?redirect_to=" + java.net.URLEncoder.encode(redirectTo, "UTF-8"), body, null)
    }

    suspend fun signOut(accessToken: String) {
        authCall("logout", JsonObject(emptyMap()), accessToken)
    }

    /** Calls a function in schema `api`. Returns the JSON result (JsonNull for void functions). */
    suspend fun rpc(function: String, params: JsonObject, accessToken: String): JsonElement {
        require(function.matches(Regex("^[a-z_]+$"))) { "invalid function name" }
        val request = Request.Builder()
            .url("${config.baseUrl}/rest/v1/rpc/$function")
            .header("apikey", config.publishableKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Profile", "api")
            .header("Accept-Profile", "api")
            .post(json.encodeToString(JsonObject.serializer(), params).toRequestBody(jsonType))
            .build()
        return execute(request, isAuth = false)
    }

    private suspend fun authCall(path: String, body: JsonObject, bearer: String?): JsonElement {
        if (!config.isConfigured) throw BackendError.NotConfigured()
        val builder = Request.Builder()
            .url("${config.baseUrl}/auth/v1/$path")
            .header("apikey", config.publishableKey)
            .post(json.encodeToString(JsonObject.serializer(), body).toRequestBody(jsonType))
        if (bearer != null) builder.header("Authorization", "Bearer $bearer")
        return execute(builder.build(), isAuth = true)
    }

    private suspend fun execute(request: Request, isAuth: Boolean): JsonElement = withContext(Dispatchers.IO) {
        if (!config.isConfigured) throw BackendError.NotConfigured()
        val response = try {
            client.newCall(request).execute()
        } catch (e: IOException) {
            throw BackendError.Network(e)
        }
        response.use { r ->
            val text = r.body?.string().orEmpty()
            if (r.isSuccessful) {
                return@withContext if (text.isBlank()) JsonNull else json.parseToJsonElement(text)
            }
            throw if (isAuth) authError(r.code, text) else apiError(r.code, text)
        }
    }

    private fun field(text: String, name: String): String? = try {
        json.parseToJsonElement(text).jsonObject[name]?.jsonPrimitive?.contentOrNull
    } catch (e: Exception) {
        null
    }

    private fun authError(status: Int, text: String): BackendError {
        val code = field(text, "error_code") ?: field(text, "error")
        return when {
            code == "email_not_confirmed" -> BackendError.EmailNotConfirmed()
            code == "invalid_credentials" || code == "invalid_grant" -> BackendError.InvalidCredentials()
            code == "weak_password" -> BackendError.WeakPassword()
            status == 429 || code?.startsWith("over_") == true -> BackendError.RateLimited()
            status == 401 -> BackendError.Unauthorized()
            status == 422 || status == 400 -> BackendError.InvalidInput()
            else -> BackendError.Server(code ?: status.toString())
        }
    }

    private fun apiError(status: Int, text: String): BackendError {
        val code = field(text, "code")
        if (code == null && status == 401) return BackendError.Unauthorized()
        return BackendError.fromSqlState(code)
    }

    companion object {
        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
    }
}
