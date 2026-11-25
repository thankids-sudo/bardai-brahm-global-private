package org.bardaibrahmglobal.app.data.membership

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import org.bardaibrahmglobal.app.data.auth.AuthRepository

@Serializable
data class MyStatus(
    @SerialName("email_verified") val emailVerified: Boolean = false,
    @SerialName("account_status") val accountStatus: String? = null,
    @SerialName("application_status") val applicationStatus: String? = null,
    @SerialName("membership_status") val membershipStatus: String? = null,
    @SerialName("member_code") val memberCode: String? = null,
)

@Serializable
data class MyApplication(
    @SerialName("application_id") val id: String,
    val status: String,
    @SerialName("chapter_id") val chapterId: String,
    @SerialName("chapter_name_en") val chapterNameEn: String,
    @SerialName("chapter_name_gu") val chapterNameGu: String,
    @SerialName("reviewer_note") val reviewerNote: String? = null,
    @SerialName("given_name") val givenName: String,
    val surname: String,
    @SerialName("birth_year") val birthYear: Int? = null,
    @SerialName("ancestral_village") val ancestralVillage: String? = null,
    @SerialName("present_city") val presentCity: String? = null,
    @SerialName("present_country") val presentCountry: String? = null,
)

@Serializable
data class ChapterOption(
    val id: String,
    @SerialName("name_en") val nameEn: String,
    @SerialName("name_gu") val nameGu: String,
    @SerialName("country_code") val countryCode: String? = null,
    @SerialName("is_global_intake") val isGlobalIntake: Boolean = false,
    @SerialName("has_secretary") val hasSecretary: Boolean = false,
)

@Serializable
data class RoleAssignment(
    val role: String,
    @SerialName("chapter_id") val chapterId: String? = null,
    @SerialName("chapter_name_en") val chapterNameEn: String? = null,
    @SerialName("chapter_name_gu") val chapterNameGu: String? = null,
)

@Serializable
data class QueueItem(
    @SerialName("application_id") val applicationId: String,
    @SerialName("chapter_name_en") val chapterNameEn: String,
    @SerialName("given_name") val givenName: String,
    val surname: String,
    @SerialName("birth_year") val birthYear: Int? = null,
    @SerialName("ancestral_village") val ancestralVillage: String? = null,
    @SerialName("present_city") val presentCity: String? = null,
    @SerialName("present_country") val presentCountry: String? = null,
    @SerialName("possible_duplicates") val possibleDuplicates: Int = 0,
    @SerialName("after_appeal") val afterAppeal: Boolean = false,
)

data class ApplicationForm(
    val chapterId: String?,
    val givenName: String,
    val surname: String,
    val birthYear: String,
    val ancestralVillage: String,
    val presentCity: String,
    val presentCountry: String,
)

enum class ReviewDecision(val wire: String) { APPROVE("approved"), CORRECTION("correction_requested"), REJECT("rejected") }

/** Membership calls. Every rule (who may do what) is enforced by the database, not here. */
class MembershipRepository(private val auth: AuthRepository) {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    suspend fun myStatus(): MyStatus = list(auth.rpc("my_status"), MyStatus.serializer()).firstOrNull() ?: MyStatus()
    suspend fun myApplication(): MyApplication? = list(auth.rpc("my_application"), MyApplication.serializer()).firstOrNull()
    suspend fun myRoles(): List<RoleAssignment> = list(auth.rpc("my_roles"), RoleAssignment.serializer())
    suspend fun chapters(): List<ChapterOption> = list(auth.rpc("list_chapters"), ChapterOption.serializer())
    suspend fun reviewQueue(): List<QueueItem> = list(auth.rpc("review_queue"), QueueItem.serializer())

    suspend fun submit(form: ApplicationForm): String? = scalar(auth.rpc("submit_application", buildJsonObject {
        put("p_chapter", form.chapterId)
        putPersonFields(form)
    }))

    suspend fun resubmit(applicationId: String, form: ApplicationForm) {
        auth.rpc("resubmit_application", buildJsonObject {
            put("p_application", applicationId)
            putPersonFields(form)
        })
    }

    suspend fun withdraw(applicationId: String) {
        auth.rpc("withdraw_application", buildJsonObject { put("p_application", applicationId) })
    }

    suspend fun review(applicationId: String, decision: ReviewDecision, note: String?) {
        auth.rpc("review_application", buildJsonObject {
            put("p_application", applicationId)
            put("p_decision", decision.wire)
            put("p_note", note?.trim()?.ifEmpty { null })
        })
    }

    /** Membership consent is recorded by submit_application itself; this only adds directory listing. */
    suspend fun setConsent(purpose: String, granted: Boolean) {
        auth.rpc("set_consent", buildJsonObject { put("p_purpose", purpose); put("p_granted", granted) })
    }

    private fun kotlinx.serialization.json.JsonObjectBuilder.putPersonFields(form: ApplicationForm) {
        put("p_given_name", form.givenName.trim())
        put("p_surname", form.surname.trim())
        put("p_birth_year", form.birthYear.trim().toIntOrNull())
        put("p_ancestral_village", form.ancestralVillage.trim().ifEmpty { null })
        put("p_present_city", form.presentCity.trim().ifEmpty { null })
        put("p_present_country", form.presentCountry.trim().uppercase().ifEmpty { null })
    }

    private fun <T> list(element: JsonElement, serializer: KSerializer<T>): List<T> = when (element) {
        is JsonArray -> json.decodeFromJsonElement(ListSerializer(serializer), element)
        is JsonObject -> listOf(json.decodeFromJsonElement(serializer, element))
        else -> emptyList()
    }

    private fun scalar(element: JsonElement): String? = (element as? JsonPrimitive)?.contentOrNull
}

/** Client-side checks for quick feedback only; the database re-checks everything. */
object FormRules {
    private val email = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
    private val country = Regex("^[A-Za-z]{2}$")
    const val MIN_PASSWORD = 10

    fun isEmail(value: String) = email.matches(value.trim())
    fun isStrongEnough(password: String) = password.length >= MIN_PASSWORD

    /** Returns the names of invalid fields (empty when the form can be sent). */
    fun problems(form: ApplicationForm, currentYear: Int): List<String> = buildList {
        if (form.chapterId.isNullOrBlank()) add("chapter")
        if (form.givenName.isBlank() || form.givenName.trim().length > 100) add("givenName")
        if (form.surname.isBlank() || form.surname.trim().length > 100) add("surname")
        val year = form.birthYear.trim()
        if (year.isNotEmpty() && (year.toIntOrNull() == null || year.toInt() !in 1900..currentYear)) add("birthYear")
        if (form.presentCountry.isNotBlank() && !country.matches(form.presentCountry.trim())) add("presentCountry")
        if (form.ancestralVillage.trim().length > 120) add("ancestralVillage")
        if (form.presentCity.trim().length > 120) add("presentCity")
    }
}
