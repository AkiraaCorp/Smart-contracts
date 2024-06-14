/// Do the function that initialize and refresh quotation rate after each bet

#[starknet::component]
pub mod odds_compute {
    use core::starknet::contract_address::ContractAddress;

    struct BetState {
        total_yes: u128,
        total_no: u128,
    }

    pub fn refresh_odds(bet_state: &mut BetState, amount: u128, bet_on_yes: bool) -> (f64, f64) {
        if bet_on_yes {
            bet_state.total_yes += amount;
        } else {
            bet_state.total_no += amount;
        }

        let total_bets = bet_state.total_yes + bet_state.total_no;
        let prob_yes = bet_state.total_yes as f64 / total_bets as f64;
        let prob_no = bet_state.total_no as f64 / total_bets as f64;

        // Here we use an overhound of 10%, so 1.10
        let overround = 1.10;
        let odds_yes = overround / prob_yes;
        let odds_no = overround / prob_no;

        (odds_yes, odds_no)
    }
}