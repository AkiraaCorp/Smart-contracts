use core::hash::Hash;
//define a constructor and an the contract blueprint first here
use starknet::ContractAddress;


#[starknet::interface]
pub trait IEventBetting<TContractState> {
    fn store_name(ref self: TContractState, name: felt252);
    fn get_name(self: @TContractState, address: ContractAddress) -> felt252;
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn place_bet(ref self: TContractState, bet: EventBetting::UserBet);
    fn get_bet(self: @TContractState, user_address: ContractAddress) -> EventBetting::UserBet;
    fn get_event_outcome(self: @TContractState) -> u8;
    fn get_shares_token_address(self: @TContractState) -> (ContractAddress, ContractAddress);
    fn get_is_active(self: @TContractState) -> bool;
    fn set_is_active(ref self: TContractState, is_active: bool);
    fn get_time_expiration(self: @TContractState) -> u256;
    fn set_time_expiration(ref self: TContractState, time_expiration: u256);
    fn get_all_bets(self: @TContractState) -> Array<EventBetting::UserBet>;
    fn get_bet_per_user(self: @TContractState, user_address: ContractAddress) -> Array<EventBetting::UserBet>;
    fn get_total_bet_bank(self: @TContractState) -> u256;
}

pub trait IEventBettingImpl<TContractState> {
    fn bet_is_over(self: @TContractState) -> bool;

    fn refresh_odds(self: @TContractState, odds: EventBetting::Odds) -> u256;
}

#[starknet::contract]
pub mod EventBetting {
    use core::option::OptionTrait;
use starknet::{ContractAddress, ClassHash, get_caller_address, get_contract_address};
    use core::num::traits::zero::Zero;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use starknet::SyscallResultTrait;
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use core::box::BoxTrait;
    use core::array::ArrayTrait;

    #[storage]
    struct Storage {
        name: felt252,
        owner: ContractAddress,
        total_names: u128,
        bets: LegacyMap<ContractAddress, UserBet>,
        bets_key: Array<ContractAddress>,
        bets_count: u32,
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

    #[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Eq, Hash)]
    pub struct UserBet {
        bet: u8, ///No = 0, Yes = 1
        amount: u256,
        has_claimed: bool,
        claimable_amount: u256,
    }

    #[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Eq, Hash)]
    pub struct Odds {
        no_probability: u256,
        yes_probability: u256,
    }

    #[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Eq, Hash)]
    pub enum RegistrationType {
        finite: u64,
        infinite
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        ///remplir avec tout les params du storage
        self.owner.write(owner);
    }

    ///ici faire la fonction qui créer les 2 tokens NO et Yes pour le bet concerné

    #[abi(embed_v0)]
    impl EventBetting of super::IEventBetting<ContractState> {
        fn store_name(ref self: ContractState, name: felt252) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            self.name.write(name);
        }

        fn get_name(self: @ContractState, address: ContractAddress) -> felt252 {
            self.name.read()
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn place_bet(ref self: ContractState, bet: UserBet) {

        }

        fn get_bet(self: @ContractState, user_address: ContractAddress) -> UserBet {
            self.bets.read(user_address)
        }

        fn get_event_outcome(self: @ContractState) -> u8 {
            self.event_outcome.read()
        }

        fn get_shares_token_address(self: @ContractState) -> (ContractAddress, ContractAddress) {
            self.shares_token_address.read()
        }
        fn get_is_active(self: @ContractState) -> bool {
            self.is_active.read()
        }

        fn set_is_active(ref self: ContractState, is_active: bool) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            self.is_active.write(is_active);
        }

        fn get_time_expiration(self: @ContractState) -> u256 {
            self.time_expiration.read()
        }

        fn set_time_expiration(ref self: ContractState, time_expiration: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            self.time_expiration.write(time_expiration);
        }

        fn get_all_bets(self: @ContractState) -> Array<UserBet> {
            let mut bets: Array<UserBet> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                let bet = self.bets.read(i);
                bets.append(bet);
                i += 1;
            };
            bets
        }

        ///Attention ici faut implemeter une logique au cas ou l'user est fait plusieurs bets
        fn get_bet_per_user(self: @ContractState, user_address: ContractAddress) -> Array<UserBet> {
            let mut bets: Array<UserBet> = ArrayTrait::new();
            let mut i: u32 = 1;
            loop {
                if i > self.bets_count.read() {
                    break;
                }
                let key = self.bets_key.read().get(i).unwrap();
                if key.unbox() == @user_address {
                    let bet = self.bets.read(*key.unbox());
                    bets.append(bet);
                }
                i += 1;
            };
            bets
        }

        fn get_total_bet_bank(self: @ContractState) -> u256 {
            self.total_bet_bank.read()
        }
        
    }
}
