/// Do the function that initialize and refresh quotation rate after each bet

#[starknet::component]
pub mod OddsComputeComponent {
    use core::starknet::contract_address::ContractAddress;
    use starknet::{get_caller_address, get_contract_address};

    #[storage]
    pub struct Storage {
        total_yes: u128,
        total_no: u128,
    }

    #[starknet::interface]
    trait OddsComputeTrait<TContractState> {
        fn odds_refresh(ref self: TContractState, amount: u128, bet_on_yes: bool) -> (u128, u128);
    }

    #[embeddable_as(OddsComputeImpl)]
    impl OddsComputeExternal<
        TContractState, +Drop<TContractState>, +HasComponent<TContractState>
    > of OddsComputeTrait<ComponentState<TContractState>> {
        fn odds_refresh(ref self: ComponentState<TContractState>, amount: u128, bet_on_yes: bool) -> (u128, u128) {
            if bet_on_yes {
                self.total_yes.write(self.total_yes.read() + amount);
            } else {
                self.total_no.write(self.total_no.read() + amount);
            }
        
            let total_bets = self.total_yes.read() + self.total_no.read();
            let prob_yes = self.total_yes.read() / total_bets;
            let prob_no = self.total_no.read() / total_bets;
        
            // Here we use an overhound of 10%, so 1.10
            let overround = 110_128;
            let odds_yes = overround / prob_yes;
            let odds_no = overround / prob_no;

            (odds_yes, odds_no)
        }
    }
}