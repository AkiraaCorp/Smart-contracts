# Setup version
```
scarb --version
scarb 2.6.4 (c4c7c0bac 2024-03-19)
cairo: 2.6.3 (https://crates.io/crates/cairo-lang-compiler/2.6.3)
sierra: 1.5.0
```

# Smart-contracts
Smart-contracts (Cairo) repo for Akira project

First we deploy smart-contract and after that we will connect them to front end using our back.

Smart-contract storage suggested by Charles :

```#[derive(starknet::Store)]
enum Vote {
  None,
  Yes,
  No,
}

#[storage]
struct Storage {
  votes: LegacyMap<ContractAddress, Vote>,
  yes_count: felt252,
  no_count: felt252,
}
```
