import { Selector } from 'testcafe';
import { cssSignIn } from '../data/CssClass';

class SignInPage {
    email: Selector;
    password: Selector;
    submit: Selector;
    constructor() {
        this.email = Selector(cssSignIn.email);
        this.password = Selector(cssSignIn.password);
        this.submit = Selector(cssSignIn.submit);
    }
}

export default new SignInPage();
