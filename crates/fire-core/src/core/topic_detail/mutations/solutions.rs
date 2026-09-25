impl ActorState {
    pub(super) async fn accept_solution(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
        accepted: bool,
    ) -> Result<(), FireCoreError> {
        if accepted {
            core.accept_solution(post_id).await?;
        } else {
            core.unaccept_solution(post_id).await?;
        }
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

}
