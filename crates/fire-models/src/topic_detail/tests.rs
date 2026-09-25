use super::*;

#[test]
fn topic_detail_interaction_count_adds_non_heart_reactions_to_topic_likes() {
    let detail = TopicDetail {
        like_count: 21,
        post_stream: TopicPostStream {
            posts: vec![
                TopicPost {
                    reactions: vec![
                        TopicReaction {
                            id: "heart".into(),
                            count: 5,
                            ..TopicReaction::default()
                        },
                        TopicReaction {
                            id: "clap".into(),
                            count: 2,
                            ..TopicReaction::default()
                        },
                    ],
                    ..TopicPost::default()
                },
                TopicPost {
                    reactions: vec![TopicReaction {
                        id: "TADA".into(),
                        count: 3,
                        ..TopicReaction::default()
                    }],
                    ..TopicPost::default()
                },
            ],
            ..TopicPostStream::default()
        },
        ..TopicDetail::default()
    };

    assert_eq!(detail.interaction_count(), 26);
}

#[test]
fn topic_thread_groups_nested_replies_without_duplication() {
    let thread = TopicThread::from_posts(&[
        topic_post(1, None),
        topic_post(2, Some(1)),
        topic_post(3, Some(2)),
        topic_post(4, Some(3)),
        topic_post(5, Some(1)),
        topic_post(6, Some(99)),
    ]);

    assert_eq!(thread.original_post_number, Some(1));
    assert_eq!(
        thread
            .reply_sections
            .iter()
            .map(|section| section.anchor_post_number)
            .collect::<Vec<_>>(),
        vec![2, 5, 6]
    );
    assert_eq!(
        thread.reply_sections[0]
            .replies
            .iter()
            .map(|reply| reply.post_number)
            .collect::<Vec<_>>(),
        vec![3, 4]
    );
    assert_eq!(
        thread.reply_sections[0]
            .replies
            .iter()
            .map(|reply| reply.depth)
            .collect::<Vec<_>>(),
        vec![1, 2]
    );
}

#[test]
fn topic_thread_flattens_to_display_order_posts() {
    let posts = vec![
        topic_post(1, None),
        topic_post(2, Some(1)),
        topic_post(3, Some(2)),
        topic_post(4, Some(3)),
        topic_post(5, Some(1)),
        topic_post(6, Some(99)),
    ];
    let thread = TopicThread::from_posts(&posts);

    assert_eq!(
        thread
            .flatten(&posts)
            .into_iter()
            .map(|flat_post: TopicThreadFlatPost| (
                flat_post.post.post_number,
                flat_post.depth,
                flat_post.parent_post_number,
                flat_post.shows_thread_line,
                flat_post.is_original_post,
            ))
            .collect::<Vec<_>>(),
        vec![
            (1, 0, None, true, true),
            (2, 0, None, true, false),
            (3, 1, Some(2), true, false),
            (4, 2, Some(3), true, false),
            (5, 0, None, true, false),
            (6, 0, None, false, false),
        ]
    );
}

#[test]
fn timeline_entries_floor_order_with_full_post_set() {
    let posts = vec![
        topic_post(1, None),
        topic_post(2, Some(1)),
        topic_post(3, Some(2)),
        topic_post(4, Some(1)),
    ];
    let mut detail = TopicDetail {
        post_stream: TopicPostStream {
            posts,
            stream: vec![1, 2, 3, 4],
        },
        ..Default::default()
    };
    detail.rebuild_timeline_entries();

    assert_eq!(detail.timeline_entries.len(), 4);
    assert_eq!(detail.timeline_entries[0].post_number, 1);
    assert_eq!(detail.timeline_entries[0].depth, 0);
    assert!(detail.timeline_entries[0].is_original_post);
    assert_eq!(detail.timeline_entries[1].post_number, 2);
    assert_eq!(detail.timeline_entries[1].depth, 1);
    assert_eq!(detail.timeline_entries[1].parent_post_number, Some(1));
    assert_eq!(detail.timeline_entries[2].post_number, 3);
    assert_eq!(detail.timeline_entries[2].depth, 2);
    assert_eq!(detail.timeline_entries[2].parent_post_number, Some(2));
    assert_eq!(detail.timeline_entries[3].post_number, 4);
    assert_eq!(detail.timeline_entries[3].depth, 1);
    assert_eq!(detail.timeline_entries[3].parent_post_number, Some(1));
}

