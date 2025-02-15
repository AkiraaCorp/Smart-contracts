#[starknet::contract]
pub mod EventBetting {
    use akira::contracts::bet::interface::{IEventBetting, UserBet, Odds};
    use akira::contracts::voting_token::interface::{IVotingTokenDispatcher, IVotingTokenDispatcherTrait};
    use core::array::ArrayTrait;
    use core::num::traits::zero::Zero;
    use core::option::OptionTrait;
    use core::starknet::event::EventEmitter;
    use core::traits::TryInto;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::Map;
    use starknet::storage::StoragePathEntry;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait, MutableVecTrait};
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_contract_address, get_block_timestamp,
        contract_address_const, syscalls
    };

    const BET_LIMIT: u256 = 1000000000000000000000; //1000 STARK
    #[storage]
    struct Storage {
        name: felt252,
        owner: ContractAddress,
        total_names: u128,
        bets: Map<felt252, Vec<UserBet>>,
        bets_count: u32,
        event_probability: Odds,
        yes_count: u128,
        yes_total_amount: u256,
        no_count: u128,
        no_total_amount: u256,
        total_bet_bank: u256,
        event_outcome: u8,
        is_active: bool,
        time_expiration: u256,
        no_share_token_address: ContractAddress,
        yes_share_token_address: ContractAddress,
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
        user_address: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BetClaimed {
        event_address: ContractAddress,
        user_address: ContractAddress,
        amount_claimed: u256,
        event_outcome: u8,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EventFinished {
        event_address: ContractAddress,
        event_outcome: u8,
        timestamp: u64,
    }

    #[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Hash)]
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
        event_name: felt252
    ) {
        self.owner.write(owner);
        self.no_share_token_address.write(token_no_address);
        self.yes_share_token_address.write(token_yes_adress);
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

    #[abi(embed_v0)]
    impl EventBetting of IEventBetting<ContractState> {
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

        fn place_bet(ref self: ContractState, user_address: ContractAddress, bet_amount: u256, bet: bool) {
            assert(self.get_is_active() == true, 'This event is not active');
            assert(self.has_bet_limit(user_address, bet_amount) == false, 'User already bet to limit');
            assert(self.get_event_outcome() == 2, 'Event already finished');
            let odds = self.get_event_probability();
            let current_odds = Odds { no_probability: odds.no_probability, yes_probability: odds.yes_probability };
            let user_choice = bet;
            if user_choice == false {
                let dispatcher = IVotingTokenDispatcher { contract_address: self.no_share_token_address.read() };
                let strk_address: ContractAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                    .try_into()
                    .unwrap();
                //STRK deposit
                let stark_token = IERC20Dispatcher { contract_address: strk_address };

                let total_user_share = bet_amount;
                stark_token.transfer_from(user_address, self.get_owner(), total_user_share);

                self.bets_count.write(self.bets_count.read() + 1);
                self.total_bet_bank.write(self.total_bet_bank.read() + total_user_share);
                let mut user_odds = current_odds.no_probability;
                self.no_total_amount.write(self.no_total_amount.read() + total_user_share);

                let potential_reward = (total_user_share * 10000) / user_odds;
                dispatcher.mint(user_address, potential_reward);
                let user_bet = UserBet {
                    bet: user_choice,
                    amount: total_user_share,
                    has_claimed: false,
                    claimable_amount: potential_reward,
                    user_odds: current_odds
                };

                self._refresh_event_odds(user_choice, total_user_share);
                let address_to_felt: felt252 = user_address.try_into().expect('failed to convert address');
                self.bets.entry(address_to_felt).append().write(user_bet);
                self.emit(Event::BetPlace(BetPlaced { user_bet, user_address, timestamp: get_block_timestamp() }));
            } else {
                let dispatcher = IVotingTokenDispatcher { contract_address: self.yes_share_token_address.read() };
                let strk_address: ContractAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                    .try_into()
                    .unwrap();
                //STRK deposit
                let stark_token = IERC20Dispatcher { contract_address: strk_address };

                let total_user_share = bet_amount;
                stark_token.transfer_from(user_address, self.get_owner(), total_user_share);

                self.bets_count.write(self.bets_count.read() + 1);
                self.total_bet_bank.write(self.total_bet_bank.read() + total_user_share);
                let user_odds = current_odds.yes_probability;
                self.yes_total_amount.write(self.yes_total_amount.read() + total_user_share);

                let potential_reward = (total_user_share * 10000) / user_odds;
                dispatcher.mint(user_address, potential_reward);
                let user_bet = UserBet {
                    bet: user_choice,
                    amount: total_user_share,
                    has_claimed: false,
                    claimable_amount: potential_reward,
                    user_odds: current_odds
                };

                self._refresh_event_odds(user_choice, total_user_share);
                let address_to_felt: felt252 = user_address.try_into().expect('failed to convert address');
                self.bets.entry(address_to_felt).append().write(user_bet);
                self.emit(Event::BetPlace(BetPlaced { user_bet, user_address, timestamp: get_block_timestamp() }));
            }
        }

        fn get_bet(self: @ContractState, user_address: ContractAddress) -> Array<UserBet> {
            let address_to_felt: felt252 = user_address.try_into().expect('failed to convert address');
            let bets = self.bets.entry(address_to_felt);
            let mut bet_array: Array<UserBet> = array![];
            let vec_lenght = bets.len();
            let mut i = 0;
            loop {
                if i >= vec_lenght {
                    break;
                }
                let at_index = bets.at(i).read();
                bet_array.append(at_index);
            };
            bet_array
        }

        fn has_bet_limit(self: @ContractState, user_address: ContractAddress, bet_amount: u256) -> bool {
            let address_to_felt: felt252 = user_address.try_into().expect('failed to convert address');
            let bets = self.bets.entry(address_to_felt);
            let vec_lenght = bets.len();
            let mut total_amount: u256 = 0;
            let mut i = 0;
            loop {
                if i >= vec_lenght {
                    break;
                }
                let at_index = bets.at(i).amount.read();
                total_amount = total_amount + at_index;
                i = i + 1;
            };
            let new_total_amount = total_amount + bet_amount;
            if (new_total_amount <= BET_LIMIT) {
                false
            } else {
                true
            }
        }

        fn get_event_probability(self: @ContractState) -> Odds {
            self.event_probability.read()
        }

        fn set_event_probability(ref self: ContractState, no_initial_prob: u256, yes_initial_prob: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            let initial_probibility = Odds { no_probability: no_initial_prob, yes_probability: yes_initial_prob };
            self.event_probability.write(initial_probibility);
        }

        fn set_event_outcome(ref self: ContractState, event_result: u8) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            self.event_outcome.write(event_result);
            if event_result != 2 {
                let event = EventFinished { timestamp: get_block_timestamp(), event_outcome: event_result, event_address: get_contract_address() };
                self.emit(Event::EventTimeout(event));
            }
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
        }

        fn get_time_expiration(self: @ContractState) -> u256 {
            self.time_expiration.read()
        }

        fn set_time_expiration(ref self: ContractState, time_expiration: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            self.time_expiration.write(time_expiration);
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
                let user_no_balance = IVotingTokenDispatcher { contract_address: self.no_share_token_address.read() }
                    .balance_of(user_address);
                assert(user_no_balance > 0, 'No tokens to claim');
                balance = user_no_balance;
            } else {
                let user_yes_balance = IVotingTokenDispatcher { contract_address: self.yes_share_token_address.read() }
                    .balance_of(user_address);
                assert(user_yes_balance > 0, 'No tokens to claim');
                balance = user_yes_balance;
            }
            balance
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can do that');
            assert(!new_class_hash.is_zero(), 'Class hash cannot be zero');
            syscalls::replace_class_syscall(new_class_hash).unwrap();
        }

        fn claim_reward(ref self: ContractState, user_address: ContractAddress) {
            assert(self.get_event_outcome() != 2, 'Event not finished yet');
            assert(get_caller_address() == user_address, 'Not allowed');
            if self.get_event_outcome() == 0 {
                let user_no_balance = IVotingTokenDispatcher { contract_address: self.no_share_token_address.read() }
                    .balance_of(user_address);
                assert(user_no_balance > 0, 'No tokens to exchange');
                IVotingTokenDispatcher { contract_address: self.no_share_token_address.read() }
                    .burn(user_address, user_no_balance);

                let STRK_ADDRESS: ContractAddress = contract_address_const::<
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                >();

                //transfer STRK token to user
                let strk_transfer = IERC20Dispatcher { contract_address: STRK_ADDRESS }
                    .transfer(user_address, user_no_balance);
                assert(strk_transfer == true, 'STRK transfer failed');

                let claim_event = BetClaimed {
                    event_address: get_contract_address(),
                    user_address: user_address,
                    amount_claimed: user_no_balance,
                    event_outcome: self.get_event_outcome(),
                    timestamp: get_block_timestamp()
                };
                self.emit(Event::Claim(claim_event));
            }

            if self.get_event_outcome() == 1 {
                let user_yes_balance = IVotingTokenDispatcher { contract_address: self.yes_share_token_address.read() }
                    .balance_of(user_address);
                assert(user_yes_balance > 0, 'No tokens to exchange');

                IVotingTokenDispatcher { contract_address: self.yes_share_token_address.read() }
                    .burn(user_address, user_yes_balance);

                let STRK_ADDRESS: ContractAddress = contract_address_const::<
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                >();

                //transfer STRK token to user
                let strk_transfer = IERC20Dispatcher { contract_address: STRK_ADDRESS }
                    .transfer(user_address, user_yes_balance);
                assert(strk_transfer == true, 'STRK transfer failed');
                let claim_event = BetClaimed {
                    event_address: get_contract_address(),
                    user_address: user_address,
                    amount_claimed: user_yes_balance,
                    event_outcome: self.get_event_outcome(),
                    timestamp: get_block_timestamp()
                };
                self.emit(Event::Claim(claim_event));
            }
        }

        fn withdraw(
            ref self: ContractState, token_to_withdraw: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let owner = self.owner.read();
            assert(get_caller_address() == owner, 'Only owner can proceed');
            IERC20Dispatcher { contract_address: token_to_withdraw }.transfer(recipient, amount)
        }
    }

    //internal function, no visibility from outside
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _refresh_event_odds(ref self: ContractState, user_choice: bool, bet_amount: u256) {
            ///si calcule trop sensible, on peut ajouter un alpha de 0.75-0.85 pour lisser
            let initial_yes_prob = self.get_event_probability().yes_probability;
            let initial_no_prob = self.get_event_probability().no_probability;

            let scale_factor: u256 = 1_000_000_000_000_000_000; // 1e18 (1000000000000000000 = 1 STRK)

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
}
