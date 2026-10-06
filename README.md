# StrataIMD (STRATA)

StrataIMD is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 tokens with 18 decimals** to the immediate deploying address. Transfers deliver the exact requested amount.

| Deployment parameter | Value |
| --- | --- |
| Contract | `src/StrataIMD.sol:StrataIMD` |
| Name | `StrataIMD` |
| Symbol | `STRATA` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; empty ABI encoding) |
| Constructor transaction value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Solidity compiler | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

## Design and assumptions

The request is interpreted as a standard transferable ERC-20. The contract inherits the vendored OpenZeppelin ERC20 implementation and adds only the initial supply constant and constructor mint. There are no taxes, rebases, burns, transfer restrictions, owner, privileged roles, further minting, upgrade mechanism, or initialization calls. The deployed contract makes no external calls during token operations.

An EOA deploying directly receives the entire supply. If a factory deploys the contract, **the factory receives the entire supply**, regardless of who called the factory. A factory must be able to forward its tokens; otherwise they remain there. The token itself does not distribute launch allocations or create liquidity.

Successful `transfer`, `approve`, and `transferFrom` calls return `true`; invalid operations revert with ERC-20 custom errors. Zero-value transfers and self-transfers are supported. Transfers to the zero address and approvals to the zero spender are rejected. Finite allowances decrease on spending; `type(uint256).max` represents unlimited allowance and does not decrease. `approve` replaces the previous allowance. Transfer events include the constructor mint, and explicit approvals emit Approval events. This OpenZeppelin version does not emit Approval when `transferFrom` spends allowance; integrations should query `allowance` for its current value.

## Build and test

Install Foundry and make Solidity 0.8.26 available to it. All Solidity dependencies are included as ordinary files under `lib/`; no `forge install`, package manager, submodule, network RPC, or environment configuration is required. The compiler is provided by the execution environment, not stored in this repository.

```sh
forge build
forge test
forge fmt --check
sha256sum -c SHA256SUMS
```

When the pinned compiler is already available, `forge build --offline` and `forge test --offline` can explicitly enforce offline operation. The configuration disables FFI and grants no filesystem permissions to contracts or tests.

Tests cover metadata, mint events and allocation, CREATE2 factory deployment, launch-like exact transfers, transfer events, full-balance/zero/self transfers, approvals and revocation, finite/unlimited allowances, invalid addresses, insufficient balances/allowances, rollback after failed delegated transfers, missing mint/admin/burn entry points, prohibited runtime opcodes, and rejected native-currency payments. Four fuzz tests exercise amount boundaries with 512 cases each. A stateful invariant test compares balances and allowances against a separate ledger over 128 runs of 64 operations, checking supply conservation throughout. Tests use isolated deployments and fixed local addresses and do not read or modify environment variables.

The local factory fixture models token movements, including a distributor claim and transfers in both directions with a pool address. Its illustrative 20% pool allocation is only a test input. It does not instantiate Uniswap v4 or verify actual swaps. The supplied protected launch harness requires the network's factory/pool contracts and launch-specific inputs; it remains a separate integration check for the launch operator. No production chain addresses or economics were supplied for this assignment.

## Deployment and operational responsibilities

1. Build with the pinned settings above. Obtain creation bytecode with `forge inspect src/StrataIMD.sol:StrataIMD bytecode`; constructor arguments are empty. The artifact is `out/StrataIMD.sol/StrataIMD.json`. No library linking is required.
2. The authorized deployment operator selects the target Cancun-compatible chain and deployment address, verifies the intended factory can distribute its initial balance, and supplies the creation bytecode to the launch system. For CREATE2, the factory and salt determine the address alongside the creation-code hash. Deploy the concrete contract directly; no proxy or initializer is involved.
3. For an IdentityMD custom launch, use the token values in the table, with no application contracts. The network's factory/distributor handles the swarm allocation and the remaining distribution. Pool pairing, fee, tick spacing, liquidity/price, requester destination, market cap, launch number, and pool allocation must come from the authorized launch configuration. They are neither constructor parameters nor defaults chosen by this token project.
4. After deployment, the operator verifies source and compiler settings, checks name/symbol/decimals and total supply, confirms the constructor mint recipient and subsequent distribution events, and runs the protected launch integration checks against the actual launch configuration.

There is no ongoing token administrator or keeper. Holders control transfers and allowances, and the initial deployer controls the initial inventory. Users are responsible for recipient addresses and spender approvals. Prefer bounded approvals; when changing an existing allowance, revoke it and wait for confirmation before setting a new value to reduce the ERC-20 allowance replacement race. Existing authorization remains usable until revocation is mined.

The token has no asset-recovery function. Tokens mistakenly sent to the token contract, or other assets sent there, may be permanently inaccessible. Ordinary ETH payments revert, although forced ETH cannot be prevented. These properties are intentional consequences of having no privileged controls.

No transactions were broadcast and no wallet keys are needed for local checks. Foundry build, unit/fuzz/invariant tests, and formatting checks were run locally. Slither and Mythril were not run. Local checks are not an independent security audit; the network's separate adversarial review and deployment checks remain the release operator's responsibility.

Dependency versions, source provenance, licenses, and file hashes are recorded in [DEPENDENCIES.md](DEPENDENCIES.md) and [SHA256SUMS](SHA256SUMS).
