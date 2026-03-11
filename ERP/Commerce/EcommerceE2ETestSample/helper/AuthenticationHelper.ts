import { b2cSignInurl } from '../data/Settings';
import { t, Selector, Role } from 'testcafe';
import { cssSignIn } from '../data/CssClass';

export default class AuthenticationHelper {
    static useC2Role(email: string, password: string): Role {
        const c2Role = Role(b2cSignInurl, async () => {
            await t.typeText(Selector(cssSignIn.email), email);
            await t.typeText(Selector(cssSignIn.password), password);
            await t.click(cssSignIn.submit);
        });
        return c2Role;
    }
}
