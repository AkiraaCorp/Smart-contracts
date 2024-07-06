use core::hash::Hash;
//define a constructor and an the contract blueprint first here
use starknet::ContractAddress;


#[starknet::interface]
pub trait IEventBetting<TContractState> {
    fn store_name(ref self: TContractState, name: felt252);
    fn get_name(self: @TContractState, address: ContractAddress) -> felt252;
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn place_bet(
        ref self: TContractState, user_address: ContractAddress, bet_amount: u256, bet: bool
    );
    fn get_bet(self: @TContractState, user_address: ContractAddress) -> EventBetting::UserBet;
    fn get_event_probability(self: @TContractState) -> EventBetting::Odds;
    fn get_event_outcome(self: @TContractState) -> u8;
    fn get_is_active(self: @TContractState) -> bool;
    fn set_is_active(ref self: TContractState, is_active: bool);
    fn get_time_expiration(self: @TContractState) -> u256;
    fn set_time_expiration(ref self: TContractState, time_expiration: u256);
    fn get_all_bets(self: @TContractState) -> Array<EventBetting::UserBet>;
    fn get_bet_per_user(
        self: @TContractState, user_address: ContractAddress
    ) -> Array<EventBetting::UserBet>;
    fn get_total_bet_bank(self: @TContractState) -> u256;

    ///attention cette fonciton ne doit pas etre visible de l'exterieur
    fn refresh_event_odds(
        ref self: TContractState,
        current_odds: EventBetting::Odds,
        user_choice: bool,
        bet_amount: u256
    );
///fn log_cost(self: @TContractState, liquidity_precision: u64, no_prob: u64, yes_prob: u64) -> cubit::f64::Fixed;
///fn convert_odds_to_probability(self: @TContractState, no_odds: u256, yes_odds: u256) -> (cubit::f64::Fixed, cubit::f64::Fixed);

///rajouter fonction pour voir combien l'user peut claim + fonction pour claim
}

pub trait IEventBettingImpl<TContractState> {
    fn bet_is_over(self: @TContractState) -> bool;

    fn refresh_odds(self: @TContractState, odds: EventBetting::Odds) -> u256;
}

