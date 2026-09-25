#[uniffi::export]
impl FireAppCore {
    pub fn chat(&self) -> Arc<FireChatHandle> {
        self.chat.clone()
    }

    pub fn diagnostics(&self) -> Arc<FireDiagnosticsHandle> {
        self.diagnostics.clone()
    }

    pub fn ldc(&self) -> Arc<FireLdcHandle> {
        self.ldc.clone()
    }

    pub fn messagebus(&self) -> Arc<FireMessageBusHandle> {
        self.messagebus.clone()
    }

    pub fn notifications(&self) -> Arc<FireNotificationsHandle> {
        self.notifications.clone()
    }

    pub fn search(&self) -> Arc<FireSearchHandle> {
        self.search.clone()
    }

    pub fn session(&self) -> Arc<FireSessionHandle> {
        self.session.clone()
    }

    pub fn topics(&self) -> Arc<FireTopicsHandle> {
        self.topics.clone()
    }

    pub fn user(&self) -> Arc<FireUserHandle> {
        self.user.clone()
    }

}
