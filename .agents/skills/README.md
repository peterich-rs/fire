# Project skills

Grok loads these from `.agents/skills/` (repo scope).

| Skill | Use when |
| --- | --- |
| `rust-quality-coding` | 写或审查 Rust 时先做设计判断：所有权、领域类型、trait 拆分、错误与 async 边界 |

`rust-quality-coding` 从 `../im/.agents/skills/rust-quality-coding` 复用。写公共 API、模块边界或后续 `RenderDocumentHandle` 这类所有权变化时先读它。
