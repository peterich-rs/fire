#[uniffi::export]
impl FireTopicsHandle {
    pub async fn accept_solution(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("accept_solution", panic_state, async move {
            inner.accept_solution(post_id).await
        })
        .await
    }

    pub async fn unaccept_solution(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("unaccept_solution", panic_state, async move {
            inner.unaccept_solution(post_id).await
        })
        .await
    }

}
