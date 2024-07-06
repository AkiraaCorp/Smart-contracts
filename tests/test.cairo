use snforge_std::{declare, ContractClassTrait, start_cheat_caller_address};
use starknet::contract_address::contract_address_const;
use starknet::ContractAddress;
use akira_smart_contract::contracts::bet::IEventBettingDispatcher;
use akira_smart_contract::contracts::bet::IEventBettingDispatcherTrait;
use akira_smart_contract::ERC20::ERC20Contract::IERC20ContractDispatcher;
use akira_smart_contract::ERC20::ERC20Contract::IERC20ContractDispatcherTrait;

fn deploy_contract() -> (IEventBettingDispatcher, ContractAddress) {
    let name: ByteArray = "EventBetting";
    let contract = declare(name).unwrap();
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let token_no_address: ContractAddress = contract_address_const::<'token_no_address'>();
    let token_yes_address: ContractAddress = contract_address_const::<'token_yes_address'>();
    let bank_wallet: ContractAddress = contract_address_const::<'blank_wallet'>();
    let (contract_address, _) = contract
        .deploy(
            @array![
                owner.into(),
                token_no_address.into(),
                token_yes_address.into(),
                bank_wallet.into(),
                'test'.into()
            ]
        )
        .unwrap();
    let dispatcher = IEventBettingDispatcher { contract_address };
    (dispatcher, contract_address)
}

#[cfg(test)]
mod test {
    use snforge_std::{declare, ContractClassTrait, start_cheat_caller_address};
    use starknet::ContractAddress;
    use akira_smart_contract::contracts::bet::IEventBettingDispatcher;
    use akira_smart_contract::contracts::bet::IEventBettingDispatcherTrait;
    use starknet::contract_address::contract_address_const;
    use super::deploy_contract;
    use akira_smart_contract::ERC20::ERC20Contract::IERC20ContractDispatcher;
    use akira_smart_contract::ERC20::ERC20Contract::IERC20ContractDispatcherTrait;
    use openzeppelin::token::erc20::interface::{
        ERC20ABI, ERC20ABIDispatcher, ERC20ABIDispatcherTrait
    };
    use openzeppelin::utils::serde::SerializedAppend;

    #[test]
    fn get_owner_test() {
        let owner: ContractAddress = contract_address_const::<'owner'>();
        let (dispatcher, _contract_address) = deploy_contract();
        assert_eq!(dispatcher.get_owner(), owner);
    }

    #[test]
    #[should_panic]
    fn store_and_get_name_panic() {
        let (dispatcher, contract_address) = deploy_contract();
        let contract_name = 'test';
        dispatcher.store_name(contract_name);
        assert_eq!(dispatcher.get_name(contract_address), contract_name);
    }

    #[test]
    fn store_and_get_name() {
        let (dispatcher, contract_address) = deploy_contract();
        let contract_name = 'test';
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher.store_name(contract_name);
        assert_eq!(dispatcher.get_name(contract_address), contract_name);
    }

    #[test]
    #[should_panic]
    fn is_active_test_not_owner_panic() {
        let (dispatcher, _contract_address) = deploy_contract();
        dispatcher.set_is_active(true);
    }

    #[test]
    fn is_active_test_true() {
        let (dispatcher, contract_address) = deploy_contract();
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher.set_is_active(true);
        assert_eq!(dispatcher.get_is_active(), true);
    }

    #[test]
    fn is_active_test_false() {
        let (dispatcher, contract_address) = deploy_contract();
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher.set_is_active(false);
        assert_eq!(dispatcher.get_is_active(), false);
    }

    #[test]
    #[should_panic]
    fn set_time_expiration_test_panic() {
        let (dispatcher, _contract_address) = deploy_contract();
        dispatcher.set_time_expiration(200);
    }

    #[test]
    fn set_time_expiration_test() {
        let (dispatcher, contract_address) = deploy_contract();
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher.set_time_expiration(200);
        assert_eq!(dispatcher.get_time_expiration(), 200);
    }

    #[test]
    // #[should_panic]
    fn ERC20_test() {
        let mut calldata: Array<felt252> = array![];
        let name: ByteArray = "ERC20Contract";
        let contract = declare(name).unwrap();
        let owner: ContractAddress = contract_address_const::<'owner'>();
        let name_token = 0;
        let initial_supply: u256 = 200;
        let initial_supply_low = initial_supply.low;
        let initial_supply_high = initial_supply.high;
        calldata.append(initial_supply_low.into());
        calldata.append(initial_supply_high.into());
        calldata.append(owner.into());
        calldata.append(owner.into());
        calldata.append(name_token.into());
        let (contract_address, _) = contract.deploy(@calldata).unwrap();
        // let dispatcherContract = IERC20ContractDispatcher { contract_address };
        // start_cheat_caller_address(contract_address, owner);
        let dispatcherMeta = ERC20ABIDispatcher { contract_address };
        // let sender: ContractAddress = contract_address_const::<'sender'>();
        // let recipient1 = contract_address_const::<'recipient1'>();
        assert_eq!(dispatcherMeta.name(), "No");
    // dispatcherContract.transfer_from_controled(owner, 50, recipient1);
    }
}
