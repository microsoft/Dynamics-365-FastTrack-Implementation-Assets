namespace SampleConsoleAppAuthorizePayment
{
    public class PaymentResponse
    {
        public AdditionalData? AdditionalData { get; set; }
        public FraudResult? FraudResult { get; set; }
        public string? PspReference { get; set; }
        public string ResultCode { get; set; } = "";
        public Amount? Amount { get; set; }
        public string? MerchantReference { get; set; }
        public PaymentMethod? PaymentMethod { get; set; }
    }

    public class AdditionalData
    {
        public string? ScaExemptionRequested { get; set; }
        public string? RefusalReasonRaw { get; set; }
        public string? Eci { get; set; }
        public string? AcquirerAccountCode { get; set; }
        public string? Xid { get; set; }
        public string? ThreeDAuthenticated { get; set; }
        public string? PaymentMethodVariant { get; set; }
        public string? IssuerBin { get; set; }
        public string? PayoutEligible { get; set; }
        public string? FraudManualReview { get; set; }
        public string? ThreeDOffered { get; set; }
        public string? ThreeDOfferedResponse { get; set; }
        public string? AuthorisationMid { get; set; }
        public string? BankAccountIban { get; set; }
        public string? Cavv { get; set; }
        public string? BankAccountOwnerName { get; set; }
        public string? FundsAvailability { get; set; }
        public string? AuthorisedAmountCurrency { get; set; }
        public string? ThreeDAuthenticatedResponse { get; set; }
        public string? AvsResultRaw { get; set; }
        public string? RetryAttempt1RawResponse { get; set; }
        public string? PaymentMethod { get; set; }
        public string? RetryAttempt1ScaExemptionRequested { get; set; }
        public string? AvsResult { get; set; }
        public string? CardSummary { get; set; }
        public string? RetryAttempt1AvsResultRaw { get; set; }
        public string? NetworkTxReference { get; set; }
        public string? ExpiryDate { get; set; }
        public string? CavvAlgorithm { get; set; }
        public string? CardBin { get; set; }
        public string? Alias { get; set; }
        public string? CvcResultRaw { get; set; }
        public string? MerchantReference { get; set; }
        public string? AcquirerReference { get; set; }
        public string? CardIssuingCountry { get; set; }
        public string? LiabilityShift { get; set; }
        public string? FraudResultType { get; set; }
        public string? AuthCode { get; set; }
        public string? CardHolderName { get; set; }
        public string? AdjustAuthorisationData { get; set; }
        public string? IsCardCommercial { get; set; }
        public string? PaymentAccountReference { get; set; }
        public string? RetryAttempt1AcquirerAccount { get; set; }
        public string? CardIssuingBank { get; set; }
        public string? RetryAttempt1Acquirer { get; set; }
        public string? AuthorisedAmountValue { get; set; }
        public string? IssuerCountry { get; set; }
        public string? CvcResult { get; set; }
        public string? RetryAttempt1ResponseCode { get; set; }
        public string? AliasType { get; set; }
        public string? RetryAttempt1ShopperInteraction { get; set; }
        public string? CardPaymentMethod { get; set; }
        public string? AcquirerCode { get; set; }

        public string? ManualCapture { get; set; } = "true";
    }

    public class FraudResult
    {
        public int AccountScore { get; set; }
        public List<object>? Results { get; set; }
    }


    public class Amount
    {
        public string? Currency { get; set; }
        public int Value { get; set; }
    }

    public class PaymentMethod
    {
        public string? Brand { get; set; }
        public string? Type { get; set; }
    }
    public enum TenderTypeId
    {
        /// <summary>
        /// Default value, should not be used.
        /// </summary>
        None = 0,

        /// <summary>
        /// Cash payment method identifier.
        /// </summary>
        Cash = 1,

        /// <summary>
        /// Check payment method identifier.
        /// </summary>
        Check = 2,

        /// <summary>
        /// Cards payment method identifier.
        /// </summary>
        Card = 3,

        /// <summary>
        /// Customer account payment method identifier.
        /// </summary>
        CustomerAccount = 4,

        /// <summary>
        /// Currency payment method identifier.
        /// </summary>
        Currency = 6,

        /// <summary>
        /// Credit memo payment method identifier.
        /// </summary>
        CreditMemo = 7,

        /// <summary>
        /// Gift card payment method identifier.
        /// </summary>
        GiftCard = 8,

        /// <summary>
        /// Loyalty card payment method identifier.
        /// </summary>
        LoyaltyCard = 10,
    }
    public class AdyenPaymentMethod
    {
        public string? Type { get; set; }
        public string? Number { get; set; }
        public string? ExpiryMonth { get; set; }
        public string? ExpiryYear { get; set; }
        public string? HolderName { get; set; }
        public string? Cvc { get; set; }
    }

    public class AdyenApplicationInfo
    {
        AdyenMerchantApplication? MerchantApplication { get; set; }
    }

    public class AdyenMerchantApplication
    {
        public string? Name { get; set; }
        public string? Version { get; set; }
    }

    public class AdyenDeliveryAddress
    {
        public string? HouseNumberOrName {  get; set; }
        public string? Street { get; set; }
        public string? City { get; set; }
        public string? StateOrProvince { get; set; }
        public string? PostalCode { get; set; }
        public string? Country  { get; set; }
    }


}
