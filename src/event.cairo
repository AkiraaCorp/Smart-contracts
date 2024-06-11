//define a constructor and an the contract blueprint first here
#[starknet::interface]
trait IBetting<TContractState> {
    fn place_bet(ref self: TContractState, bet: u8, amount: u128);
    fn get_bet(self: @TContractState, user_address: ContractAddress) -> (u8, u128);
}

#[starknet::contract]
mod Betting {
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    const YES: u8 = 1_u8;
    const NO: u8 = 0_u8;

    //Here we use user address as a Key to retrieve bets
    #[storage]
    struct Storage {
        bets: LegacyMap::<ContractAddress, (u8, u128)>,
        yes_count: u128,
        no_count: u128,
    }

    #[abi(embed_v0)]
    impl Betting of super::IBetting<ContractState> {
        fn place_bet(ref self: ContractState, bet: u8, amount: u128) {
            assert!(bet == NO || bet == YES, "BET_0_OR_1");
            let caller: ContractAddress = get_caller_address();
            self.bets.write(caller, (bet, amount));
            if bet == YES {
                self.yes_count += 1;
            } else {
                self.no_count += 1;
            }
            self.emit(BetPlaced { user: caller, amount: amount });
        }

        fn get_bet(self: @ContractState, user_address: ContractAddress) -> (u8, u128) {
            self.bets.read(user_address)
        }
    }
}

//function to get the bet output per address, so Yes or No for each user
fn get_bet_output_per_adress(storage: Store<Storage>) -> (felt252, felt252) {
  let rate = storage.get_rate();
  let bet = storage.get_bet_output();
  (rate, bet)
}

//function to get the rate and amount per address,
//get this at the end of an event in case user outpur is right
fn get_rate_and_amount_per_address(storage: Store<Storage>) -> (felt252, felt252) {
  let rate = storage.get_rate();
  let amount_per_address = storage.get_amount_per_address();
  (rate, amount_per_address)
}

//emit an event each time a bet is placed in order to get latest info and refresh rate on App
#[derive(Drop, starknet::Event)]
struct BetPlaced {
    #[key]
    user: ContractAddress,
    amount: felt252,
}

#[event]
#[derive(Drop, starknet::Event)]
enum Event {
    BetPlaced: BetPlaced,
}
