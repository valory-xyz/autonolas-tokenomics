# Forwarder validation — 2026-10-19

Validated source revision: `f7c6f228b7cd0f2bdee361efd52fb16b1e65a459`.

- Targeted rebuild: successful, solc `0.8.30+commit.73712a01`.
- `PolygonBurnForwarderTest`: 9 passed, 0 failed, 0 skipped.
- Installed Forge: `1.6.0-nightly`, commit `e0d4aab210b1386d8dcf212c12646e465738d20b`.
  This differs from the PR's CI toolchain (`1.7.1`).

`build-record.json` records the compiler metadata (including effective remappings),
dependency commit pins, constructor inputs, factory, salt, and calculated hashes.
`unit-tests.txt` contains the exact test command and output. The command excludes
unrelated contracts to avoid compiling legacy Solidity sources with solc 0.8.30;
it still compiles the forwarder suite's imports. No fork tests were run.

The four `lib` directories were restored as exported Git trees at the recorded
commit pins, using `git archive <pin>` in each existing local dependency repository.
There was no `node_modules` directory and no dependency symlink. Nested submodules
were not populated. Forge's attempted automatic submodule initialization failed
because these exported directories were non-empty; the build and tests nevertheless
completed successfully using the exported sources.

The complete init-code hash, using the committed mainnet globals, was:

```text
0x8f85891423ff33134902eb8ae23511284c06ac6e3275f2524c009d4e700621d9
```

Its predicted CREATE2 address was `0x682a4DdD50F3c9d9E40D0C93B047e5Cf00B4AE8F`.
Both values were independently checked against the deployment helper by sourcing
`scripts/deployment/utils/polygon_burn_forwarder_common.sh`, calling `pbfLoadArgs`
and `pbfPredict`, then reading `cast keccak "$initCode"` and `$predicted`.

These values describe this local validation build. They are not deployment
approvals or production configuration. No transactions were sent. Prepare the
final deployment record from the final chosen revision and toolchain as described
in [the deployment notes](../../polygon_burn_forwarder_deployment.md).
