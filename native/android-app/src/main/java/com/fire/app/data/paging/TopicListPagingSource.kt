package com.fire.app.data.paging

import androidx.paging.PagingSource
import androidx.paging.PagingState
import com.fire.app.cloudflare.CloudflareChallengeDetector
import com.fire.app.cloudflare.CloudflareChallengeRecoveryError
import com.fire.app.data.repository.TopicRepository
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicRowState

class TopicListPagingSource(
    private val repository: TopicRepository,
    private val kind: TopicListKindState,
    private val baseUrl: String? = null,
    private val categorySlug: String? = null,
    private val categoryId: ULong? = null,
    private val parentCategorySlug: String? = null,
    private val tag: String? = null,
    private val additionalTags: List<String> = emptyList(),
    private val matchAllTags: Boolean = false,
) : PagingSource<UInt, TopicRowState>() {

    override fun getRefreshKey(state: PagingState<UInt, TopicRowState>): UInt? {
        return state.anchorPosition?.let { position ->
            state.closestPageToPosition(position)?.prevKey?.plus(1u)
                ?: state.closestPageToPosition(position)?.nextKey?.minus(1u)
        }
    }

    override suspend fun load(params: LoadParams<UInt>): LoadResult<UInt, TopicRowState> {
        val page = params.key ?: 0u
        return try {
            val response = repository.fetchTopicList(
                kind = kind,
                page = params.key,
                categorySlug = categorySlug,
                categoryId = categoryId,
                parentCategorySlug = parentCategorySlug,
                tag = tag,
                additionalTags = additionalTags,
                matchAllTags = matchAllTags,
            )
            val rows = response.rows
            LoadResult.Page(
                data = rows,
                prevKey = if (page == 0u) null else page - 1u,
                nextKey = response.nextPage,
            )
        } catch (e: Exception) {
            val error = if (CloudflareChallengeDetector.isChallenge(e)) {
                CloudflareChallengeRecoveryError(recoveryUrl(params.key), e)
            } else {
                e
            }
            LoadResult.Error(error)
        }
    }

    private fun recoveryUrl(page: UInt?): String =
        TopicListRecoveryUrl.htmlUrl(
            baseUrl = baseUrl,
            kind = kind,
            page = page,
            categorySlug = categorySlug,
            categoryId = categoryId,
            parentCategorySlug = parentCategorySlug,
            tag = tag,
            additionalTags = additionalTags,
            matchAllTags = matchAllTags,
        )
}
