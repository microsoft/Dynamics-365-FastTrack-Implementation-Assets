import { t, Selector } from 'testcafe';
import Buybox from '../components/Buybox';
import PageHeader from '../components/PageHeader';
import { cssPdp } from '../data/CssClass';
import { deletePress } from '../data/key';

class ProductDetailsPage {
    Header: PageHeader;
    BuyboxControl: Buybox;
    addtoCartPopUpModalDialogButton: Selector;
    constructor() {
        this.BuyboxControl = new Buybox();
        this.addtoCartPopUpModalDialogButton = Selector(cssPdp.addtoCartPopUpModalButton);
    }

    async quantity(qty: string) {
        await t
            .selectText(this.BuyboxControl.quantity)
            .pressKey(deletePress)
            .typeText(this.BuyboxControl.quantity, qty);
    }

    async addItemToCart() {
        await t.click(this.BuyboxControl.addtoCart);
    }

    async viewBagAndCheckout() {
        await t.click(this.addtoCartPopUpModalDialogButton);
        await t.wait(3000);
    }

    async chooseDimension(name: string, val: string): Promise<void> {
        const dimensionSelect = Selector(cssPdp.dimensionDropdownLabel)
            .withExactText(name)
            .nextSibling();
        const dimensionOption = dimensionSelect.find('option').withExactText(val);
        await t.click(dimensionSelect).click(dimensionOption);
    }
}

export default new ProductDetailsPage();
