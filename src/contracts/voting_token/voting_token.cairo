#[starknet::contract]
pub mod ERC20Contract {
    use akira::contracts::voting_token::interface::IVotingToken;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StorageMapReadAccess};

    //
    // Components
    //

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    //
    // Constants
    //

    const MINTER_ROLE: felt252 = selector!("MINTER_ROLE");
    const BURNER_ROLE: felt252 = selector!("BURNER_ROLE");
    const TRANSFER_ROLE: felt252 = selector!("TRANSFER_ROLE");

    //
    // Storage
    //

    #[storage]
    struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }

    //
    // Events
    //

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    //
    // Constructor
    //

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_supply_low: u128,
        initial_supply_high: u128,
        recipient: ContractAddress,
        owner: ContractAddress,
        name: u8
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(MINTER_ROLE, owner);
        self.accesscontrol._grant_role(BURNER_ROLE, owner);
        self.accesscontrol._grant_role(TRANSFER_ROLE, owner);
        let mut token_name: ByteArray = "No";
        let mut symbol: ByteArray = "NO";
        if (name != 0) {
            token_name = "Yes";
            symbol = "YES";
        }
        self.erc20.initializer(token_name, symbol);

        let initial_supply = u256 { low: initial_supply_low, high: initial_supply_high, };
        self.erc20.mint(recipient, initial_supply);
    }

    //
    // Voting Token impl
    //

    #[abi(embed_v0)]
    impl ERC20Contract of IVotingToken<ContractState> {
        fn controled_transfer_from(
            ref self: ContractState, sender: ContractAddress, amount: u256, recipient: ContractAddress
        ) {
            self.accesscontrol.assert_only_role(TRANSFER_ROLE);
            self.erc20._transfer(sender, recipient, amount);
        }

        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.accesscontrol.assert_only_role(MINTER_ROLE);
            self.erc20.mint(recipient, amount);
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.accesscontrol.assert_only_role(BURNER_ROLE);
            self.erc20.burn(account, amount);
        }

        fn balance_of(ref self: ContractState, account: ContractAddress) -> u256 {
            self.erc20.ERC20_balances.read(account)
        }

        fn supply_total(ref self: ContractState) -> u256 {
            self.erc20.ERC20_total_supply.read()
        }
    }
}
