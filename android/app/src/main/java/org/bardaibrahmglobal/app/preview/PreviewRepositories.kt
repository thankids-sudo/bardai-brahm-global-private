package org.bardaibrahmglobal.app.preview

import kotlinx.coroutines.delay
import org.bardaibrahmglobal.app.data.Chapter
import org.bardaibrahmglobal.app.data.ChapterRepository
import org.bardaibrahmglobal.app.data.CommunityEvent
import org.bardaibrahmglobal.app.data.EventRepository

/**
 * Preview-only implementations. They intentionally return no records: no chapters or
 * events exist yet, and M1 must not show invented live data. The short delay exercises
 * the loading state.
 */
class PreviewChapterRepository : ChapterRepository {
    override suspend fun chapters(): List<Chapter> {
        delay(PREVIEW_LATENCY_MS)
        return emptyList()
    }
}

class PreviewEventRepository : EventRepository {
    override suspend fun upcomingEvents(): List<CommunityEvent> {
        delay(PREVIEW_LATENCY_MS)
        return emptyList()
    }
}

private const val PREVIEW_LATENCY_MS = 400L
