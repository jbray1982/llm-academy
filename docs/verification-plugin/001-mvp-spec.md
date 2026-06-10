# Spec 001 — Verification Plugin Framework + Judge Migration

## Goal

Implement the verifier plugin framework for the orchestration harness, with the existing LLM judge migrated as the first plugin. This is a behavior-preserving refactor: the plugin contract is defined and validated against a mechanism that already works. The MVP demonstrates that:

1. `verify.sh` dispatches verify-block keys to `lib/plugins/<key>.sh` scripts with no per-plugin knowledge
2. The judge, running as a plugin, produces the same pass/fail outcomes as the inline implementation it replaces
3. The verdict schema namespaces per-plugin results so a future plugin (TVR, spec 002) requires zero changes to `verify.sh` or the schema

## In Scope

- `harness/lib/plugins/judge.sh` — the LLM judge, migrated from inline `verify.sh` code
- `harness/lib/verify.sh` — rewritten around plugin dispatch: run checks, dispatch every other verify-block key to its plugin, merge verdicts
- `harness/lib/executor.sh` — write the full `verify:` block into the stage record (today it forwards only `checks` and `judge`)
- `harness/lib/config.sh` — surface the whole stage `verify:` block as JSON; preflight plugin keys at `config_load`
- Verdict JSON schema — namespaced `plugins` object, `warnings` field, multi-source `failure_reason`
- Bug fix: `verify.sh` reads the judge envelope from undefined `$judge_result_file` (should be `$_verify_result_file`) — every judge invocation currently fails; the migration rewrites this path and must leave it working

## Out of Scope (for this spec)

- TVR, embeddings, `lib/embed*` — spec 002
- Any new verifier plugin beyond the judge
- Migrating `checks` into the plugin framework — stays a built-in
- Plugin versioning, registry manifest, or discovery beyond `lib/plugins/<key>.sh`
- Changes to retry/recover flow in `executor.sh`

## Data Model

**Plugin contract.** A plugin is a bash script at `harness/lib/plugins/<name>.sh`, invoked as:

```bash
lib/plugins/<name>.sh  stage_record_dir  run_dir  item  co_author
```

- stdout: a verdict JSON object — `{"passed": true|false, ...}` plus any plugin-specific fields. stdout is the ONLY channel verify.sh parses; diagnostics go to stderr.
- `stage_record_dir/<name>`: the plugin's own config — the JSON value of its key in the stage's `verify:` block.
- `stage_record_dir/backend`: the stage backend name, for plugins that make LLM calls.
- Plugins may source harness libs (`prompt.sh`, `backend.sh`, `result.sh`) via `$HARNESS_DIR` resolved from their own script path.
- Exit code is ignored when stdout parses as valid verdict JSON; non-zero exit with unparseable stdout is treated as `passed: false` (see Behaviors 5).

**Judge plugin config** (unchanged YAML — already plugin-shaped):

```yaml
verify:
  judge:
    prompt: prompts/judge-review.md
    schema: schemas/judge.json
```

**Verdict JSON** (emitted by `verify_stage`; per-plugin results are namespaced — no plugin owns top-level fields):

```json
{
  "passed": true,
  "checks": [{"command": "...", "exit_code": 0}],
  "plugins": {
    "judge": { "passed": true, "verdict": "pass", "reason": "..." }
  },
  "warnings": [],
  "failure_reason": ""
}
```

The legacy top-level `judge_verdict` / `judge_reason` fields are removed. Nothing machine-reads them: `executor.sh` extracts only `passed` and `failure_reason`; telemetry stores the verdict as an opaque blob.

## Behaviors

1. **Verify-block plumbing** — `config.sh` gains access to the full stage `verify:` block as a JSON object (e.g. `config_stage_field i verify`). `executor.sh` writes that JSON to `stage_record_dir/verify` alongside the existing fields. The special-cased `verify_checks` / `verify_judge` accessors may remain for compatibility but verify.sh no longer depends on them.

2. **Plugin dispatch** — `verify_stage` reads `stage_record_dir/verify` and iterates its keys. `checks` is the one reserved key, handled by the existing built-in check runner. For every other key `<k>`, verify.sh writes the key's JSON value to `stage_record_dir/<k>` and invokes `lib/plugins/<k>.sh` with `(stage_record_dir, run_dir, item, co_author)`, capturing stdout as that plugin's verdict.