#[starknet::contract]
pub mod EventBetting {
    use akira_smart_contract::contracts::bet::IEventBetting;
    use core::array::ArrayTrait;
    use core::box::BoxTrait;
    use core::num::traits::zero::Zero;
    use core::option::OptionTrait;
    use cubit::f64::{math::ops::{ln, exp}, types::fixed::{Fixed, FixedTrait}};
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use starknet::SyscallResultTrait;
    use starknet::storage_access::StorageBaseAddress;
    use starknet::{
        ContractAddress, SyscallResult, Store, ClassHash, get_caller_address, get_contract_address
    };


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
        yes_total_amount: u256,
        no_count: u128,
        no_total_amount: u256,
        total_bet_bank: u256,
        bet_fee: u256,
        event_outcome: u8, ///No = 0, Yes = 1 or 2 if event got no outcome yet
        is_active: bool,
        time_expiration: u256,
        bank_wallet: ContractAddress,
        no_share_token_address: ContractAddress,
        yes_share_token_address: ContractAddress,
    }

    #[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Eq, Hash)]
    pub struct UserBet {
        bet: bool, ///No = false, Yes = true
        amount: u256,
        has_claimed: bool,
        claimable_amount: u256,
        user_odds: Odds,
    }
    #[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Eq, Hash)]
    pub struct Odds {
        no_probability: u64,
        yes_probability: u64,
    }

    #[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Eq, Hash)]
    pub enum RegistrationType {
        finite: u64,
        infinite
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        token_no_address: ContractAddress,
        token_yes_adress: ContractAddress,
        bank_wallet: ContractAddress,
        event_name: felt252
    ) {
        self.owner.write(owner);
        self.no_share_token_address.write(token_no_address);
        self.yes_share_token_address.write(token_yes_adress);
        self.bank_wallet.write(bank_wallet);
        self.is_active.write(false);
        self.event_outcome.write(2);
        self.yes_count.write(0);
        self.no_count.write(0);
        self.yes_total_amount.write(0);
        self.no_total_amount.write(0);
        self.total_names.write(0);
        self.bets_count.write(0);
        let probability = Odds { no_probability: 100, yes_probability: 100 };
        self.event_probability.write(probability);
        let array_key: Array<ContractAddress> = array![];
        self.bets_key.write(array_key);
        self.name.write(event_name);
    }

    impl EventBettingArray of Store<Array<ContractAddress>> {
        fn read(
            address_domain: u32, base: StorageBaseAddress
        ) -> SyscallResult<Array<ContractAddress>> {
            Store::read_at_offset(address_domain, base, 0)
        }

        fn write(
            address_domain: u32, base: StorageBaseAddress, value: Array<ContractAddress>
        ) -> SyscallResult<()> {
            Store::write_at_offset(address_domain, base, 0, value)
        }

        fn read_at_offset(
            address_domain: u32, base: StorageBaseAddress, mut offset: u8
        ) -> SyscallResult<Array<ContractAddress>> {
            let mut arr: Array<ContractAddress> = array![];

            let len: u8 = Store::<u8>::read_at_offset(address_domain, base, offset)
                .expect('Storage Span too large');
            offset += 1;

            let exit = len + offset;
            loop {
                if offset >= exit {
                    break;
                }

                let value = Store::<ContractAddress>::read_at_offset(address_domain, base, offset)
                    .unwrap();
                arr.append(value);
                offset += Store::<ContractAddress>::size();
            };

            Result::Ok(arr)
        }

        fn write_at_offset(
            address_domain: u32,
            base: StorageBaseAddress,
            mut offset: u8,
            mut value: Array<ContractAddress>
        ) -> SyscallResult<()> {
            let len: u8 = value.len().try_into().expect('Storage - Span too large');
            Store::<u8>::write_at_offset(address_domain, base, offset, len).unwrap();
            offset += 1;

            while let Option::Some(element) = value
                .pop_front() {
                    Store::<ContractAddress>::write_at_offset(address_domain, base, offset, element)
                        .unwrap();
                    offset += Store::<ContractAddress>::size();
                };

            Result::Ok(())
        }

        fn size() -> u8 {
            255 * Store::<ContractAddress>::size()
        }
    }

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

        fn place_bet(
            ref self: ContractState, user_address: ContractAddress, bet_amount: u256, bet: bool
        ) {
            assert(self.get_is_active() == true, 'This event is not active');
            let odds = self.get_event_probability();
            let current_odds = Odds {
                no_probability: odds.no_probability, yes_probability: odds.yes_probability
            };
            let user_choice = bet;
            let contract_address = get_caller_address(); ///ici mettre une vraie addresse avec les tokens yes et no
            let mut dispatcher = IERC20Dispatcher { contract_address };
            if user_choice == false {
                dispatcher =
                    IERC20Dispatcher { contract_address: self.no_share_token_address.read() };
            } else {
                dispatcher =
                    IERC20Dispatcher { contract_address: self.yes_share_token_address.read() };
            }
            let tx: bool = dispatcher
                .transfer_from(get_caller_address(), get_contract_address(), bet_amount);
            dispatcher.transfer(self.bank_wallet.read(), bet_amount * PLATFORM_FEE / 100);
            let total_user_share = bet_amount - (bet_amount * PLATFORM_FEE / 100);
            self.bets_count.write(self.bets_count.read() + 1);
            self.total_bet_bank.write(self.total_bet_bank.read() + total_user_share);
            if user_choice == false {
                self.no_total_amount.write(self.no_total_amount.read() + total_user_share);
            } else {
                self.yes_total_amount.write(self.yes_total_amount.read() + total_user_share);
            }
            let user_bet = UserBet {
                bet: user_choice,
                amount: total_user_share,
                has_claimed: false,
                claimable_amount: 0,
                user_odds: current_odds
            };
            self.bets.write(user_address, user_bet);
        ///
        /// self.refresh_event_odds();
        ///
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

        // fn log_cost(self: @ContractState, liquidity_precision: u64, no_prob: u64, yes_prob: u64) -> Fixed {
        //     let cost_no = FixedTrait::new_unscaled(no_prob, false) / FixedTrait::new_unscaled(liquidity_precision, false);
        //     let exp_no = cost_no.exp();
        //     let cost_yes = FixedTrait::new_unscaled(yes_prob, false) / FixedTrait::new_unscaled(liquidity_precision, false);
        //     let exp_yes = cost_yes.exp();

        //     let result: u64 = liquidity_precision * (exp_no.mag + exp_yes.mag);
        //     let fixed_result = Fixed { mag: result, sign: false };

        //    fixed_result.ln() ///ici on sort un fixed mais on utilisera uniquement le mag
        ///Verifier absolument le resultat de cette fonction dans les tests 
        //}

        // fn convert_odds_to_probability(self: @ContractState, no_odds: u256, yes_odds: u256) -> (Fixed, Fixed) {
        //     let scale: u256 = 10000; ///ici il faut mettre un f64
        //     let mut no_probability = (no_odds * scale) as u256;
        //     let mut yes_probability = (yes_odds * scale) as u256;

        // }

        fn refresh_event_odds(
            ref self: ContractState, current_odds: Odds, user_choice: bool, bet_amount: u256
        ) { // let liquidity_precision: u64 = 1000;
        // let no_odds = current_odds.no_probability;
        // let yes_odds = current_odds.yes_probability;

        // let current_cost = log_cost(liquidity_precision, no_odds, yes_odds);

        }
    }
}
