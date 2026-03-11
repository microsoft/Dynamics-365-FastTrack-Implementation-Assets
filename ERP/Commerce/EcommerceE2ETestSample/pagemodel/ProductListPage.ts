import { t, Selector } from 'testcafe';
import PageHeader from '../components/PageHeader';
import { cssCategory } from '../data/CssClass';

class ProductListPage {
    header: PageHeader;
    searchResultContainerProduct: Selector;
    constructor() {
        this.searchResultContainerProduct = Selector(cssCategory.categorySearchProducts);
    }

    async chooseProduct(name: string): Promise<void> {
        await t.click(
            this.searchResultContainerProduct.find(cssCategory.categoryProduct).withText(name)
        );
    }
}

export default new ProductListPage();
