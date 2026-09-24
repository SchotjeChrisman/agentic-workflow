# Library docs

Check third-party libraries, frameworks, SDKs, CLI tools and platform APIs against current docs with Context7, not memory:
- before writing or changing code that uses an API, option or config key you haven't confirmed this session;
- when an error, warning or deprecation names a library API ("deprecated", "does not contain a definition", "unknown option"), before working around it or calling it pre-existing;
- when a plan or review depends on how a library behaves;
- when I ask about one.

Not for our own code, general programming concepts, or refactors that don't change library calls.

1. Version first: read the installed version from the lockfile or manifest.
2. `resolve-library-id` with the package's official name as the manifest spells it. Check that the result's org and description belong to that vendor; if not, retry with another name. Use a version-specific ID when one matches step 1.
3. `query-docs` once per concept. Stop after 3 lookups for one question and say what's still unclear.
4. Where the Context7 MCP tools aren't available (the verifier and critic agents) or fail, use the CLI: `npx ctx7@latest library <name> "<query>"`, then `npx ctx7@latest docs <id> "<query>"`. If both fail, say so; never fall back to memory silently.
5. Docs silent or ambiguous: the installed package's source or types settle exact signatures. Web search is for issues and changelogs, not API docs.
6. A library ID that proved right for a project goes into that project's memory, so the next session skips resolving it.
