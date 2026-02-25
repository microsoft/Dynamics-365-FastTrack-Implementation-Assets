import { Selector } from 'testcafe';

export default interface IBuybox {
    quantity: Selector;
    size?: Selector;
    color?: Selector;
    addtoCart: Selector;
}
