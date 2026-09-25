pub fn attach_post_presentation(post: &mut TopicPost, base_url: &str) {
    if post.presented.get().is_none() {
        post.presented = present_cooked_html(&post.cooked, base_url)
            .map(|document| AttachedPresentation::some(Arc::new(document)))
            .unwrap_or_default();
    }
    for boost in &mut post.boosts {
        attach_boost_presentation(boost, base_url);
    }
}

pub fn attach_boost_presentation(boost: &mut TopicPostBoost, base_url: &str) {
    if boost.presented.get().is_some() {
        return;
    }
    boost.presented = present_cooked_html(&boost.cooked, base_url)
        .map(|document| AttachedPresentation::some(Arc::new(document)))
        .unwrap_or_default();
}

pub fn attach_chat_message_presentation(message: &mut ChatMessage, base_url: &str) {
    if message.presented.get().is_some() {
        return;
    }
    message.presented = present_cooked_html(&message.cooked, base_url)
        .map(|document| AttachedPresentation::some(Arc::new(document)))
        .unwrap_or_default();
}

pub fn attach_posts_presentation(posts: &mut [TopicPost], base_url: &str) {
    for post in posts {
        attach_post_presentation(post, base_url);
    }
}

