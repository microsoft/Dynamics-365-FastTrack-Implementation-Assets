import { Selector } from 'testcafe';
import { cssCheckout } from '../data/CssClass';
import ICreditCardPayment from '../common/ICreditCardPayment';
//Test connector
export default class CreditCardPayment implements ICreditCardPayment {
    cardHolderName: Selector;
    cardNumber: Selector;
    cardExpiryMonth: Selector;
    cardExpiryYear: Selector;
    cardType: Selector;
    sameAsShippingCheckBox: Selector;

    constructor() {
        this.cardHolderName = Selector(cssCheckout.cardHolderName);
        this.cardNumber = Selector(cssCheckout.cardNumber);
        this.cardExpiryMonth = Selector(cssCheckout.cardExpirationMonthDropDown);
        this.cardExpiryYear = Selector(cssCheckout.cardExpirationYearDropDown);
        this.cardType = Selector(cssCheckout.cardType);
        this.sameAsShippingCheckBox = Selector(cssCheckout.sameAsShippingCheckBox);
    }
}
