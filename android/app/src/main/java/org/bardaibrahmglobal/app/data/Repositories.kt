package org.bardaibrahmglobal.app.data

import java.time.ZonedDateTime

/** Screen state shared by list screens. */
sealed interface UiState<out T> {
    data object Loading : UiState<Nothing>
    data object Empty : UiState<Nothing>
    data class Error(val cause: Throwable) : UiState<Nothing>
    data class Content<T>(val items: List<T>) : UiState<T>
}

enum class ChapterLevel { GLOBAL, COUNTRY, STATE, DISTRICT, CITY }

data class Chapter(
    val id: String,
    val name: String,
    val level: ChapterLevel,
    val parentId: String?,
)

data class CommunityEvent(
    val id: String,
    val title: String,
    val chapterName: String,
    val startsAt: ZonedDateTime,
    val isOnline: Boolean,
)

/**
 * Repository contracts. M1 binds these to preview implementations that hold no real data.
 * M2+ will add backend-backed implementations with server-side authorisation.
 */
interface ChapterRepository {
    suspend fun chapters(): List<Chapter>
}

interface EventRepository {
    suspend fun upcomingEvents(): List<CommunityEvent>
}

suspend fun <T> loadState(block: suspend () -> List<T>): UiState<T> =
    try {
        val items = block()
        if (items.isEmpty()) UiState.Empty else UiState.Content(items)
    } catch (e: kotlin.coroutines.cancellation.CancellationException) {
        throw e
    } catch (e: Exception) {
        UiState.Error(e)
    }
