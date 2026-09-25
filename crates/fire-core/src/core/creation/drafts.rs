impl FireCore {
    pub async fn fetch_drafts(
        &self,
        offset: Option<u32>,
        limit: Option<u32>,
    ) -> Result<DraftListResponse, FireCoreError> {
        info!(offset = ?offset, limit = ?limit, "fetching drafts");

        let mut params = Vec::new();
        if let Some(offset) = offset {
            params.push(("offset", offset.to_string()));
        }
        if let Some(limit) = limit.filter(|value| *value > 0) {
            params.push(("limit", limit.to_string()));
        }

        let traced = self.build_json_get_request("fetch drafts", "/drafts.json", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch drafts", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("fetch drafts", trace_id, response)
            .await?;
        parse_draft_list_response_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "fetch drafts",
            source,
        })
    }

    pub async fn fetch_draft(&self, draft_key: &str) -> Result<Option<Draft>, FireCoreError> {
        info!(draft_key, "fetching draft");

        let path = format!("/drafts/{}.json", encode_path_segment(draft_key));
        let traced = self.build_json_get_request("fetch draft", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        if response.status() == StatusCode::NOT_FOUND {
            let _ = self.read_response_text(trace_id, response).await?;
            return Ok(None);
        }

        let response = expect_success(self, "fetch draft", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("fetch draft", trace_id, response)
            .await?;
        parse_draft_detail_response_value(raw, draft_key).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch draft",
                source,
            }
        })
    }

    pub async fn save_draft(
        &self,
        draft_key: &str,
        data: DraftData,
        sequence: u32,
    ) -> Result<u32, FireCoreError> {
        info!(
            draft_key,
            sequence,
            has_content = data.has_content(),
            "saving draft"
        );

        let payload = serde_json::to_string(&data).map_err(FireCoreError::DiagnosticsSerialize)?;
        let fields = vec![
            ("draft_key", draft_key.to_string()),
            ("data", payload),
            ("sequence", sequence.to_string()),
        ];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("save draft", || {
                self.build_form_request(
                    "save draft",
                    Method::POST,
                    "/drafts.json",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        if response.status() == StatusCode::CONFLICT {
            let raw: Value = self
                .read_response_json("save draft", trace_id, response)
                .await?;
            return Ok(integer_u32(
                raw.as_object()
                    .and_then(|object| object.get("draft_sequence")),
            )
            .unwrap_or(sequence));
        }

        let response = expect_success(self, "save draft", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("save draft", trace_id, response)
            .await?;
        Ok(integer_u32(
            raw.as_object()
                .and_then(|object| object.get("draft_sequence")),
        )
        .unwrap_or(sequence.saturating_add(1)))
    }

    pub async fn delete_draft(
        &self,
        draft_key: &str,
        sequence: Option<u32>,
    ) -> Result<(), FireCoreError> {
        info!(draft_key, sequence = ?sequence, "deleting draft");

        let path = if let Some(sequence) = sequence {
            format!(
                "/drafts/{}.json?sequence={sequence}",
                encode_path_segment(draft_key)
            )
        } else {
            format!("/drafts/{}.json", encode_path_segment(draft_key))
        };
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("delete draft", || {
                self.build_api_request("delete draft", Method::DELETE, &path, true)
            })
            .await?;
        if response.status() == StatusCode::NOT_FOUND {
            let _ = self.read_response_text(trace_id, response).await?;
            return Ok(());
        }

        let response = expect_success(self, "delete draft", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}
