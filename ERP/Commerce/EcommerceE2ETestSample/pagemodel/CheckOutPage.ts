import { t, Selector } from 'testcafe';
import BillingAddress from '../components/BillingAddress';
import CheckoutAddress from '../components/CheckoutAddress';
import CreditCardPayment from '../components/CreditCardPayment';
import CustomerAccountPayment from '../components/CustomerAccountPayment';
import { cssCheckout } from '../data/CssClass';

class CheckOutPage {
    shippingAddress: CheckoutAddress;
    billingAddress: BillingAddress;
    creditCardPayment: CreditCardPayment;
    customerAccountPayment: CustomerAccountPayment;
    saveAndContinue: Selector;
    placeOrder: Selector;
    paymentIframe: Selector;
    emailProfile: Selector;
    constructor() {
        this.shippingAddress = new CheckoutAddress();
        this.billingAddress = new BillingAddress();
        this.creditCardPayment = new CreditCardPayment();
        this.customerAccountPayment = new CustomerAccountPayment();
        this.saveAndContinue = Selector(cssCheckout.saveAndContinueBtnOnCheckout);
        this.paymentIframe = Selector(cssCheckout.iframe);
        this.placeOrder = Selector(cssCheckout.placeOrderButton);
        this.emailProfile = Selector(cssCheckout.emailprofile);
    }
    async email(email: string) {
        if (await Selector(this.emailProfile).exists) {
            await t.typeText(this.emailProfile, email);
        }
    }

    async shippingAddressName(addressName: string) {
        if (await Selector(this.shippingAddress.name).exists) {
            await t.typeText(this.shippingAddress.name, addressName);
        }
    }

    async shippingAddressStreet(street: string) {
        if (await Selector(this.shippingAddress.street).exists) {
            await t.typeText(this.shippingAddress.street, street);
        }
    }

    async billingAddressStreet(street: string) {
        if (await Selector(this.billingAddress.street).exists) {
            await t.typeText(this.billingAddress.street, street);
        }
    }

    async shippingAddressCity(city: string) {
        if (await Selector(this.shippingAddress.city).exists) {
            await t.typeText(this.shippingAddress.city, city);
        }
    }

    async billingAddressCity(city: string) {
        if (await Selector(this.billingAddress.city).exists) {
            await t.typeText(this.billingAddress.city, city);
        }
    }

    async shippingAddressZipCode(zipcode: string) {
        if (await Selector(this.shippingAddress.zipcode).exists) {
            await t.typeText(this.shippingAddress.zipcode, zipcode);
        }
    }

    async billingAddressZipCode(zipcode: string) {
        if (await Selector(this.billingAddress.zipcode).exists) {
            await t.typeText(this.billingAddress.zipcode, zipcode);
        }
    }

    async shippingAddressPhone(phone: string) {
        if (await Selector(this.shippingAddress.phone).exists) {
            await t.typeText(this.shippingAddress.phone, phone);
        }
    }

    async shippingAddressState(state: string) {
        if (await Selector(this.shippingAddress.state).exists) {
            const stateOption = this.shippingAddress.state.find('option').withText(state);
            await t.click(this.shippingAddress.state);
            await t.click(stateOption);
        }
    }

    async billingAddressState(state: string) {
        if (await Selector(this.billingAddress.state).exists) {
            await t.typeText(this.billingAddress.state, state);
        }
    }

    async shippingAddressCountry(country: string) {
        if (await Selector(this.shippingAddress.country).exists) {
            const countryOption = this.shippingAddress.country.find('option').withText(country);
            await t.click(this.shippingAddress.country).click(countryOption);
        }
    }

    async billingAddressCountry(country: string) {
        if (await Selector(this.billingAddress.country).exists) {
            const countryOption = this.billingAddress.country.find('option').withText(country);
            await t.click(this.billingAddress.country).click(countryOption);
        }
    }

    async clickSaveAndContinue() {
        if (await Selector(this.saveAndContinue).exists) {
            await t.click(this.saveAndContinue);
            await t.wait(3000);
        }
    }

    async clickAccountPayment() {
        if (await Selector(this.customerAccountPayment.applyCreditBalance).exists) {
            await t.click(this.customerAccountPayment.applyCreditBalance);
        }
    }

    async clickPlaceOrder() {
        if (await Selector(this.placeOrder).exists) {
            await t.click(this.placeOrder);
            await t.wait(3000);
        }
    }

    async clickSameAsShippingCheckBox() {
        if (await Selector(this.creditCardPayment.sameAsShippingCheckBox).exists) {
            await t.click(this.creditCardPayment.sameAsShippingCheckBox);
        }
    }

    async switchToPaymentIframe() {
        await t.switchToIframe(this.paymentIframe);
    }

    async switchToMain() {
        await t.switchToMainWindow();
    }

    async cardHolderName(name: string) {
        if (await Selector(this.creditCardPayment.cardHolderName).exists)
            await t.typeText(this.creditCardPayment.cardHolderName, name);
    }

    async cardType(cardType: string) {
        if (await Selector(this.creditCardPayment.cardType).exists) {
            const cardTypeOption = this.creditCardPayment.cardType
                .find('option')
                .withText(cardType);
            await t.click(this.creditCardPayment.cardType);
            await t.click(cardTypeOption);
        }
    }

    async cardNumber(num: string) {
        if (await Selector(this.creditCardPayment.cardNumber).exists) {
            await t.typeText(this.creditCardPayment.cardNumber, num);
        }
    }

    async cardExpiryMonth(expiryMonth: string) {
        if (await Selector(this.creditCardPayment.cardExpiryMonth).exists) {
            const expiryMonthOption = this.creditCardPayment.cardExpiryMonth
                .find('option')
                .withText(expiryMonth);
            await t.click(this.creditCardPayment.cardExpiryMonth);
            await t.click(expiryMonthOption);
        }
    }

    async cardExpiryYear(expiryYear: string) {
        if (await Selector(this.creditCardPayment.cardExpiryYear).exists) {
            const expiryYearOption = this.creditCardPayment.cardExpiryYear
                .find('option')
                .withText(expiryYear);
            await t.click(this.creditCardPayment.cardExpiryYear);
            await t.click(expiryYearOption);
        }
    }
}

export default new CheckOutPage();
