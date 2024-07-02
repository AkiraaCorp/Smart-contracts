use core::hash::Hash;
//define a constructor and an the contract blueprint first here
use starknet::ContractAddress;

#[starknet::interface]
pub trait IEventBetting<TContractState> {
    fn store_name(
        ref self: TContractState, name: felt252, registration_type: EventBetting::RegistrationType
    );
    fn get_name(self: @TContractState, address: ContractAddress) -> felt252;
    fn get_owner(self: @TContractState) -> EventBetting::Person;
    fn place_bet(ref self: TContractState, bet: EventBetting::UserBet);
    fn get_bet(self: @TContractState, user_address: ContractAddress) -> (u8, u256);
    fn get_event_outcome(self: @TContractState) -> u8;
    fn get_shares_token_address(self: @TContractState) -> (ContractAddress, ContractAddress);
    fn get_is_active(self: @TContractState) -> bool;
    fn get_time_expiration(self: @TContractState) -> u256;
    fn get_all_bets(self: @TContractState) -> LegacyMap<ContractAddress, EventBetting::UserBet>;
    fn get_bet_per_user(self: @TContractState, user_address: ContractAddress) -> EventBetting::UserBet;
    fn get_total_bet_bank(self: @TContractState) -> u256;
}

pub trait IEventBettingImpl<TContractState> {
    fn bet_is_over(self: @TContractState) -> bool;

    fn refresh_odds(self: @TContractState, odds: EventBetting::Odds) -> u256;
}

#[starknet::contract]
pub mod EventBetting {
    use starknet::{ContractAddress, ClassHash, get_caller_address, get_contract_address};
    use core::num::traits::zero::Zero;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use starknet::SyscallResultTrait;
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use core::box::BoxTrait;
    use core::array::ArrayTrait;

    #[storage]
    struct Storage {
        names: LegacyMap::<ContractAddress, felt252>,
        owner: Person,
        total_names: u128,
        bets: LegacyMap<ContractAddress, UserBet>,
        event_probability: Odds,
        yes_count: u128,
        no_count: u128,
        total_bet_bank: u256,
        bet_fee: u256,
        event_outcome: u8, ///No = 0, Yes = 1 or 2 if event got no outcome yet
        is_active: bool,
        time_expiration: u256,
        shares_token_address: (ContractAddress, ContractAddress), ///First for the NO token address, second for the YES token address
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct UserBet {
        bet: u8, ///No = 0, Yes = 1
        amount: u256,
        has_claimed: bool,
        claimable_amount: u256,
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct Odds {
        no_probability: u256,
        yes_probability: u256,
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct Person {
        address: ContractAddress,
        name: felt252,
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub enum RegistrationType {
        finite: u64,
        infinite
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: Person) {
        self.names.write(owner.address, owner.name);
        self.total_names.write(1);
        self.owner.write(owner);
    }

    ///ici faire la fonction qui créer les 2 tokens NO et Yes pour le bet concerné

    #[abi(embed_v0)]
    impl EventBetting of super::IEventBetting<ContractState> {
        fn store_name(ref self: ContractState, name: felt252, registration_type: RegistrationType) {
            let caller = get_caller_address();
            self._store_name(caller, name, registration_type);
        }

        fn get_name(self: @ContractState, address: ContractAddress) -> felt252 {
            self.names.read(address)
        }

        fn get_owner(self: @ContractState) -> Person {
            self.owner.read()
        }

        fn place_bet(ref self: TContractState, bet: EventBetting::UserBet) {

        }
        fn get_bet(self: @TContractState, user_address: ContractAddress) -> (u8, u256) {

        }
        fn get_event_outcome(self: @TContractState) -> u8 {

        }
        fn get_shares_token_address(self: @TContractState) -> (ContractAddress, ContractAddress) {

        }
        fn get_is_active(self: @TContractState) -> bool {

        }
        fn get_time_expiration(self: @TContractState) -> u256 {

        }
        fn get_all_bets(self: @TContractState) -> LegacyMap<ContractAddress, EventBetting::UserBet> {

        }
        fn get_bet_per_user(self: @TContractState, user_address: ContractAddress) -> EventBetting::UserBet {

        }
        fn get_total_bet_bank(self: @TContractState) -> u256 {

        }
        
    }
}
