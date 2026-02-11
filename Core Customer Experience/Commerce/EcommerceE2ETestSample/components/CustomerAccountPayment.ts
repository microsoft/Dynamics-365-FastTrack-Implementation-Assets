import { Selector } from 'testcafe';
import { cssCheckout } from '../data/CssClass';
import ICustomerAccountPayment from '../common/ICustomerAccountPayment';

export default class CustomerAccountPayment implements ICustomerAccountPayment {
    applyCreditBalance: Selector;

    constructor() {
        this.applyCreditBalance = Selector(cssCheckout.applyCustomerCredit);
    }
}
