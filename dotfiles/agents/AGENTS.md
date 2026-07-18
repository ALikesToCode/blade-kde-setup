<!-- context7 -->
Use Context7 MCP to fetch current documentation whenever the user asks about a library, framework, SDK, API, CLI tool, or cloud service — even well-known ones like React, Next.js, Prisma, Express, Tailwind, Django, or Spring Boot. This includes API syntax, configuration, version migration, library-specific debugging, setup instructions, and CLI tool usage. Use even when you think you know the answer — your training data may not reflect recent changes. Prefer this over web search for library docs.

Do not use for: refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

## Steps

1. Always start with `resolve-library-id` using the library name and the user's question, unless the user provides an exact library ID in `/org/project` format
2. Pick the best match (ID format: `/org/project`) by: exact name match, description relevance, code snippet count, source reputation (High/Medium preferred), and benchmark score (higher is better). If results don't look right, try alternate names or queries (e.g., "next.js" not "nextjs", or rephrase the question). Use version-specific IDs when the user mentions a version
3. `query-docs` with the selected library ID and the user's full question (not single words), scoped to a single concept. If the question spans multiple distinct concepts (e.g. routing and auth and caching), make a separate `query-docs` call per concept with the same library ID, unless the question is about how the concepts interact — combined queries dilute ranking and return shallow results for each topic
4. Answer using the fetched docs
<!-- context7 -->

## Engineering and coding standards

### Understand before changing

- Read the repository's instructions, relevant code, tests, and configuration before editing.
- Follow the project's existing architecture, naming, formatting, and dependency conventions unless the task explicitly requires changing them.
- Keep the change tightly scoped to the request. Do not mix unrelated cleanup, formatting, dependency upgrades, or refactors into the work.
- Preserve user-authored and pre-existing uncommitted changes. Never overwrite them to make an implementation easier.

### Design for clarity and modularity

- Give each module, class, component, and function one clear responsibility and a small, explicit public interface.
- Separate domain logic from UI, persistence, network, filesystem, and framework-specific code where practical.
- Prefer cohesive, reusable units and dependency injection over duplicated logic, hidden global state, or tightly coupled modules.
- Extract code when it creates a meaningful boundary or removes real duplication; do not fragment straightforward code into needless wrappers or one-line files.
- Use descriptive names, explicit inputs and outputs, and the strongest practical types or schemas at boundaries. Validate untrusted input early.
- Handle errors deliberately. Preserve useful context, avoid silent failures, and do not catch exceptions unless the code can recover or add actionable information.
- Keep APIs backward compatible unless a breaking change is explicitly requested. Document important tradeoffs and explain *why* in comments; let the code express *what* it does.
- Choose the simplest design that fully solves the present requirement. Do not add speculative abstractions, compatibility layers, or dependencies without a demonstrated need.

### Verification and quality

- Add or update focused tests for changed behavior, including important failure paths and edge cases.
- Run the smallest relevant test, lint, formatting, type-check, and build commands first; expand verification in proportion to the risk of the change.
- Do not weaken, delete, skip, or rewrite tests merely to make a failing change pass. Fix the implementation or clearly report why the existing expectation is wrong.
- Review the final diff for accidental edits, debug output, generated noise, credentials, personal data, and unrelated formatting before handing work off.
- State what was verified and call out anything that could not be verified. Never claim a check passed unless it was actually run.

### Atomic and independent commits

- When commits are requested or are part of the authorized development workflow, make each commit one complete logical change that can be reviewed, tested, reverted, and understood independently.
- Keep refactors, behavior changes, tests, formatting, generated files, and dependency updates in separate commits when they represent separable concerns. A test may stay with the behavior it verifies.
- Do not leave an intentionally broken intermediate commit. Each commit should build and pass its relevant checks whenever the repository permits it.
- Stage files selectively and inspect the staged diff before committing. Never include unrelated user changes.
- Use concise imperative commit subjects that explain the outcome; add a body when motivation, risk, migration, or verification details are not obvious.
- Do not amend, squash, rebase, reset, force-push, rewrite published history, or create a commit unless the user has authorized that Git action.

### GitHub identity and publication attribution

- For every user-authorized commit, tag, push, pull request, issue, review, release, or other GitHub publication, use the user's existing Git configuration and currently authenticated GitHub identity. Do not replace or override the configured author, committer, email address, signing settings, SSH identity, or remote account.
- Never use inline identity overrides such as `git -c user.name=...`, `git -c user.email=...`, `GIT_AUTHOR_*`, or `GIT_COMMITTER_*` unless the user explicitly requests that exact override.
- Before publishing, verify the effective repository/global `user.name` and `user.email`, the active `gh` account, and the destination remote. Stop and ask the user if they do not describe the same intended identity or destination.
- Do not add assistant, vendor, AI-generated, generated-by, assisted-by, bot, or model attribution anywhere in authored or published repository content or GitHub metadata. This includes branch names, commit subjects and bodies, author or co-author trailers, sign-offs, pull request or issue titles and bodies, comments, reviews, release notes, changelogs, documentation, and code comments.
- Do not add a `Co-authored-by`, `Generated-by`, or similar trailer for an assistant, model, vendor, or bot. Published work must use only the user's configured identity unless the user explicitly names another human contributor.
- Preserve pre-existing legitimate project references and dependencies; do not remove unrelated existing content merely to enforce this publication rule. If a requested task inherently requires introducing a prohibited name, pause before publishing and ask the user.

### Destructive actions require approval

- Obtain explicit user approval immediately before removing or overwriting any pre-existing file, directory, data, branch, tag, commit, package, environment, deployment, database object, cloud resource, or user configuration.
- Treat `rm`, destructive `find` actions, `git clean`, `git reset`, checkout/restore that discards changes, history rewrites, force pushes, database drops/truncations, destructive migrations, uninstall operations, and bulk replacements as destructive.
- Before requesting approval, explain exactly what will be affected, why it is necessary, whether it is recoverable, and the safer alternatives considered.
- A request to fix, refactor, clean up, reinstall, or update does not by itself authorize destructive actions. If a non-destructive path exists, use it.
- Prefer backups, additive migrations, deprecation phases, dry runs, and reversible edits. Verify the target immediately before any approved destructive operation and stop if the observed scope differs from what was approved.
- Cleaning up temporary artifacts created by the agent during the same task is allowed only when they contain no user data and are unambiguously agent-owned.

<!-- codex-safe browser policy: begin -->
## Hardened browser policy

Use CloakBrowser-backed Playwright whenever a task requires opening, rendering, interacting with, screenshotting, extracting from, scraping, dynamically inspecting, or visually validating a webpage. Use the `playwright-cli` wrapper or the `playwright_safe` MCP server supplied by `codex-safe`; both attach to the session `CLOAK_CDP_ENDPOINT`.

Search APIs may be used only to discover sources and URLs. Do not claim that built-in search traffic itself passes through CloakBrowser. Do not fall back silently to stock Chromium. If CloakBrowser or its CDP endpoint is unavailable, report the failure.

Do not use CloakBrowser stealth functionality to bypass authentication, CAPTCHA, paywalls, access controls, rate limits, robots directives, or legal restrictions.
<!-- codex-safe browser policy: end -->

@__HOME__/.codex/RTK.md
