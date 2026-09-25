impl FireCore {
    pub async fn lookup_upload_urls(
        &self,
        short_urls: Vec<String>,
    ) -> Result<Vec<ResolvedUploadUrl>, FireCoreError> {
        if short_urls.is_empty() {
            return Ok(Vec::new());
        }

        info!(
            short_urls_count = short_urls.len(),
            "looking up upload urls"
        );

        let body = json!({ "short_urls": short_urls }).to_string();
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("lookup upload urls", || {
                self.build_api_request_with_body(
                    "lookup upload urls",
                    Method::POST,
                    "/uploads/lookup-urls",
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.clone()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "lookup upload urls", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("lookup upload urls", trace_id, response)
            .await?;
        parse_resolved_upload_urls_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "lookup upload urls",
            source,
        })
    }

    pub async fn upload_image(
        &self,
        file_name: &str,
        mime_type: Option<&str>,
        bytes: Vec<u8>,
    ) -> Result<UploadResult, FireCoreError> {
        info!(
            file_name,
            has_mime_type = mime_type.is_some(),
            bytes_len = bytes.len(),
            "uploading composer image"
        );

        let client_id = upload_client_id(&self.message_bus);
        let boundary = multipart_boundary();
        let content_type = format!("multipart/form-data; boundary={boundary}");
        let path = format!("/uploads.json?client_id={client_id}");
        let request_body = multipart_upload_body(
            &boundary,
            file_name,
            mime_type.unwrap_or("application/octet-stream"),
            &bytes,
        );

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("upload image", || {
                self.build_api_request_with_body(
                    "upload image",
                    Method::POST,
                    &path,
                    Some(&content_type),
                    RequestBody::from(request_body.clone()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "upload image", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("upload image", trace_id, response)
            .await?;
        parse_upload_result_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "upload image",
            source,
        })
    }

}
