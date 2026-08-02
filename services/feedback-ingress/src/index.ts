/**
 * Fire feedback ingress Worker.
 *
 * Accepts multipart feedback from the mobile apps and creates a GitHub Issue
 * using a server-side secret. Clients never hold GitHub credentials.
 */

export interface Env {
  GITHUB_TOKEN?: string;
  GITHUB_APP_ID?: string;
  GITHUB_APP_PRIVATE_KEY?: string;
  GITHUB_INSTALLATION_ID?: string;
  GITHUB_OWNER: string;
  GITHUB_REPO: string;
  MAX_TITLE_CHARS: string;
  MAX_BODY_CHARS: string;
  MAX_BUNDLE_BYTES: string;
  MAX_MEDIA_BYTES: string;
  MAX_MEDIA_FILES: string;
  RATE_LIMIT_PER_IP_PER_HOUR: string;
  /** Optional R2 bucket for attachment blobs. */
  ATTACHMENTS?: R2Bucket;
}

interface FeedbackFields {
  title: string;
  body: string;
  category?: string;
  severity?: string;
  platform?: string;
  app_version?: string;
  build_number?: string;
  username?: string;
  diagnostic_session_id?: string;
  bundle?: File;
  media: File[];
}

const ALLOWED_CATEGORIES = new Set([
  "bug",
  "crash",
  "performance",
  "ui",
  "suggestion",
  "other",
]);

const ALLOWED_SEVERITIES = new Set([
  "critical",
  "high",
  "medium",
  "low",
]);

/** In-memory rate limit (best-effort per isolate; use Durable Object / KV for production). */
const rateBuckets = new Map<string, { count: number; resetAt: number }>();

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "fire-feedback-ingress" });
    }

    if (request.method === "POST" && url.pathname === "/v1/feedback") {
      return handleFeedback(request, env);
    }

    return json({ ok: false, error: "not_found" }, 404);
  },
};

async function handleFeedback(request: Request, env: Env): Promise<Response> {
  const ip =
    request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for") ??
    "unknown";

  const limit = parsePositiveInt(env.RATE_LIMIT_PER_IP_PER_HOUR, 10);
  if (!allowRate(ip, limit)) {
    return json({ ok: false, error: "rate_limited" }, 429);
  }

  let fields: FeedbackFields;
  try {
    fields = await parseMultipart(request, env);
  } catch (error) {
    const message = error instanceof Error ? error.message : "invalid_payload";
    return json({ ok: false, error: message }, 400);
  }

  const token = await resolveGitHubToken(env);
  if (!token) {
    return json(
      {
        ok: false,
        error: "server_misconfigured",
        detail: "Missing GITHUB_TOKEN or GitHub App secrets",
      },
      500,
    );
  }

  const labels = buildLabels(fields);
  const issueBody = await buildIssueBody(fields, env);

  const createResponse = await fetch(
    `https://api.github.com/repos/${env.GITHUB_OWNER}/${env.GITHUB_REPO}/issues`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "User-Agent": "fire-feedback-ingress",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        title: fields.title,
        body: issueBody,
        labels,
      }),
    },
  );

  if (!createResponse.ok) {
    const detail = await createResponse.text();
    return json(
      {
        ok: false,
        error: "github_create_failed",
        status: createResponse.status,
        detail: detail.slice(0, 500),
      },
      502,
    );
  }

  const issue = (await createResponse.json()) as {
    number: number;
    html_url: string;
  };

  return json(
    {
      ok: true,
      issue_number: issue.number,
      issue_url: issue.html_url,
    },
    201,
  );
}

async function parseMultipart(request: Request, env: Env): Promise<FeedbackFields> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.includes("multipart/form-data")) {
    throw new Error("expected_multipart");
  }

  const form = await request.formData();
  const title = String(form.get("title") ?? "").trim();
  const body = String(form.get("body") ?? "").trim();
  const maxTitle = parsePositiveInt(env.MAX_TITLE_CHARS, 120);
  const maxBody = parsePositiveInt(env.MAX_BODY_CHARS, 8000);

  if (!title) throw new Error("title_required");
  if (!body) throw new Error("body_required");
  if (title.length > maxTitle) throw new Error("title_too_long");
  if (body.length > maxBody) throw new Error("body_too_long");

  const category = optionalString(form.get("category"));
  if (category && !ALLOWED_CATEGORIES.has(category)) {
    throw new Error("invalid_category");
  }
  const severity = optionalString(form.get("severity"));
  if (severity && !ALLOWED_SEVERITIES.has(severity)) {
    throw new Error("invalid_severity");
  }

  const bundleEntry = form.get("bundle");
  let bundle: File | undefined;
  if (bundleEntry instanceof File && bundleEntry.size > 0) {
    const maxBundle = parsePositiveInt(env.MAX_BUNDLE_BYTES, 2 * 1024 * 1024);
    if (bundleEntry.size > maxBundle) throw new Error("bundle_too_large");
    bundle = bundleEntry;
  }

  const maxMedia = parsePositiveInt(env.MAX_MEDIA_BYTES, 5 * 1024 * 1024);
  const maxMediaFiles = parsePositiveInt(env.MAX_MEDIA_FILES, 3);
  const media: File[] = [];
  for (const [key, value] of form.entries()) {
    if (key !== "media" && !key.startsWith("media[")) continue;
    if (!(value instanceof File) || value.size === 0) continue;
    if (value.size > maxMedia) throw new Error("media_too_large");
    media.push(value);
    if (media.length > maxMediaFiles) throw new Error("too_many_media");
  }

  return {
    title,
    body,
    category,
    severity,
    platform: optionalString(form.get("platform")),
    app_version: optionalString(form.get("app_version")),
    build_number: optionalString(form.get("build_number")),
    username: optionalString(form.get("username")),
    diagnostic_session_id: optionalString(form.get("diagnostic_session_id")),
    bundle,
    media,
  };
}

