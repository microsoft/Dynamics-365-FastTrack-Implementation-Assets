import { siteurl } from '../data/Settings';
import { fixture, test } from 'testcafe';
import AuthenticationHelper from '../helper/AuthenticationHelper';
import homePage from '../pagemodel/HomePage';
import productListPage from '../pagemodel/ProductListPage';
import productDetailsPage from '../pagemodel/ProductDetailsPage';
import cartPage from '../pagemodel/CartPage';
import checkOutPage from '../pagemodel/CheckOutPage';

fixture('ecommercesignedincheckout').beforeEach(async (t) => {
    await t
        .useRole(AuthenticationHelper.useC2Role('test@contoso.com', 'password'))
        .navigateTo(siteurl);
});
test('signedin', async (t) => {
    await t.maximizeWindow();
    await homePage.clickSignin();
    await homePage.acceptCookies();
    await homePage.clickCategoryDropDown('Womenswear');
    await homePage.clickCategoryDropDownLink('Coats');
    await productListPage.chooseProduct('Blush Dress Trench Coat');
    await productDetailsPage.chooseDimension('Size', 'S');
    await productDetailsPage.quantity('2');
    await productDetailsPage.addItemToCart();
    await productDetailsPage.viewBagAndCheckout();
    await cartPage.clickCheckout();
    await checkOutPage.shippingAddressName('sdfsdf');
    await checkOutPage.shippingAddressStreet('weqweqwe');
    await checkOutPage.shippingAddressCity('asdasd');
    await checkOutPage.shippingAddressState('California');
    await checkOutPage.shippingAddressZipCode('saasdasdasd');
    await checkOutPage.shippingAddressCountry('United States');
    await checkOutPage.shippingAddressPhone('1234567891');
    await checkOutPage.clickSaveAndContinue();
    //Use default delivery option
    await checkOutPage.clickSaveAndContinue();
    await checkOutPage.switchToPaymentIframe();
    //Use test connector
    await checkOutPage.cardHolderName('c2');
    await checkOutPage.cardType('VISA');
    await checkOutPage.cardNumber('4111111111111111 ');
    await checkOutPage.cardExpiryMonth('03 - March');
    await checkOutPage.cardExpiryYear('2030');
    await checkOutPage.billingAddressCountry('United States of America');
    await checkOutPage.billingAddressStreet('street1');
    await checkOutPage.billingAddressCity('city1');
    await checkOutPage.billingAddressState('state1');
    await checkOutPage.billingAddressZipCode('zipcode1');
    await checkOutPage.switchToMain();
    await checkOutPage.clickSaveAndContinue();
    await checkOutPage.email('test@test.com');
    await checkOutPage.clickSaveAndContinue();
    await checkOutPage.clickPlaceOrder();
});
