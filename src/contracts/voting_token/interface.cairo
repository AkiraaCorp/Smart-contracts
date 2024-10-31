use starknet::ContractAddress;

#[starknet::interface]
pub trait IVotingToken<TContractState> {
    fn controled_transfer_from(
        ref self: TContractState, sender: ContractAddress, amount: u256, recipient: ContractAddress
    );
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
    fn balance_of(ref self: TContractState, account: ContractAddress) -> u256;
    fn supply_total(ref self: TContractState) -> u256;
}
