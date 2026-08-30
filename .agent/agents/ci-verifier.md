# ci-verifier

**Canonical file lives in the sibling code repo:**
[`../golden-fur/.agent/agents/ci-verifier.md`](../../../golden-fur/.agent/agents/ci-verifier.md).

This agent is shared between `golden-fur` and this vault — it runs the
`✅ CI: Verify All` task for **both** repos (this vault's is
`npm run format:check`; golden-fur's is tests + lint + format + build) and
reports one pass/fail. It is maintained in `golden-fur` because that repo
carries the heavier checks; this file is only a pointer so a vault session
can discover and spawn it.

Read and follow the canonical file. Read-only: it runs check commands and
reports — it never fixes, stages, commits, or pushes, in either repo.

**Use whenever** committing, pushing, or opening a PR in either repo — it
is a mandatory step of this vault's `commit` and `pr` skills.
