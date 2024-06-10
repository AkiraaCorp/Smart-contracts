//define a constructor and an the contract blueprint first here

#[derive(starknet::Store)]
enum Bet {
  None,
  Yes,
  No,
}

#[derive(starknet::Store)]
struct bet_amount {
  amount: felt252,
}

#[storage]
struct Storage {
  votes: LegacyMap<ContractAddress, Bet>,
  yes_count: felt252,
  no_count: felt252,
}

fn get_bet_output_per_adress(storage: Store<Storage>) -> (felt252, felt252) {
  let rate = storage.get_rate();
  let bet = storage.get_bet_output();
  (rate, bet)
}

fn get_rate_and_amount_per_address(storage: Store<Storage>) -> (felt252, felt252) {
  let rate = storage.get_rate();
  let amount_per_address = storage.get_amount_per_address();
  (rate, amount_per_address)
}

