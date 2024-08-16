use starknet::ContractAddress;

#[starknet::interface]
pub trait IEventBetting<TContractState> {
    fn store_name(ref self: TContractState, name: felt252);
    fn get_name(self: @TContractState) -> felt252;
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn place_bet(
        ref self: TContractState, user_address: ContractAddress, bet_amount: u256, bet: bool
    );
    fn get_bet(self: @TContractState, user_address: ContractAddress) -> EventBetting::UserBet;
    fn has_bet(self: @TContractState, user_address: ContractAddress) -> bool;
    fn get_event_probability(self: @TContractState) -> EventBetting::Odds;
    fn set_event_probability(
        ref self: TContractState, no_initial_prob: u256, yes_initial_prob: u256
    );
    fn set_event_outcome(ref self: TContractState, event_result: u8);
    fn set_yes_token_address(ref self: TContractState, token_address: ContractAddress);
    fn set_no_token_address(ref self: TContractState, token_address: ContractAddress);
    fn get_event_outcome(self: @TContractState) -> u8;
    fn get_is_active(self: @TContractState) -> bool;
    fn set_is_active(ref self: TContractState, is_active: bool);
    fn get_time_expiration(self: @TContractState) -> u256;
    fn set_time_expiration(ref self: TContractState, time_expiration: u256);
    fn get_bet_per_user(
        self: @TContractState, user_address: ContractAddress
    ) -> EventBetting::UserBet;
    fn get_total_bet_bank(self: @TContractState) -> u256;

    fn is_claimable(self: @TContractState, bet_to_claim: EventBetting::UserBet) -> bool;
    fn claimable_amount(self: @TContractState, user_address: ContractAddress) -> u256;
    fn claim_reward(ref self: TContractState, user_address: ContractAddress);
}

pub trait IEventBettingImpl<TContractState> {
    fn bet_is_over(self: @TContractState) -> bool;
    fn refresh_odds(self: @TContractState, odds: EventBetting::Odds) -> u256;
}

