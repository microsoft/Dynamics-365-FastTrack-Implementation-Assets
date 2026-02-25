import { LocalizeConstants } from "../common/Constants";

export class Localization {
    private _resources: ComponentFramework.Resources;

    constructor(resources: ComponentFramework.Resources) {
        this._resources = resources;
    }

    /**
    * Takes string name, arguments and returns localized string.
    */
    public getString = (stringId: LocalizeConstants, ...args: string[]): string => {
        let locString = stringId.toString();
        try {
            locString = this._resources.getString(stringId);
            args.forEach((item, index) => {
                locString = locString.replace(`{${index}}`, item);
            });
        } catch {
            console.error(`No localization string found for ${stringId}`);  // eslint-disable-line no-console
        }
        return locString;
    };
}
