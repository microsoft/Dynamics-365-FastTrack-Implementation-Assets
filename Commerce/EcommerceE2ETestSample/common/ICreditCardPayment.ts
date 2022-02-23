import { Selector } from 'testcafe';

export default interface ICreditCardPayment {
    cardHolderName: Selector;
    cardNumber: Selector;
}
