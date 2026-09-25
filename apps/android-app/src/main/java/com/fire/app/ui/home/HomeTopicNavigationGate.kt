package com.fire.app.ui.home

class HomeTopicNavigationGate {
    private var openingTopicDetail = false

    fun tryBeginOpeningTopicDetail(): Boolean {
        if (openingTopicDetail) {
            return false
        }
        openingTopicDetail = true
        return true
    }

    fun reset() {
        openingTopicDetail = false
    }
}
