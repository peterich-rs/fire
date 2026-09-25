impl FireCore {
    pub async fn fetch_badge_detail(&self, badge_id: u64) -> Result<Badge, FireCoreError> {
        info!(badge_id, "fetching badge detail");
        let path = format!("/badges/{badge_id}.json");
        let traced = self.build_json_get_request("fetch badge detail", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch badge detail", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch badge detail", trace_id, response)
            .await?;
        let badge =
            parse_badge_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
                operation: "fetch badge detail",
                source,
            })?;
        info!(badge_id = badge.id, badge_name = %badge.name, "badge detail fetched successfully");
        Ok(badge)
    }

}