function buildLabels(fields: FeedbackFields): string[] {
  const labels = ["feedback", "beta"];
  if (fields.category) labels.push(`feedback:${fields.category}`);
  if (fields.severity) labels.push(`severity:${fields.severity}`);
  if (fields.platform === "ios" || fields.platform === "android") {
    labels.push(fields.platform);
  }
  return labels;
}

async function buildIssueBody(fields: FeedbackFields, env: Env): Promise<string> {
  const lines: string[] = [];
  lines.push("## User report");
  lines.push("");
  lines.push(fields.body);
  lines.push("");
  lines.push("## Environment");
  lines.push("");
  lines.push(`- Platform: ${fields.platform ?? "unknown"}`);
  lines.push(`- App version: ${fields.app_version ?? "unknown"}`);
  lines.push(`- Build: ${fields.build_number ?? "unknown"}`);
  lines.push(`- Category: ${fields.category ?? "unspecified"}`);
  lines.push(`- Severity: ${fields.severity ?? "unspecified"}`);
  lines.push(`- LinuxDo user: ${fields.username ?? "anonymous / not logged in"}`);
  lines.push(
    `- Diagnostic session: ${fields.diagnostic_session_id ?? "none"}`,
  );
  lines.push("");
  lines.push("_Submitted via Fire in-app feedback (bot account)._");

  const attachmentNotes: string[] = [];

  if (fields.bundle) {
    const note = await storeAttachment(env, fields.bundle, "bundle");
    attachmentNotes.push(note);
  }
  for (const [index, file] of fields.media.entries()) {
    const note = await storeAttachment(env, file, `media-${index + 1}`);
    attachmentNotes.push(note);
  }

  if (attachmentNotes.length > 0) {
    lines.push("");
    lines.push("## Attachments");
    lines.push("");
    for (const note of attachmentNotes) {
      lines.push(`- ${note}`);
    }
  }

  return lines.join("\n");
}

async function storeAttachment(
  env: Env,
  file: File,
  kind: string,
): Promise<string> {
  const safeName = sanitizeFileName(file.name || kind);
  if (!env.ATTACHMENTS) {
    // Without R2, record metadata only. Wire R2 for real blob retention.
    return `${kind}: \`${safeName}\` (${file.size} bytes) — storage not configured`;
  }

  const key = `feedback/${Date.now()}-${crypto.randomUUID()}-${safeName}`;
  await env.ATTACHMENTS.put(key, await file.arrayBuffer(), {
    httpMetadata: {
      contentType: file.type || "application/octet-stream",
    },
  });
  return `${kind}: \`${key}\` (${file.size} bytes)`;
}

async function resolveGitHubToken(env: Env): Promise<string | null> {
  if (env.GITHUB_TOKEN) {
    return env.GITHUB_TOKEN;
  }

  // GitHub App installation token path can be added later.
  // For TF bootstrap, a fine-grained PAT in GITHUB_TOKEN is enough.
  if (
    env.GITHUB_APP_ID &&
    env.GITHUB_APP_PRIVATE_KEY &&
    env.GITHUB_INSTALLATION_ID
  ) {
    return null; // TODO: mint installation token via JWT
  }

  return null;
}

function allowRate(ip: string, limitPerHour: number): boolean {
  const now = Date.now();
  const hourMs = 60 * 60 * 1000;
  const bucket = rateBuckets.get(ip);
  if (!bucket || now >= bucket.resetAt) {
    rateBuckets.set(ip, { count: 1, resetAt: now + hourMs });
    return true;
  }
  if (bucket.count >= limitPerHour) {
    return false;
  }
  bucket.count += 1;
  return true;
}

function optionalString(value: FormDataEntryValue | null): string | undefined {
  if (value == null) return undefined;
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function parsePositiveInt(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function sanitizeFileName(name: string): string {
  return name.replace(/[^a-zA-Z0-9._-]+/g, "_").slice(0, 120);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}
