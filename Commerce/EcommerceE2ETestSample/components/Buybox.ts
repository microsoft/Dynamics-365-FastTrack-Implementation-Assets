import { Selector } from 'testcafe';
import { cssPdp } from '../data/CssClass';
import IBuybox from '../common/IBuybox';

export default class Buybox implements IBuybox {
    quantity: Selector;
    size?: Selector;
    color?: Selector;
    addtoCart: Selector;
    constructor() {
        this.quantity = Selector(cssPdp.inputQuantity);
        this.addtoCart = Selector(cssPdp.addToCartBtn);
    }
}
