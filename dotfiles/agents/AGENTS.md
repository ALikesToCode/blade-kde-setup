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

### Skill and configuration access

- Files and directories under `~/.agents` and `~/.codex` are explicitly in scope for read-only access whenever they are needed for skills, instructions, configuration, documentation, diagnostics, or task context.
- Listing, searching, traversing, and reading those paths does not require destructive-action approval. Do not interpret the filesystem safety rules as a prohibition on reading them, and do not claim they are inaccessible unless a tool returns a concrete access error.
- Follow referenced skill and instruction files directly from those locations. If a particular tool is sandboxed, use another available read-only mechanism or report the exact failing operation rather than treating the whole directory as forbidden.
- This read authorization does not authorize deletion. Deleting, moving, replacing, or otherwise destructively changing anything under `~/.agents` or `~/.codex` still requires explicit user approval immediately before the action; ordinary edits remain subject to the task scope and the destructive-action rules below.

### Design for clarity and modularity

- Give each module, class, component, and function one clear responsibility and a small, explicit public interface.
- Separate domain logic from UI, persistence, network, filesystem, and framework-specific code where practical.
- Prefer cohesive, reusable units and dependency injection over duplicated logic, hidden global state, or tightly coupled modules.
- Extract code when it creates a meaningful boundary or removes real duplication; do not fragment straightforward code into needless wrappers or one-line files.
- Use descriptive names, explicit inputs and outputs, and the strongest practical types or schemas at boundaries. Validate untrusted input early.
- Handle errors deliberately. Preserve useful context, avoid silent failures, and do not catch exceptions unless the code can recover or add actionable information.
- Keep APIs backward compatible unless a breaking change is explicitly requested. Document important tradeoffs and explain *why* in comments; let the code express *what* it does.
- Choose the simplest design that fully solves the present requirement. Do not add speculative abstractions, compatibility layers, or dependencies without a demonstrated need.

### Maintainable module and file boundaries

- Design module boundaries before implementing work that spans multiple responsibilities. Keep orchestration separate from domain rules, UI rendering, persistence, filesystem access, and external integrations.
- Do not create or further expand a hand-written source file beyond 1,000 lines. Treat approximately 500 lines as a strong refactoring signal—not a target—and split earlier whenever distinct responsibilities or independent reasons to change appear.
- When a requested change touches an existing hand-written file over 1,000 lines, first look for a safe, task-relevant extraction into cohesive modules. Do not turn a scoped task into a risky whole-file rewrite; if extraction is not safe within scope, make the minimum correct change and report the remaining oversized file with a concrete split recommendation.
- Treat functions longer than roughly 60 lines, nesting deeper than three levels, classes or components coordinating unrelated behavior, and repeated multi-step blocks as review signals. Prefer named helpers, early returns, composition, and explicit collaborators.
- Split along behavior and ownership boundaries: UI components from state and data access; transport handlers from application and domain logic; persistence behind repositories or adapters; CLI parsing from orchestration and provider integrations.
- Keep dependencies directional and interfaces small. Avoid circular imports, cross-module hidden state, catch-all managers, and generic `utils` dumping grounds.
- Do not game size limits with trivial pass-through files, one-line wrappers, arbitrary fragmentation, or moving a monolith unchanged into a differently named module. Every extraction must improve cohesion, testability, reuse, or ownership.
- Generated code, vendored sources, lockfiles, schema snapshots, migrations, fixtures, and data or asset manifests are exempt when their tooling or format requires a single large file. Do not hand-edit generated or vendored artifacts unless the task explicitly requires it.
- Before handoff, inspect the sizes of changed hand-written source files. Explicitly report any that remain over 1,000 lines, why they remain, and the safest follow-up boundary.

### Verification and quality

- Add or update focused tests for changed behavior, including important failure paths and edge cases.
- Run the smallest relevant test, lint, formatting, type-check, and build commands first; expand verification in proportion to the risk of the change.
- Do not weaken, delete, skip, or rewrite tests merely to make a failing change pass. Fix the implementation or clearly report why the existing expectation is wrong.
- Review the final diff for accidental edits, debug output, generated noise, credentials, personal data, and unrelated formatting before handing work off.
- State what was verified and call out anything that could not be verified. Never claim a check passed unless it was actually run.

### Atomic and independent commits

- When commits are requested or are part of the authorized development workflow, make each commit one complete logical change that can be reviewed, tested, reverted, and understood independently.
- Default to the smallest complete commit that passes its relevant checks. Do not bundle independent changes merely because they were produced during the same request or working session.
- Keep refactors, behavior changes, tests, formatting, generated files, and dependency updates in separate commits when they represent separable concerns. A test may stay with the behavior it verifies.
- Do not leave an intentionally broken intermediate commit. Each commit should build and pass its relevant checks whenever the repository permits it.
- Stage files selectively and inspect the staged diff before committing. Never include unrelated user changes.
- Immediately before each commit, review `git status`, the staged file list, `git diff --cached`, and `git diff --cached --check`. If the staged diff has more than one independent intent, unstage and split it.
- Follow the repository's established commit-message convention. When it uses Conventional Commits, choose an accurate type and useful scope such as `feat`, `fix`, `refactor`, `test`, `docs`, `build`, `ci`, or `chore`; never hide a feature or bug fix behind a vague `update` or misleading `chore`.
- Use concise imperative commit subjects that explain the outcome; add a body when motivation, risk, migration, or verification details are not obvious.
- Do not amend, squash, rebase, reset, force-push, rewrite published history, or create a commit unless the user has authorized that Git action.

