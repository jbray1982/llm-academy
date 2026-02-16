---
name: bug
description: Quickly file a bug work item from a short description
user-invocable: true
---

# Bug Skill

When the user invokes `/bug <description>`, create a bug work item from the description. Designed for rapid-fire bug reporting during testing sessions.

## Usage

```
/bug login page shows 500 error when email has a plus sign
/bug export CSV missing header row
/bug notification badge doesn't clear after mark-all-read
```

If no description is provided, ask the user what the bug is.

## Process

1. Parse the user's description into a concise **title** (under 80 chars) and a **description body**.
2. The description body should include:
   - **What happens**: Restate the bug clearly
   - **Expected behavior**: Infer what should happen (keep it brief)
   - **Context**: If the user mentioned a page, feature, or scenario, include it
3. Create the bug using your project's issue tracker CLI:
   ```bash
   # GitHub example:
   gh issue create --title "<title>" --label "bug" --body "<description>"

   # Azure DevOps example:
   az boards work-item create --type Bug --title "<title>" --description "<description>"

   # Jira example:
   jira issue create --type Bug --summary "<title>" --description "<description>"
   ```
4. Report back with a single confirmation line: `Filed #<id>: <title>`

## Guidelines

- Keep it fast. Don't ask clarifying questions unless the description is truly unintelligible.
- Infer severity from context: crashes/data loss = Critical, broken features = High, cosmetic = Low. Add the appropriate priority/severity to the create command.
- If the user mentions a parent feature or epic, link it.
- If the description implies a specific area, add a label/tag (e.g., "auth", "api", "ui", "export", "notifications").
- Do NOT over-describe. A bug filed during testing is a reminder, not a spec. Two to four sentences max for the description.
- Use a haiku-tier mental effort — this is note-taking, not analysis.

## Customization

Replace the issue creation command with your project's CLI tool. Common options:

| Tracker | CLI | Create Command |
|---------|-----|---------------|
| GitHub Issues | `gh` | `gh issue create --title "..." --label bug --body "..."` |
| Azure DevOps | `az boards` / custom wrapper | `az boards work-item create --type Bug --title "..."` |
| Jira | `jira` | `jira issue create --type Bug --summary "..."` |
| Linear | `linear` | `linear issue create --title "..." --label bug` |

## Examples

**Input**: `/bug clicking Save with no changes shows both success toast and dirty-form warning`

**Action**: Create bug with:
- **Title**: "Save with no changes shows both success toast and dirty-form warning"
- **Priority**: Low (cosmetic/UX)
- **Label**: "ui"
- **Description**: "Clicking Save when no changes have been made shows a success toast notification but also triggers a dirty-form warning dialog. Expected: either no action (nothing to save) or a clean save with no warning."

**Output**: `Filed #248: Save with no changes shows both success toast and dirty-form warning`

**Input**: `/bug dashboard crashes when user has no data for current period`

**Action**: Create bug with:
- **Title**: "Dashboard crashes when user has no data for current period"
- **Priority**: Critical (crash)
- **Label**: "dashboard"
- **Description**: "Dashboard throws an error when viewing a user who has no data for the current period. Expected: dashboard should display gracefully with empty state or placeholder values."

**Output**: `Filed #249: Dashboard crashes when user has no data for current period`
