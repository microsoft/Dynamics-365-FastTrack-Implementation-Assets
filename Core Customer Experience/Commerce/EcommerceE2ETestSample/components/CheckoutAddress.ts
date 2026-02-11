import { Selector } from 'testcafe';
import { cssCheckout } from '../data/CssClass';
import IAddress from '../common/IAddress';

export default class CheckoutAddress implements IAddress {
    name: Selector;
    street: Selector;
    city: Selector;
    state: Selector;
    zipcode: Selector;
    country: Selector;
    phone: Selector;

    constructor() {
        this.name = Selector(cssCheckout.shipAddressNameOnCheckoutForm);
        this.street = Selector(cssCheckout.shipStreetNameOnCheckoutForm);
        this.city = Selector(cssCheckout.shipCityNameOnCheckoutForm);
        this.state = Selector(cssCheckout.shipStateDrpDwnOnCheckoutForm);
        this.zipcode = Selector(cssCheckout.shipZipCodeOnCheckoutForm);
        this.country = Selector(cssCheckout.shipCountryNameOnCheckoutForm);
        this.phone = Selector(cssCheckout.shipCustContactNumberInput);
    }
}
