#[uniffi::export]
impl FireAppCore {
    #[uniffi::constructor]
    pub fn new(
        base_url: Option<String>,
        workspace_path: Option<String>,
    ) -> Result<Arc<Self>, FireUniFfiError> {
        let shared = Arc::new(SharedFireCore::bootstrap(base_url, workspace_path)?);
        Ok(Arc::new(Self {
            shared: shared.clone(),
            chat: FireChatHandle::from_shared(shared.clone()),
            diagnostics: FireDiagnosticsHandle::from_shared(shared.clone()),
            ldc: FireLdcHandle::from_shared(shared.clone()),
            messagebus: FireMessageBusHandle::from_shared(shared.clone()),
            notifications: FireNotificationsHandle::from_shared(shared.clone()),
            search: FireSearchHandle::from_shared(shared.clone()),
            session: FireSessionHandle::from_shared(shared.clone()),
            topics: FireTopicsHandle::from_shared(shared.clone()),
            user: FireUserHandle::from_shared(shared),
        }))
    }

}
