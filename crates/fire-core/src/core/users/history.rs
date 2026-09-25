impl FireCore {
    pub async fn fetch_read_history(
        &self,
        page: Option<u32>,
    ) -> Result<TopicListResponse, FireCoreError> {
        info!(?page, "fetching read history");
        let mut params = Vec::new();
        if let Some(page) = page.filter(|page| *page > 0) {
            params.push(("page", page.to_string()));
        }
        let traced =
            self.build_json_get_request("fetch read history", "/read.json", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch read history", trace_id, response).await?;
        let raw: RawTopicListResponse = self
            .read_response_json("fetch read history", trace_id, response)
            .await?;
        let result: TopicListResponse = raw.into();
        info!(
            topic_count = result.topics.len(),
            has_more = result.more_topics_url.is_some(),
            "read history fetched successfully"
        );
        Ok(result)
    }

    pub async fn fetch_bookmarks(
        &self,
        username: &str,
        page: Option<u32>,
    ) -> Result<TopicListResponse, FireCoreError> {
        info!(username, ?page, "fetching user bookmarks");
        let path = format!("/u/{username}/bookmarks.json");
        let mut params = Vec::new();
        if let Some(page) = page {
            if page > 0 {
                params.push(("page", page.to_string()));
            }
        }
        let traced = self.build_json_get_request("fetch bookmarks", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch bookmarks", trace_id, response).await?;
        let raw: RawTopicListResponse = self
            .read_response_json("fetch bookmarks", trace_id, response)
            .await?;
        let result: TopicListResponse = raw.into();
        info!(
            username,
            topic_count = result.topics.len(),
            has_more = result.more_topics_url.is_some(),
            "user bookmarks fetched successfully"
        );
        Ok(result)
    }
}
