# Public URLs for Store / TestFlight

Fire does not currently host a separate marketing site. For **public / external
TestFlight** and App Store Connect fields that require HTTPS links, use the
public GitHub `main` branch files below.

Repository: https://github.com/peterich-rs/fire  
Visibility: public (links work without GitHub login)

## Canonical links (paste into App Store Connect)

| Field | URL |
| --- | --- |
| **Privacy Policy** (preferred, rendered Markdown) | https://github.com/peterich-rs/fire/blob/main/docs/release/privacy-policy.md |
| Privacy Policy (plain-text mirror) | https://raw.githubusercontent.com/peterich-rs/fire/main/docs/release/privacy-policy.md |
| App Privacy questionnaire draft (internal reference) | https://github.com/peterich-rs/fire/blob/main/docs/release/app-store-data-collection.md |
| App Store listing draft (internal reference) | https://github.com/peterich-rs/fire/blob/main/docs/release/app-store-description.md |
| Support / contact | https://github.com/peterich-rs/fire/issues |
| TestFlight setup guide | https://github.com/peterich-rs/fire/blob/main/docs/release/testflight-setup.md |

## App Store Connect mapping

1. **App Privacy → Privacy Policy URL**  
   Use the **Privacy Policy** preferred link.

2. **TestFlight → External Testing → Privacy Policy URL**  
   Same Privacy Policy preferred link (required before external / public link).

3. **App Information → Support URL** (when asked)  
   Use https://github.com/peterich-rs/fire/issues  
   or the repository root https://github.com/peterich-rs/fire

4. **Marketing URL** (optional)  
   https://github.com/peterich-rs/fire

## Notes

- Prefer the `blob/main/...` rendered page for reviewers and testers; keep the
  `raw.githubusercontent.com` link as a fallback if a form rejects GitHub UI
  pages.
- These URLs track **`main`**. Merge privacy edits to `main` before submitting
  Beta App Review so reviewers see the published text.
- GitHub hosting is acceptable for TestFlight external testing when the repo is
  public. A dedicated website can replace these URLs later without changing app
  binaries—only App Store Connect metadata.
