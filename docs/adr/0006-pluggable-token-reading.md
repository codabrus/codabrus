# ADR-0006: Pluggable API Token Reading

**Status:** Accepted  
**Date:** 2026-04-11

## Context

Codabrus communicates with LLM providers (DeepSeek, OpenAI, Anthropic, …) using API tokens. These tokens need to be:

- Stored securely, outside version-controlled project directories
- Available for multiple providers without duplicating lookup logic
- Readable from different sources depending on platform and user preference (file, env var, OS keychain, secrets manager)
- Customizable without modifying Codabrus source code

Storing tokens in environment variables is common but has drawbacks:

- Inherited by child processes — including the `bash` tool, which means any shell command the AI generates has access to the token
- Visible in `/proc/<pid>/environ` on Linux to same-user processes
- Frequently leak into CI logs and crash dumps
- Encourage storing in project `.env` files that get accidentally committed

## Decision

**Primary storage:** `~/.config/codabrus/secrets.json` — an XDG-compliant file outside any project directory:

```json
{
  "deepseek": "sk-...",
  "openai": "sk-...",
  "anthropic": "sk-..."
}
```

The key is the provider name (lowercase string); the value is the token. The file should be `chmod 600`.

**Pluggable reading mechanism:** A global variable `codabrus/vars:*token-readers*` holds an ordered list of functions. Each function has the signature:

```
(provider-name : string) → (or string null)
```

They are tried in order; the first non-nil result is used. This is the single extension point for platform-specific or organization-specific token sources.

**Default reader list** (in priority order):

| Order | Reader | Source |
|-------|--------|--------|
| 1 | `secrets-json-reader` | `~/.config/codabrus/secrets.json` |
| 2 | `env-var-reader` | Env var: `<PROVIDER-UPCASE>_API_TOKEN` |

Users extend or replace the list from `~/.codabrus/config.lisp` or `.local-config.lisp`, which are loaded before token lookup:

```lisp
;; Prepend a macOS Keychain reader
(push (lambda (provider)
        (uiop:run-program
         (list "security" "find-generic-password"
               "-a" (uiop:getenv "USER")
               "-s" (format nil "codabrus-~A" provider) "-w")
         :output :string :ignore-error-status t))
      codabrus/vars:*token-readers*)
```

If no reader returns a token, startup signals an error with a message that lists both configuration options.

## Consequences

**Good:**
- Tokens live outside project directories by default — no accidental `git add .` commits
- A single file serves all providers; adding a new provider requires no code change
- Platform-specific readers (Keychain, 1Password CLI, HashiCorp Vault) can be prepended without patching Codabrus
- Environment variables remain a valid fallback, useful in CI/CD where secrets are injected via the runner

**Neutral:**
- Adds `yason` as an explicit dependency for JSON parsing
- Users must create `~/.config/codabrus/secrets.json` manually; the error message guides them

**Risk:**
- `secrets.json` is plaintext on disk; permissions depend on the user setting `chmod 600`
- Mitigation (future): warn at startup if the file's permissions are broader than `600`
