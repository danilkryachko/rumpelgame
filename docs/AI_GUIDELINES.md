# AI GUIDELINES

1. **NO SLOP:** Keep the code DRY. No magic numbers. Use proper structs, traits, and interfaces.
2. **MAXIMUM MODULARITY:** Every single feature MUST be a separate module or package.
   - In Go: isolate features into `/pkg/feature_name`.
   - In Rust: isolate features into `mod feature_name` or separate local crates.
3. **Branching Workflow:**
   - Create a feature branch (`feat/name`).
   - Implement, write unit tests.
   - Ensure `clippy` and `golangci-lint` pass with no warnings.
   - Merge to `main` and delete the feature branch.
3. **No Degradation:** Always consult `ARCHITECTURE.md` before making design changes.
4. **AgentMemory:** Use `agentmemory` to persist critical decisions.
