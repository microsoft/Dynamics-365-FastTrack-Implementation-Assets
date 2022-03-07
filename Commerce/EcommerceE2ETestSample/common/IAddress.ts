import { Selector } from 'testcafe';

export default interface IAddress {
    street: Selector;
    city: Selector;
    state: Selector;
    zipcode: Selector;
    country: Selector;
}
