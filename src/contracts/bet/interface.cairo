use starknet::ContractAddress;

#[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Hash)]
pub struct UserBet {
    pub bet: bool, // No = false, Yes = true
    pub amount: u256,
    pub has_claimed: bool,
    pub claimable_amount: u256,
    pub user_odds: Odds,
}

#[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Hash)]
pub struct Odds {
    pub no_probability: u256,
    pub yes_probability: u256,
}

#[starknet::interface]
pub trait IEventBetting<TContractState> {
    fn store_name(ref self: TContractState, name: felt252);
    fn get_name(self: @TContractState) -> felt252;
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn place_bet(ref self: TContractState, user_address: ContractAddress, bet_amount: u256, bet: bool);
    fn get_bet(self: @TContractState, user_address: ContractAddress) -> Array<UserBet>;
    fn has_bet_limit(self: @TContractState, user_address: ContractAddress, bet_amount: u256) -> bool;
    fn get_event_probability(self: @TContractState) -> Odds;
    fn set_event_probability(ref self: TContractState, no_initial_prob: u256, yes_initial_prob: u256);
    fn set_event_outcome(ref self: TContractState, event_result: u8);
    fn set_yes_token_address(ref self: TContractState, token_address: ContractAddress);
    fn set_no_token_address(ref self: TContractState, token_address: ContractAddress);
    fn get_event_outcome(self: @TContractState) -> u8;
    fn get_is_active(self: @TContractState) -> bool;
    fn set_is_active(ref self: TContractState, is_active: bool);
    fn get_time_expiration(self: @TContractState) -> u256;
    fn set_time_expiration(ref self: TContractState, time_expiration: u256);
    fn get_total_bet_bank(self: @TContractState) -> u256;
    fn upgrade(ref self: TContractState, new_class_hash: starknet::ClassHash);
    fn is_claimable(self: @TContractState, bet_to_claim: UserBet) -> bool;
    fn claimable_amount(self: @TContractState, user_address: ContractAddress) -> u256;
    fn claim_reward(ref self: TContractState, user_address: ContractAddress);
    fn withdraw(
        ref self: TContractState, token_to_withdraw: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
}
