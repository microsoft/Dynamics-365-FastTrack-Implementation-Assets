import { Selector } from 'testcafe';
import { cssCheckout } from '../data/CssClass';
import IAddress from '../common/IAddress';

export default class BillingAddress implements IAddress {
    name: Selector;
    street: Selector;
    city: Selector;
    state: Selector;
    zipcode: Selector;
    country: Selector;
    phone: Selector;

    constructor() {
        this.street = Selector(cssCheckout.billingStreetTextBox);
        this.city = Selector(cssCheckout.billingCityTextBox);
        this.state = Selector(cssCheckout.billingStateProvinceTextBox);
        this.zipcode = Selector(cssCheckout.billingZipTextBox1);
        this.country = Selector(cssCheckout.billingCountryRegionDropDownList);
    }
}