3. **Preflight** — `config_load` validates that every non-`checks` key in every stage's `verify:` block resolves to an existing `lib/plugins/<key>.sh` (config-dir override first, harness install fallback — same two-tier resolution as prompts/schemas). A key with no plugin is a load-time error with a clear message, never a silently skipped verification. `config_load` also preflights `jq` (currently unchecked anywhere; verify.sh and result.sh depend on it).

4. **Verdict composition** — overall `passed` = all checks exit 0 AND every dispatched plugin reports `passed: true`. Each plugin's parsed verdict object is stored under `plugins.<name>`. When multiple sources fail, `failure_reason` concatenates each source's reason, `"; "`-separated, prefixed with the source name (e.g. `checks: 1 of 3 failed; judge: <reason>`).

5. **Never silently pass** — a plugin that exits non-zero without parseable stdout, emits unparseable JSON, or emits JSON without a boolean `passed` field is recorded as `plugins.<name>: {"passed": false, "reason": "plugin did not return a valid verdict"}` and fails the stage. This generalizes the existing judge rule ("a judge that cannot return a structured verdict is a verify failure").

6. **Judge migration** — `lib/plugins/judge.sh` carries over the current inline logic intact: resolve prompt/schema paths (config-dir override, then harness `prompts/`/`schemas/` fallback), `prompt_assemble`, `backend_invoke` with the stage backend, `result_normalize` + `result_extract_field` for `verdict`/`reason`, non-`pass`/`fail` verdict treated as failure. It emits `{"passed": ..., "verdict": ..., "reason": ...}`. The `$judge_result_file` bug must not survive the migration.

7. **Warnings channel** — advisory conditions go in the `warnings` array, never `failure_reason`. `failure_reason` is non-empty if and only if `passed` is false. (Spec 002's "no acceptance criteria found" advisory uses this.)

8. **Behavioral equivalence** — for a stage configured with `verify: checks: [...]` and/or `verify: judge: {...}`, the post-migration `passed` outcome matches the pre-migration logic for every combination of check results and judge verdicts (taking the `$judge_result_file` fix as the intended pre-migration behavior).

## Integration Points

| Component | Change |
|---|---|
| `harness/lib/verify.sh` | Rewritten: checks built-in + plugin dispatch + verdict merge; inline judge code removed |
| `harness/lib/plugins/judge.sh` | New — receives the migrated judge logic |
| `harness/lib/executor.sh` | Writes full `verify:` block JSON into the stage record |
| `harness/lib/config.sh` | Surfaces the whole `verify:` block; preflights plugin keys and `jq` at load |
| `harness/config/default.yaml` | No changes — existing `verify:` blocks are already plugin-shaped |
| `install.sh` | No changes — `harness/` is linked/copied wholesale, so `lib/plugins/` propagates |

## Extension Hooks

- `lib/plugins/` — new plugins are self-registering via filesystem discovery; zero verify.sh changes required. Spec 002 (TVR) is the first consumer of this hook and the proof it holds.
- Consuming repos can override a plugin by placing `lib/plugins/<key>.sh` relative to their config dir (same override model as prompts/schemas).

## Acceptance Criteria

- [ ] `lib/plugins/judge.sh` exists and contains the judge logic; `verify.sh` contains no judge-specific code
- [ ] A stage with `verify: judge: {...}` in existing config syntax dispatches through the plugin framework with no YAML changes
- [ ] The judge plugin produces correct verdicts end-to-end (which also confirms the `$judge_result_file` bug is fixed — the judge path works at all)
- [ ] Verdict JSON namespaces plugin results under `plugins.<name>`; no plugin-specific top-level fields
- [ ] A plugin that crashes or emits invalid JSON fails the stage with a named reason — never a silent pass
- [ ] A verify-block key with no matching `lib/plugins/<key>.sh` fails at `config_load` with a clear message
- [ ] `config_load` errors informatively when `jq` is not installed
- [ ] When checks and a plugin both fail, `failure_reason` names both sources
- [ ] A do-nothing test plugin dropped in `lib/plugins/` and declared in a stage's verify block is dispatched with no `verify.sh` edit
- [ ] End-to-end: a harness run of the default feature-flow pipeline on a real issue passes/fails the review stage identically to the pre-migration behavior
