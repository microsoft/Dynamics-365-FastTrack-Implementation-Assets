import { t, Selector } from 'testcafe';
import PageHeader from '../components/PageHeader';
import { cssHeader, cssCheckout } from '../data/CssClass';
class HomePage {
    header: PageHeader;
    cookieConsent: Selector;
    constructor() {
        this.header = new PageHeader();
        this.cookieConsent = Selector(cssCheckout.acceptCookies);
    }

    async clickSignin() {
        await t.click(this.header.signin);
    }

    async clickCategoryDropDown(categoryName: string) {
        const link = Selector(cssHeader.navBarDropDowns)
            .find(cssHeader.navBarDropDownButton)
            .withText(categoryName);
        await t.hover(link).click(link);
    }

    async clickCategoryDropDownLink(catgoryLink: string) {
        const link = Selector(cssHeader.navBarDropDowns)
            .find(cssHeader.navBarDropDownLink)
            .withText(catgoryLink);
        await t.hover(link).click(link);
    }

    async acceptCookies() {
        await t.click(this.cookieConsent);
    }
}

export default new HomePage();
