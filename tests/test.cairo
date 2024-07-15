use akira_smart_contract::ERC20::ERC20Contract::{
    IERC20ContractDispatcher, IERC20ContractDispatcherTrait
};
use akira_smart_contract::contracts::bet::EventBetting::{
    to_u64, log_cost, cost_diff, from_u64, print_fixed
};
use akira_smart_contract::contracts::bet::{IEventBettingDispatcher, IEventBettingDispatcherTrait};
use cubit::f64::{math::ops::{ln, exp}, types::fixed::{Fixed, FixedTrait}};
use openzeppelin::token::erc20::interface::{ERC20ABI, ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{declare, ContractClassTrait, start_cheat_caller_address};
use starknet::ContractAddress;
use starknet::contract_address::contract_address_const;

fn deploy_event_betting() -> (IEventBettingDispatcher, ContractAddress) {
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

fn deploy_erc20(
    name: ByteArray, initial_supply: u256, name_token: u8,
) -> (ERC20ABIDispatcher, IERC20ContractDispatcher, ContractAddress) {
    let mut calldata: Array<felt252> = array![];
    let contract = declare(name).unwrap();
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'owner'>();
    let initial_supply_low = initial_supply.low;
    let initial_supply_high = initial_supply.high;
    calldata.append(initial_supply_low.into());
    calldata.append(initial_supply_high.into());
    calldata.append(recipient.into());
    calldata.append(owner.into());
    calldata.append(name_token.into());
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    let dispatcherContract = IERC20ContractDispatcher { contract_address };
    let dispatcherMeta = ERC20ABIDispatcher { contract_address };
    (dispatcherMeta, dispatcherContract, contract_address)
}

#[cfg(test)]
mod test {
    use akira_smart_contract::ERC20::ERC20Contract::{
        IERC20ContractDispatcher, IERC20ContractDispatcherTrait
    };

    // #[test]
    // fn log_cost_pass() {

    // }

    // #[test]
    // fn cost_diff_pass() {

    // }

    use akira_smart_contract::contracts::bet::EventBetting::{to_u64, log_cost, cost_diff, from_u64};
    use akira_smart_contract::contracts::bet::{
        IEventBettingDispatcher, IEventBettingDispatcherTrait
    };
    use openzeppelin::token::erc20::interface::{
        ERC20ABI, ERC20ABIDispatcher, ERC20ABIDispatcherTrait
    };
    use snforge_std::{ContractClassTrait, start_cheat_caller_address};
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use super::{deploy_event_betting, deploy_erc20};

    #[test]
    fn get_owner_test() {
        let owner: ContractAddress = contract_address_const::<'owner'>();
        let (dispatcher, _contract_address) = deploy_event_betting();
        assert_eq!(dispatcher.get_owner(), owner);
    }

    #[test]
    #[should_panic]
    fn store_and_get_name_panic() {
        let (dispatcher, contract_address) = deploy_event_betting();
        let contract_name = 'test';
        dispatcher.store_name(contract_name);
        assert_eq!(dispatcher.get_name(contract_address), contract_name);
    }

    #[test]
    fn store_and_get_name() {
        let (dispatcher, contract_address) = deploy_event_betting();
        let contract_name = 'test';
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher.store_name(contract_name);
        assert_eq!(dispatcher.get_name(contract_address), contract_name);
    }

    #[test]
    #[should_panic]
    fn is_active_test_not_owner_panic() {
        let (dispatcher, _contract_address) = deploy_event_betting();
        dispatcher.set_is_active(true);
    }

    #[test]
    fn is_active_test_true() {
        let (dispatcher, contract_address) = deploy_event_betting();
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher.set_is_active(true);
        assert_eq!(dispatcher.get_is_active(), true);
    }

    #[test]
    fn is_active_test_false() {
        let (dispatcher, contract_address) = deploy_event_betting();
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher.set_is_active(false);
        assert_eq!(dispatcher.get_is_active(), false);
    }

    #[test]
    #[should_panic]
    fn set_time_expiration_test_panic() {
        let (dispatcher, _contract_address) = deploy_event_betting();
        dispatcher.set_time_expiration(200);
    }

    #[test]
    fn set_time_expiration_test() {
        let (dispatcher, contract_address) = deploy_event_betting();
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher.set_time_expiration(200);
        assert_eq!(dispatcher.get_time_expiration(), 200);
    }

    #[test]
    #[should_panic]
    fn ERC20_test_transfert_from_panic() {
        let (dispatcher_ABI, _dispatcher_contract, _contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();
        let recipient1 = contract_address_const::<'recipient1'>();
        dispatcher_ABI.transfer_from(owner, recipient1, 50);
    }

    #[test]
    fn ERC20_test_mint() {
        let (_dispatcher_ABI, dispatcher_contract, contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher_contract.mint(owner, 50);
        assert_eq!(dispatcher_contract.get_balance_of(owner), 250);
    }

    #[test]
    #[should_panic]
    fn ERC20_test_mint_not_minter() {
        let (_dispatcher_ABI, dispatcher_contract, _contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();
        dispatcher_contract.mint(owner, 50);
        assert_eq!(dispatcher_contract.get_balance_of(owner), 250);
    }

    #[test]
    fn ERC20_test_burn() {
        let (_dispatcher_ABI, dispatcher_contract, contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher_contract.burn(owner, 50);
        assert_eq!(dispatcher_contract.supply_total(), 150);
    }

    #[test]
    #[should_panic]
    fn ERC20_test_burn_not_burner() {
        let (_dispatcher_ABI, dispatcher_contract, _contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();
        dispatcher_contract.burn(owner, 50);
        assert_eq!(dispatcher_contract.supply_total(), 150);
    }

    #[test]
    #[should_panic]
    fn ERC20_test_burn_insufficient_balance() {
        let (_dispatcher_ABI, dispatcher_contract, contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        dispatcher_contract.burn(owner, 250);
        assert_eq!(dispatcher_contract.supply_total(), 150);
    }

    #[test]
    fn ERC20_test_controled_transfert_from() {
        let (_dispatcher_ABI, dispatcher_contract, contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        let recipient = contract_address_const::<'recipient'>();
        dispatcher_contract.controled_transfer_from(owner, 50, recipient);
        assert_eq!(dispatcher_contract.get_balance_of(recipient), 50);
    }

    #[test]
    #[should_panic]
    fn ERC20_test_controled_transfert_from_insufficient_balance() {
        let (_dispatcher_ABI, dispatcher_contract, contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();
        start_cheat_caller_address(contract_address, owner);
        let recipient1 = contract_address_const::<'recipient1'>();
        let recipient2 = contract_address_const::<'recipient2'>();
        dispatcher_contract.controled_transfer_from(owner, 50, recipient1);
        dispatcher_contract.controled_transfer_from(recipient1, 100, recipient2);
    }

    #[test]
    #[should_panic]
    fn ERC20_test_controled_transfert_from_not_owner() {
        let (_dispatcher_ABI, dispatcher_contract, _contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();
        let recipient1 = contract_address_const::<'recipient1'>();
        dispatcher_contract.controled_transfer_from(owner, 50, recipient1);
    }


    ///odds tests
    #[test]
    fn odds_refresh_test_pass() {
        let (dispatcher, _contract_address) = deploy_event_betting();
        let (_dispatcher_ABI, dispatcher_contract, contract_address) = deploy_erc20(
            "ERC20Contract", 200, 0
        );
        let owner: ContractAddress = contract_address_const::<'owner'>();

        let no_odds: u256 = 5714;
        let yes_odds: u256 = 4000;

        dispatcher.set_event_probability(no_odds, yes_odds);
        let current_odds = dispatcher.get_event_probability();
        let current_no_prob = current_odds.no_probability;
        let current_yes_prob = current_odds.yes_probability;

        println!("The value of no probability is : {}", current_no_prob);
        println!("The value of yes probability is : {}", current_yes_prob);
        assert_eq!(current_no_prob, 5714);
        assert_eq!(current_yes_prob, 4000);

        let bet_amount = 2500;
        let user_choice = true;

        dispatcher.refresh_event_odds(user_choice, bet_amount);

        let mut new_odds = dispatcher.get_event_probability();
        let mut new_no_prob = new_odds.no_probability;
        let mut new_yes_prob = new_odds.yes_probability;

        println!("The value of new no probability is : {}", new_no_prob);
        println!("The value of new yes probability is : {}", new_yes_prob);
        assert_eq!(new_no_prob, 4678);
        assert_eq!(new_yes_prob, 5321);

        let re_bet = 3000;
        let new_user_voice = false;

        dispatcher.refresh_event_odds(user_choice, bet_amount);

        new_odds = dispatcher.get_event_probability();
        new_no_prob = new_odds.no_probability;
        new_yes_prob = new_odds.yes_probability;

        println!("The value of new no probability is : {}", new_no_prob);
        println!("The value of new yes probability is : {}", new_yes_prob);
        assert_eq!(new_no_prob, 3118);
        assert_eq!(new_yes_prob, 6881);
    }
}
