export class ReportPreviewUtils {
    public static LogMessageInConsole(message: unknown, type?: LogType): void {
        if (console) {
            switch (type) {
                case LogType.Error: {
                    // eslint-disable-next-line no-console
                    if (typeof(console.error) === "function") {
                        // eslint-disable-next-line no-console
                        console.error(message);
                    }
                    break;
                }
                case LogType.Warn: {
                    // eslint-disable-next-line no-console
                    if (typeof(console.warn) === "function") {
                        // eslint-disable-next-line no-console
                        console.warn(message);
                    }
                    break;
                }
                case LogType.Console:
                default: {
                    // eslint-disable-next-line no-console
                    if (typeof(console.log) === "function") {
                        // eslint-disable-next-line no-console
                        console.log(message);
                    }
                }
            }
        }
    }
}

export enum LogType {
    Warn,
    Error,
    Console
}