#[test]
fn timeline_entries_partial_set_falls_back_depth_for_missing_parents() {
    // Simulate an anchored load that only has posts 5-7, where 5 replies to 3 (not loaded).
    let posts = vec![
        topic_post(5, Some(3)),
        topic_post(6, Some(5)),
        topic_post(7, None),
    ];
    let mut detail = TopicDetail {
        post_stream: TopicPostStream {
            posts,
            stream: vec![1, 2, 3, 4, 5, 6, 7],
        },
        ..Default::default()
    };
    detail.rebuild_timeline_entries();

    assert_eq!(detail.timeline_entries.len(), 3);
    // Post 5 replies to 3 (not loaded) — depth falls back to 1.
    assert_eq!(detail.timeline_entries[0].post_number, 5);
    assert_eq!(detail.timeline_entries[0].depth, 1);
    assert_eq!(detail.timeline_entries[0].parent_post_number, Some(3));
    assert!(detail.timeline_entries[0].is_original_post); // min in partial set
                                                          // Post 6 replies to 5 (loaded) — depth is 2.
    assert_eq!(detail.timeline_entries[1].post_number, 6);
    assert_eq!(detail.timeline_entries[1].depth, 2);
    // Post 7 has no parent — depth is 0.
    assert_eq!(detail.timeline_entries[2].post_number, 7);
    assert_eq!(detail.timeline_entries[2].depth, 0);
}

#[test]
fn timeline_entries_depth_self_corrects_after_hydration() {
    // First: partial set with missing parent.
    let partial_posts = vec![topic_post(5, Some(3)), topic_post(6, Some(5))];
    let mut detail = TopicDetail {
        post_stream: TopicPostStream {
            posts: partial_posts,
            stream: vec![1, 2, 3, 4, 5, 6],
        },
        ..Default::default()
    };
    detail.rebuild_timeline_entries();
    assert_eq!(detail.timeline_entries[0].depth, 1); // fallback

    // Now hydrate: add post 3 (which replies to 1, also not loaded yet).
    detail.post_stream.posts.insert(0, topic_post(3, Some(1)));
    detail.rebuild_timeline_entries();

    let entry5 = detail
        .timeline_entries
        .iter()
        .find(|e| e.post_number == 5)
        .unwrap();
    // Post 5 → parent 3 (loaded, depth 1 because 3's parent 1 is not loaded) → depth 2.
    assert_eq!(entry5.depth, 2);
}

fn topic_post(post_number: u32, reply_to_post_number: Option<u32>) -> TopicPost {
    TopicPost {
        id: u64::from(post_number),
        username: format!("user-{post_number}"),
        name: None,
        avatar_template: None,
        author_metadata: Default::default(),
        cooked: format!("<p>{post_number}</p>"),
        raw: None,
        post_number,
        post_type: 1,
        created_at: None,
        updated_at: None,
        like_count: 0,
        reply_count: 0,
        reply_to_post_number,
        reply_to_user: None,
        bookmarked: false,
        bookmark_id: None,
        bookmark_name: None,
        bookmark_reminder_at: None,
        reactions: Vec::new(),
        current_user_reaction: None,
        boosts: Vec::new(),
        can_boost: false,
        polls: Vec::new(),
        accepted_answer: false,
        can_accept_answer: false,
        can_unaccept_answer: false,
        can_edit: false,
        can_delete: false,
        can_recover: false,
        hidden: false,
        presented: Default::default(),
    }
}
