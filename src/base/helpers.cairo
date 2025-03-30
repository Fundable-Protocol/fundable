pub mod Helpers {
    use core::num::traits::Pow;

    /// @dev Descales the provided `amount` from 18 decimals fixed-point number to token's decimals
    /// number.
    pub fn descale_amount(amount: u256, decimals: u8) -> u256 {
        if decimals == 18 {
            return amount;
        }

        let scale_factor = 10_u256.pow(18 - decimals.into());
        return amount / scale_factor;
    }

    /// @dev Scales the provided `amount` from token's decimals number to 18 decimals fixed-point
    /// number.
    pub fn scale_amount(amount: u256, decimals: u8) -> u256 {
        if decimals == 18 {
            return amount;
        }

        let scale_factor = 10_u256.pow(18 - decimals.into());
        return amount * scale_factor;
    }
}