#[starknet::contract]
pub mod EventBetting {
    use akira_smart_contract::ERC20::ERC20Contract::IERC20ContractDispatcherTrait;
    use akira_smart_contract::contracts::bet::IEventBetting;
    use core::array::ArrayTrait;
    use core::box::BoxTrait;
    use core::num::traits::zero::Zero;
    use core::option::OptionTrait;
    use core::starknet::event::EventEmitter;
    use core::traits::TryInto;
    use cubit::f64::{math::ops::{ln, exp}, types::fixed::{Fixed, FixedTrait}};
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20CamelDispatcher};
    use starknet::SyscallResultTrait;
    use starknet::storage_access::StorageBaseAddress;
    use starknet::{
        ContractAddress, SyscallResult, Store, ClassHash, get_caller_address, get_contract_address,
        get_block_timestamp, contract_address_const,
    };
    use super::super::super::ERC20::ERC20Contract;


    const PLATFORM_FEE: u256 = 2;
    #[storage]
    struct Storage {
        name: felt252,
        owner: ContractAddress,
        total_names: u128,
        bets: LegacyMap<felt252, UserBet>,
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
        pub no_probability: u256,
        pub yes_probability: u256,
    }

    // events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        BetPlace: BetPlaced,
        Claim: BetClaimed,
        EventTimeout: EventFinished,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BetPlaced {
        user_bet: UserBet,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BetClaimed {
        event_name: felt252,
        amount_claimed: u256,
        event_outcome: u8,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EventFinished {
        timestamp: u64,
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
        self.is_active.write(true);
        self.event_outcome.write(2);
        self.yes_count.write(0);
        self.no_count.write(0);
        self.yes_total_amount.write(0);
        self.no_total_amount.write(0);
        self.total_names.write(0);
        self.bets_count.write(0);
        let probability = Odds { no_probability: 4000, yes_probability: 4000 };
        self.event_probability.write(probability);
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

        fn get_name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn place_bet(
            ref self: ContractState, user_address: ContractAddress, bet_amount: u256, bet: bool
        ) {
            assert(self.get_is_active() == true, 'This event is not active');
            assert(self.has_bet(user_address) == false, 'User already bet');
            let odds = self.get_event_probability();
            let current_odds = Odds {
                no_probability: odds.no_probability, yes_probability: odds.yes_probability
            };
            let user_choice = bet;
            if user_choice == false {
                let dispatcher = ERC20Contract::IERC20ContractDispatcher {
                    contract_address: self.no_share_token_address.read()
                };
                let strk_address: ContractAddress =
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                    .try_into()
                    .unwrap();
                //STRK approve = le multicall et l'approve se font directement dans le front
                //STRK deposit
                let stark_token = IERC20Dispatcher { contract_address: strk_address };

                stark_token.transfer_from(user_address, self.bank_wallet.read(), bet_amount);

                let platform_fee_amount = bet_amount * PLATFORM_FEE / 100;

                assert(bet_amount > platform_fee_amount, 'Bet amount too small');

                let total_user_share = bet_amount - platform_fee_amount;

                self.bets_count.write(self.bets_count.read() + 1);
                self.total_bet_bank.write(self.total_bet_bank.read() + total_user_share);
                let mut user_odds = current_odds.no_probability;
                if user_choice == false {
                    self.no_total_amount.write(self.no_total_amount.read() + total_user_share);
                } else {
                    user_odds = current_odds.yes_probability;
                    self.yes_total_amount.write(self.yes_total_amount.read() + total_user_share);
                }
                let potential_reward = (total_user_share * 10000) / user_odds;
                dispatcher.mint(user_address, potential_reward);
                let user_bet = UserBet {
                    bet: user_choice,
                    amount: total_user_share,
                    has_claimed: false,
                    claimable_amount: potential_reward,
                    user_odds: current_odds
                };

                refresh_event_odds(ref self, user_choice, total_user_share);
                let address_to_felt: felt252 = user_address
                    .try_into()
                    .expect('failed to convert address');
                self.bets.write(address_to_felt, user_bet);
                let bet_event = BetPlaced { user_bet, timestamp: get_block_timestamp() };
                self.emit(Event::BetPlace(bet_event));
            } else {
                let dispatcher = ERC20Contract::IERC20ContractDispatcher {
                    contract_address: self.yes_share_token_address.read()
                };
                let strk_address: ContractAddress =
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                    .try_into()
                    .unwrap();
                //STRK approve = le multicall et l'approve se font directement dans le front
                //STRK deposit
                let stark_token = IERC20Dispatcher { contract_address: strk_address };

                stark_token.transfer_from(user_address, self.bank_wallet.read(), bet_amount);

                let platform_fee_amount = bet_amount * PLATFORM_FEE / 100;

                assert(bet_amount > platform_fee_amount, 'Bet amount too small');

                let total_user_share = bet_amount - platform_fee_amount;

                self.bets_count.write(self.bets_count.read() + 1);
                self.total_bet_bank.write(self.total_bet_bank.read() + total_user_share);
                let mut user_odds = current_odds.no_probability;
                if user_choice == false {
                    self.no_total_amount.write(self.no_total_amount.read() + total_user_share);
                } else {
                    user_odds = current_odds.yes_probability;
                    self.yes_total_amount.write(self.yes_total_amount.read() + total_user_share);
                }
                let potential_reward = (total_user_share * 10000) / user_odds;
                dispatcher.mint(user_address, potential_reward);
                let user_bet = UserBet {
                    bet: user_choice,
                    amount: total_user_share,
                    has_claimed: false,
                    claimable_amount: potential_reward,
                    user_odds: current_odds
                };

                refresh_event_odds(ref self, user_choice, total_user_share);
                let address_to_felt: felt252 = user_address
                    .try_into()
                    .expect('failed to convert address');
                self.bets.write(address_to_felt, user_bet);
                let bet_event = BetPlaced { user_bet, timestamp: get_block_timestamp() };
                self.emit(Event::BetPlace(bet_event));
            }
        }

        fn get_bet(self: @ContractState, user_address: ContractAddress) -> UserBet {
            let address_to_felt: felt252 = user_address
                .try_into()
                .expect('failed to convert address');
            self.bets.read(address_to_felt)
        }

        fn has_bet(self: @ContractState, user_address: ContractAddress) -> bool {
            let address_to_felt: felt252 = user_address
                .try_into()
                .expect('failed to convert address');
            let bet = self.bets.read(address_to_felt);
            if bet.amount == 0 {
                false
            } else {
                true
            }
        }

        fn get_event_probability(self: @ContractState) -> Odds {
            self.event_probability.read()
        }

        fn set_event_probability(
            ref self: ContractState, no_initial_prob: u256, yes_initial_prob: u256
        ) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            let initial_probibility = Odds {
                no_probability: no_initial_prob, yes_probability: yes_initial_prob
            };
            self.event_probability.write(initial_probibility);
        }

        fn set_event_outcome(ref self: ContractState, event_result: u8) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            self.event_outcome.write(event_result);
        }

        fn set_yes_token_address(ref self: ContractState, token_address: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            self.yes_share_token_address.write(token_address);
        }

        fn set_no_token_address(ref self: ContractState, token_address: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            self.no_share_token_address.write(token_address);
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
            if is_active == false {
                let event = EventFinished { timestamp: get_block_timestamp() };
                self.emit(Event::EventTimeout(event));
            }
        }

        fn get_time_expiration(self: @ContractState) -> u256 {
            self.time_expiration.read()
        }

        fn set_time_expiration(ref self: ContractState, time_expiration: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            self.time_expiration.write(time_expiration);
        }

        fn get_bet_per_user(self: @ContractState, user_address: ContractAddress) -> UserBet {
            let address_to_felt: felt252 = user_address
                .try_into()
                .expect('failed to convert address');
            let bet = self.bets.read(address_to_felt);
            bet
        }

        fn get_total_bet_bank(self: @ContractState) -> u256 {
            self.total_bet_bank.read()
        }

        fn is_claimable(self: @ContractState, bet_to_claim: UserBet) -> bool {
            assert(self.get_is_active() == false, 'Cant claim, event is running');
            let user_bet = bet_to_claim.bet;
            let mut bet_to_outcome: u8 = 0;
            if user_bet == true {
                bet_to_outcome = 1;
            }
            assert(self.get_event_outcome() == bet_to_outcome, 'Cant claim, bet is wrong');
            assert(bet_to_claim.claimable_amount > 0, 'Nothing to claim');
            true
        }

        fn claimable_amount(self: @ContractState, user_address: ContractAddress) -> u256 {
            let event_outcome = self.get_event_outcome();
            assert(event_outcome != 2, 'No outcome yet');
            let mut balance = 0;
            if event_outcome == 0 {
                let user_no_balance = ERC20Contract::IERC20ContractDispatcher {
                    contract_address: self.no_share_token_address.read()
                }
                    .get_balance_of(user_address);
                assert(user_no_balance > 0, 'No tokens to claim');
                balance = user_no_balance;
            } else {
                let user_yes_balance = ERC20Contract::IERC20ContractDispatcher {
                    contract_address: self.yes_share_token_address.read()
                }
                    .get_balance_of(user_address);
                assert(user_yes_balance > 0, 'No tokens to claim');
                balance = user_yes_balance;
            }
            balance
        }

        fn claim_reward(ref self: ContractState, user_address: ContractAddress) {
            assert(self.get_event_outcome() != 2, 'Event not finished yet');
            assert(get_caller_address() == user_address, 'Not allowed');
            if self.get_event_outcome() == 0 {
                let user_no_balance = ERC20Contract::IERC20ContractDispatcher {
                    contract_address: self.no_share_token_address.read()
                }
                    .get_balance_of(user_address);
                assert(user_no_balance > 0, 'No tokens to exchange');
                let transfer = ERC20Contract::IERC20ContractDispatcher {
                    contract_address: self.no_share_token_address.read()
                }
                    .burn(user_address, user_no_balance);

                let STRK_ADDRESS: ContractAddress = contract_address_const::<
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                >();

                //transfer STRK token to user
                let strk_transfer = IERC20Dispatcher { contract_address: STRK_ADDRESS }
                    .transfer_from(self.get_owner(), user_address, user_no_balance);
                assert(strk_transfer == true, 'STRK transfer failed');

                let claim_event = BetClaimed {
                    event_name: self.get_name(),
                    amount_claimed: user_no_balance,
                    event_outcome: self.get_event_outcome(),
                    timestamp: get_block_timestamp()
                };
                self.emit(Event::Claim(claim_event));
            }

            if self.get_event_outcome() == 1 {
                let user_yes_balance = ERC20Contract::IERC20ContractDispatcher {
                    contract_address: self.yes_share_token_address.read()
                }
                    .get_balance_of(user_address);
                assert(user_yes_balance > 0, 'No tokens to exchange');

                let transfer = ERC20Contract::IERC20ContractDispatcher {
                    contract_address: self.yes_share_token_address.read()
                }
                    .burn(user_address, user_yes_balance);

                let STRK_ADDRESS: ContractAddress = contract_address_const::<
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                >();

                //transfer STRK token to user
                let strk_transfer = IERC20Dispatcher { contract_address: STRK_ADDRESS }
                    .transfer_from(
                        self.get_owner(), user_address, user_yes_balance
                    ); //check this line  
                assert(strk_transfer == true, 'STRK transfer failed');
                //let bet_event = BetPlaced { user_bet, timestamp: get_block_timestamp() };
                let claim_event = BetClaimed {
                    event_name: self.get_name(),
                    amount_claimed: user_yes_balance,
                    event_outcome: self.get_event_outcome(),
                    timestamp: get_block_timestamp()
                };
                self.emit(Event::Claim(claim_event));
            }
        }
    }

    //internal function, no visibility from outside
    fn refresh_event_odds(ref self: ContractState, user_choice: bool, bet_amount: u256) {
        ///si calcule trop sensible, on peut ajouter un alpha de 0.75-0.85 pour lisser (1000000000000000000 = 1 STRK)
        let initial_yes_prob = self.get_event_probability().yes_probability;
        let initial_no_prob = self.get_event_probability().no_probability;

        let scale_factor: u256 = 1000000000000000000; // 1e18

        let total_yes = self.yes_total_amount.read();
        let total_no = self.no_total_amount.read();

        let initial_yes_amount = initial_yes_prob * scale_factor;
        let initial_no_amount = initial_no_prob * scale_factor;

        let updated_total_yes = if user_choice {
            total_yes + bet_amount
        } else {
            total_yes
        };

        let updated_total_no = if !user_choice {
            total_no + bet_amount
        } else {
            total_no
        };

        let adjusted_total_yes = updated_total_yes + initial_yes_amount;
        let adjusted_total_no = updated_total_no + initial_no_amount;

        let adjusted_total_bet = adjusted_total_yes + adjusted_total_no;

        let new_yes_prob = (adjusted_total_yes * 10000) / adjusted_total_bet;
        let new_no_prob = (adjusted_total_no * 10000) / adjusted_total_bet;

        let updated_odds = Odds { no_probability: new_no_prob, yes_probability: new_yes_prob, };
        self.event_probability.write(updated_odds);

        self.yes_total_amount.write(updated_total_yes);
        self.no_total_amount.write(updated_total_no);
    }
}

