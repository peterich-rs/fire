use fire_models::TopicSummary;

use crate::parsing::decode_html_entities;

pub fn plain_text_from_html(raw_html: &str) -> String {
    if raw_html.trim().is_empty() {
        return String::new();
    }

    let normalized = raw_html
        .replace("<br>", "\n")
        .replace("<br/>", "\n")
        .replace("<br />", "\n")
        .replace("</p>", "\n\n")
        .replace("</li>", "\n");
    let stripped = strip_html_tags(&normalized);
    normalize_whitespace(&decode_html_entities(&stripped))
}

pub fn preview_text_from_html(raw_html: Option<&str>) -> Option<String> {
    let html = raw_html?.trim();
    if html.is_empty() {
        return None;
    }

    let compact = normalize_whitespace(&plain_text_from_html(html).replace('\n', " "));
    if compact.is_empty() {
        None
    } else {
        Some(compact)
    }
}

pub fn monogram_for_username(username: &str) -> String {
    let letters: Vec<String> = username
        .split(|character: char| !character.is_alphanumeric())
        .filter_map(|component| component.chars().next())
        .take(2)
        .map(|character| character.to_uppercase().collect::<String>())
        .collect();
    if !letters.is_empty() {
        return letters.join("");
    }

    username
        .chars()
        .next()
        .map(|character| character.to_uppercase().collect::<String>())
        .unwrap_or_default()
}

pub fn topic_status_labels(topic: &TopicSummary) -> Vec<String> {
    let mut labels = Vec::new();
    if topic.pinned {
        labels.push("Pinned".to_string());
    }
    if topic.closed {
        labels.push("Closed".to_string());
    }
    if topic.archived {
        labels.push("Archived".to_string());
    }
    if topic.has_accepted_answer {
        labels.push("Solved".to_string());
    }
    if topic.unread_posts > 0 {
        labels.push(format!("Unread {}", topic.unread_posts));
    }
    if topic.new_posts > 0 {
        labels.push(format!("New {}", topic.new_posts));
    }
    labels
}

fn strip_html_tags(input: &str) -> String {
    let mut stripped = String::with_capacity(input.len());
    let mut inside_tag = false;

    for character in input.chars() {
        match character {
            '<' => inside_tag = true,
            '>' => {
                inside_tag = false;
                stripped.push(' ');
            }
            _ if !inside_tag => stripped.push(character),
            _ => {}
        }
    }

    stripped
}

fn normalize_whitespace(value: &str) -> String {
    let normalized = value.replace("\r\n", "\n");
    let mut result = String::with_capacity(normalized.len());
    let mut previous_was_space = false;
    let mut newline_run = 0_u8;

    for character in normalized.chars() {
        match character {
            '\n' => {
                newline_run = newline_run.saturating_add(1);
                previous_was_space = false;
                if newline_run <= 2 {
                    result.push('\n');
                }
            }
            ' ' | '\t' => {
                newline_run = 0;
                if !previous_was_space {
                    result.push(' ');
                    previous_was_space = true;
                }
            }
            _ => {
                newline_run = 0;
                previous_was_space = false;
                result.push(character);
            }
        }
    }

    result.trim().to_string()
}

#[cfg(test)]
mod tests {
    use fire_models::TopicSummary;

    use super::{
        monogram_for_username, plain_text_from_html, preview_text_from_html, topic_status_labels,
    };

    #[test]
    fn plain_text_from_html_normalizes_basic_markup() {
        assert_eq!(
            plain_text_from_html("<p>Hello<br>Fire</p><ul><li>Rust</li><li>CI</li></ul>"),
            "Hello\nFire\n\n Rust\n CI"
        );
    }

    #[test]
    fn preview_text_from_html_collapses_to_single_line() {
        assert_eq!(
            preview_text_from_html(Some("<p>Hello&nbsp;<strong>Fire</strong></p>")),
            Some("Hello Fire".to_string())
        );
    }

    #[test]
    fn monogram_for_username_prefers_two_components() {
        assert_eq!(monogram_for_username("fire native"), "FN");
        assert_eq!(monogram_for_username("rustacean"), "R");
    }

    #[test]
    fn topic_status_labels_include_flags_and_counters() {
        let topic = TopicSummary {
            pinned: true,
            archived: true,
            has_accepted_answer: true,
            unread_posts: 2,
            new_posts: 1,
            ..TopicSummary::default()
        };

        assert_eq!(
            topic_status_labels(&topic),
            vec![
                "Pinned".to_string(),
                "Archived".to_string(),
                "Solved".to_string(),
                "Unread 2".to_string(),
                "New 1".to_string(),
            ]
        );
    }
}
