import { t, Selector } from 'testcafe';
import { cssCart } from '../data/CssClass';

class CartPage {
    guestCheckout: Selector;
    checkout: Selector;
    constructor() {
        this.guestCheckout = Selector(cssCart.cartGuestCheckoutBtn);
        this.checkout = Selector(cssCart.checkoutBtnOnCart);
    }

    async clickGuestCheckout() {
        await t.click(this.guestCheckout);
        await t.wait(3000);
    }

    async clickCheckout() {
        await t.click(this.checkout);
        await t.wait(3000);
    }
}

export default new CartPage();
