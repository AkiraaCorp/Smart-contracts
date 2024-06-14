//define a constructor and an the contract blueprint first here
use starknet::ContractAddress;

#[starknet::interface]
pub trait IEventBetting<TContractState> {
    fn store_name(
        ref self: TContractState, name: felt252, registration_type: EventBetting::RegistrationType
    );
    fn get_name(self: @TContractState, address: ContractAddress) -> felt252;
    fn get_owner(self: @TContractState) -> EventBetting::Person;
    fn place_bet(ref self: TContractState, bet: EventBetting::Vote, amount: u256);
    fn get_bet(self: @TContractState, user_address: ContractAddress) -> (EventBetting::Vote, u256);
}

#[starknet::contract]
mod EventBetting {
    use starknet::{ContractAddress, get_caller_address, storage_access::StorageBaseAddress};

    // for the rate
    type odds = u8;

    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub enum Vote {
      None,
      Yes: odds,
      No: odds,
    }

    #[storage]
    struct Storage {
        names: LegacyMap::<ContractAddress, felt252>,
        owner: Person,
        registration_type: LegacyMap::<ContractAddress, RegistrationType>,
        total_names: u128,
        bets: LegacyMap<(ContractAddress, Vote), u256>,
        user_votes: LegacyMap<ContractAddress, Vote>,
        yes_count: u128,
        no_count: u128,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        StoredName: StoredName,
        BetPlaced: BetPlaced,
    }

    #[derive(Drop, starknet::Event)]
    struct StoredName {
        #[key]
        user: ContractAddress,
        name: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct BetPlaced {
        #[key]
        user: ContractAddress,
        amount: u256,
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

        fn place_bet(ref self: ContractState, bet: Vote, amount: u256) {
            let caller: ContractAddress = get_caller_address();
            self.bets.write((caller, bet), amount);
            self.user_votes.write(caller, bet);

            match bet {
                Vote::Yes => {
                    let yes_count = self.yes_count.read();
                    self.yes_count.write(yes_count + 1);
                },
                Vote::No => {
                    let no_count = self.no_count.read();
                    self.no_count.write(no_count + 1);
                },
                _ => {}
            }

            self.emit(BetPlaced { user: caller, amount: amount });
        }

        fn get_bet(self: @ContractState, user_address: ContractAddress) -> (Vote, u256) {
            let vote = self.user_votes.read(user_address);
            let amount = self.bets.read((user_address, vote.clone()));
            (vote, amount)
        }
    }

    #[external(v0)]
    fn get_contract_name(self: @ContractState) -> felt252 {
        'Event number 1'
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _store_name(
            ref self: ContractState,
            user: ContractAddress,
            name: felt252,
            registration_type: RegistrationType
        ) {
            let total_names = self.total_names.read();
            self.names.write(user, name);
            self.registration_type.write(user, registration_type);
            self.total_names.write(total_names + 1);
            self.emit(StoredName { user: user, name: name });
        }
    }

    fn get_owner_storage_address(self: @ContractState) -> StorageBaseAddress {
        self.owner.address()
    }
}