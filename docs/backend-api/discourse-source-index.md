# Discourse Source Index

This file records the upstream Discourse API/source references used by Fire when backend behavior is not Linux.do-specific. Prefer these references over reverse-engineering Linux.do frontend JavaScript; use Linux.do traffic only to confirm site plugins, Cloudflare behavior, and deployment-specific payload drift.

## Topic Detail And Posts

- `GET /t/{topicId}.json`, `GET /t/{topicId}/{postNumber}.json`, `GET /t/{slug}/{topicId}.json`
  - Upstream route: `topics#show`
  - Fire usage: topic header, original post, root reply stream, read tracking, private-message metadata.
  - Source: <https://github.com/discourse/discourse/blob/main/config/routes.rb>, <https://github.com/discourse/discourse/blob/main/app/controllers/topics_controller.rb>

- `GET /t/{topicId}/posts.json?post_ids[]=...`
  - Upstream route: `topics#posts`
  - Fire usage: batch hydrate specific post IDs for topic detail pages, reply context, and row-budgeted root branch pagination.
  - Source: <https://github.com/discourse/discourse/blob/main/config/routes.rb>, <https://github.com/discourse/discourse/blob/main/app/controllers/topics_controller.rb>

- `GET /posts/by_number/{topicId}/{postNumber}.json`
  - Upstream route: `posts#by_number`
  - Fire usage: fetch missing original post, resolve target post root ancestry, recover anchor posts when filtered topic payloads omit them.
  - Source: <https://github.com/discourse/discourse/blob/main/config/routes.rb>, <https://github.com/discourse/discourse/blob/main/app/controllers/posts_controller.rb>

- `GET /posts/{postId}/reply-ids.json`
  - Upstream route: `posts#reply_ids`
  - Fire usage: fetch a root reply branch's descendant ID list before bounded post hydration.
  - Source: <https://github.com/discourse/discourse/blob/main/config/routes.rb>, <https://github.com/discourse/discourse/blob/main/app/controllers/posts_controller.rb>

- `GET /posts/{postId}/cooked.json` and `GET /posts/{postId}/raw`
  - Upstream routes: `posts#cooked`, `posts#markdown_id`
  - Fire usage: `cooked` remains the display source; `raw` is for editing, quote/preview workflows, and offline fallback.
  - Source: <https://github.com/discourse/discourse/blob/main/config/routes.rb>, <https://github.com/discourse/discourse/blob/main/app/controllers/posts_controller.rb>

## Uploads And Rich Content

- `POST /uploads/lookup-urls`
  - Upstream route: `uploads#lookup_urls`
  - Fire usage: resolve short upload URLs found in cooked HTML to canonical upload URLs.
  - Source: <https://github.com/discourse/discourse/blob/main/config/routes.rb>, <https://github.com/discourse/discourse/blob/main/app/controllers/uploads_controller.rb>

- `POST /uploads/lookup-metadata`
  - Upstream route: `uploads#metadata`
  - Fire usage: recover upload width, height, filename, and size metadata when cooked image tags do not carry enough layout information.
  - Source: <https://github.com/discourse/discourse/blob/main/config/routes.rb>, <https://github.com/discourse/discourse/blob/main/app/controllers/uploads_controller.rb>

## Policy

- Fire documentation should cite the upstream controller/route when adding or changing a Discourse-compatible API path.
- Linux.do-specific observations belong in the relevant endpoint notes only after confirming they differ from upstream Discourse behavior.
- `references/fluxdo/` remains a read-only behavior reference for Linux.do client conventions; it is not the protocol authority.
