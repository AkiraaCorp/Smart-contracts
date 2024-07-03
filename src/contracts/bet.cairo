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
    fn get_event_probability(self: @TContractState) -> EventBetting::Odds;
    fn get_event_outcome(self: @TContractState) -> u8;
    fn get_is_active(self: @TContractState) -> bool;
    fn set_is_active(ref self: TContractState, is_active: bool);
    fn get_time_expiration(self: @TContractState) -> u256;
    fn set_time_expiration(ref self: TContractState, time_expiration: u256);
    fn get_all_bets(self: @TContractState) -> Array<EventBetting::UserBet>;
    fn get_bet_per_user(self: @TContractState, user_address: ContractAddress) -> Array<EventBetting::UserBet>;
    fn get_total_bet_bank(self: @TContractState) -> u256;
    ///rajouter fonction pour voir combien l'user peut claim + fonction pour claim
}

pub trait IEventBettingImpl<TContractState> {
    fn bet_is_over(self: @TContractState) -> bool;

    fn refresh_odds(self: @TContractState, odds: EventBetting::Odds) -> u256;
}

#[starknet::contract]
pub mod EventBetting {
    use akira_smart_contract::contracts::bet::IEventBetting;
use core::option::OptionTrait;
use starknet::{ContractAddress, ClassHash, get_caller_address, get_contract_address};
    use core::num::traits::zero::Zero;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use starknet::SyscallResultTrait;
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use core::box::BoxTrait;
    use core::array::ArrayTrait;


    const PLATFORM_FEE: u256 = 5;
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
        no_share_token_address: ContractAddress,
        yes_share_token_address: ContractAddress,
    }

    #[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Eq, Hash)]
    pub struct UserBet {
        bet: bool, ///No = false, Yes = true
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
    fn constructor(ref self: ContractState, owner: ContractAddress, token_no_address: ContractAddress, token_yes_adress: ContractAddress) {
        ///remplir avec tout les params du storage
        self.owner.write(owner);
        let token_adresses = (token_no_address, token_yes_adress);
        self.no_share_token_address.write(token_no_address);
        self.yes_share_token_address.write(token_yes_adress);
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
            assert(self.get_is_active() == true, 'This event is not active');
            let odds = self.get_event_probability();
            let (no_odds, yes_odds) = (odds.no_probability, odds.yes_probability);
            let user_choice = bet.bet;
            let mut dispatcher: IERC20Dispatcher = "0x0000";
            if user_choice == false {
                dispatcher = IERC20Dispatcher { contract_address: self.no_share_token_address.read() };
            }
            else {
                dispatcher = IERC20Dispatcher { contract_address: self.yes_share_token_address.read() };
            }
            let bet_amount = bet.amount;
            let tx: bool = dispatcher.transfer_from(get_caller_address(), get_contract_address(), bet_amount);
            dispatcher.transfer( 

        }

        fn get_bet(self: @ContractState, user_address: ContractAddress) -> UserBet {
            self.bets.read(user_address)
        }

        fn get_event_probability(self: @ContractState) -> Odds {
            self.event_probability.read()
        }

        fn get_event_outcome(self: @ContractState) -> u8 {
            self.event_outcome.read()
        }

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
            let mut i: u32 = 0;
            let count = self.bets_count.read();
            loop {
                if i > count - 1 {
                    break;
                }
                let key = self.bets_key.read().get(i).unwrap();
                let bet = self.bets.read(*key.unbox());
                bets.append(bet);
                i += 1;
            };
            bets
        }

        fn get_bet_per_user(self: @ContractState, user_address: ContractAddress) -> Array<UserBet> {
            let mut bets: Array<UserBet> = ArrayTrait::new();
            let mut i: u32 = 0;
            let count = self.bets_count.read();
            loop {
                if i > count - 1 {
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