### Repository-authored publication voice

- Write commit messages, pull requests, issues, release notes, and code comments in the repository author's established voice, terminology, and level of detail. Match the project's existing history and contribution conventions.
- Describe the software change directly: the problem, decision, behavior, tradeoff, migration impact, and verified result. Do not narrate the prompt, working session, tools, agent workflow, model, or content-generation process.
- Prefer short, specific prose over canned templates, excessive headings, generic filler, marketing language, or repeated summaries. Use a project template only when the repository already requires it.
- Never fabricate personal experience, manual steps, review activity, benchmarks, or test results. Repository-author voice must remain factual and supported by the work actually performed.
- Before publication, remove generic generated-sounding phrasing, unsupported claims, process commentary, and any attribution that does not belong to the configured human author.

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

Use CloakBrowser-backed Playwright whenever a task requires opening, rendering, interacting with, screenshotting, extracting from, scraping, dynamically inspecting, or visually validating a webpage. In ordinary Codex sessions, use the `playwright_safe` MCP server; it starts a verified, loopback-only CloakBrowser for the MCP session. Inside `codex-safe`, use either the `playwright-cli` wrapper or `playwright_safe`; both attach to that hardened session's `CLOAK_CDP_ENDPOINT`.

### Browser mode declaration and cursor isolation

- Before the first browser tool call, explicitly state `Browser mode: headless` or `Browser mode: headed` in a commentary update and give the reason for that choice.
- In ordinary Codex sessions, use `playwright_safe` for headless work and `playwright_safe_headed` for headed work. Use exactly one browser server for a task; never start both modes speculatively.
- Default to headless for automated tests, extraction, scraping, and other work that does not need a user-visible browser. Select headed when the user asks to see the browser or visible GUI rendering is part of the requirement.
- Headed always means visible: it opens `CloakBrowser Automation (CDP only)` on the KDE desktop. Never describe a hidden or off-screen browser as headed.
- The visible window is a nested Xephyr display. CloakBrowser connects to that nested display, not directly to the KDE X11 display, and a KWin rule makes the Xephyr window non-focusable with Extreme focus-stealing prevention. Its appearance must not interrupt the user's active application.
- CloakBrowser uses Chromium's `basic` password backend only inside its disposable `0700` profile and receives no desktop D-Bus address. Browser automation must never request access to KDE Wallet or another desktop credential store.
- Keep all page interaction inside Playwright over CDP. Never use Computer Use, `xdotool`, `ydotool`, `wtype`, KWin scripting, desktop coordinates, OS mouse movement, or OS keyboard injection for browser work.
- The visible automation window is intentionally read-only to host keyboard input. If a workflow requires manual login, CAPTCHA, permission prompt, or other physical desktop interaction, stop and ask the user to perform that step in their own browser. Never take control of the host pointer or keyboard.
- Inside `codex-safe`, the selected mode is fixed when the session starts (`CODEX_SAFE_HEADED=true` selects headed). If the active mode does not match the declared mode, stop and request a correctly configured fresh session instead of silently changing modes.

### Playwright skill protocol

- Invoke the installed `playwright` skill for browser navigation, form interaction, screenshots, responsive checks, console/network inspection, accessibility-tree inspection, or end-to-end UI debugging.
- In ordinary Codex, use `playwright_safe` MCP tools only. Never run `npx @playwright/cli`, install browsers, invoke the skill's CLI fallback, or silently substitute stock Chromium.
- Start with `browser_navigate`, then capture `browser_snapshot`. Use refs only from the latest snapshot and refresh the snapshot after navigation or major DOM changes.
- Use snapshots for semantic understanding and refs; use `browser_take_screenshot` for visual evidence. For important journeys, inspect console messages and network requests after reproduction.
- Keep browser profiles, downloads, traces, screenshots, and other artifacts inside the active workspace or its repository-prescribed evidence directory.
- Use synthetic or repository-provided data. Do not bypass authentication, CAPTCHA, paywalls, access controls, rate limits, robots directives, or legal restrictions.
- If the MCP namespace is unavailable, run the read-only check `codex mcp get playwright_safe`, report that Codex must be restarted, and do not fall back to another browser.

Search APIs may be used only to discover sources and URLs. Do not claim that built-in search traffic itself passes through CloakBrowser. Do not fall back silently to stock Chromium. If CloakBrowser or its CDP endpoint is unavailable, report the failure.

Do not use CloakBrowser stealth functionality to bypass authentication, CAPTCHA, paywalls, access controls, rate limits, robots directives, or legal restrictions.
<!-- codex-safe browser policy: end -->

@__HOME__/.codex/RTK.md
