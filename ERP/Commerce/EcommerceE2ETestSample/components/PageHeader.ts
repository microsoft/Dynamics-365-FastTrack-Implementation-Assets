import { Selector } from 'testcafe';
import IHeader from '../common/IHeader';
import { cssHeader } from '../data/cssClass';

export default class PageHeader implements IHeader {
    signin: Selector;
    search: Selector;
    shoppingBag: Selector;
    wishList: Selector;
    companyLogo: Selector;

    constructor() {
        this.signin = Selector(cssHeader.signinLink);
    }
}
