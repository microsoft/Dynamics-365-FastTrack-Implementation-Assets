/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Voice input for the side chat's message box. The associate taps the mic and speaks, and the words
 * are typed into the box as they are recognised, so the associate sees what they said. The mic keeps
 * listening through pauses until the associate taps it again, which sends the message as soon as the
 * engine has finished the last words. Typing, Enter, Send or closing the panel stop the mic instead,
 * without it sending anything. When listening ends any other way, such as a failure, or the engine
 * cannot finish the last words, the words stay in the box for the associate to check and send.
 *
 * The browser engine's own speech recognition (the Web Speech API) turns speech into text, so there is
 * no service or key of ours involved: Store Commerce for Windows (WebView2) and Edge use Microsoft's
 * online speech service, and Chrome uses Google's. The agent only ever receives text, exactly as if it
 * had been typed. The mic is shown only where the engine offers speech recognition, and it says why
 * when it cannot listen, such as when the microphone is blocked.
 *
 * The engine still ends a recognition after a long silence, or after a minute or so of speech. While the
 * associate has not stopped the mic, the next recognition then starts straight away and carries on from
 * the words already in the box, so a pause never turns the mic off.
 */

import * as React from "react";
import { ToggleButton, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { MicOffRegular, MicPulseRegular, MicRegular } from "@fluentui/react-icons";

/** The part of the Web Speech API's `result` event this reads. */
interface ISpeechRecognitionEvent {
    /** Everything recognised since listening started; the last entries may still be interim. */
    readonly results: SpeechRecognitionResultList;
}

/** The part of the Web Speech API's `error` event this reads. */
interface ISpeechRecognitionErrorEvent {
    /** The error code, such as "not-allowed" or "no-speech". */
    readonly error: string;
}

/**
 * The part of the Web Speech API's SpeechRecognition this uses. TypeScript's DOM library does not
 * declare SpeechRecognition itself, and Chromium engines only expose it as webkitSpeechRecognition.
 */
interface ISpeechRecognition {
    lang: string;
    continuous: boolean;
    interimResults: boolean;
    maxAlternatives: number;
    onaudiostart: (() => void) | null;
    onresult: ((event: ISpeechRecognitionEvent) => void) | null;
    onerror: ((event: ISpeechRecognitionErrorEvent) => void) | null;
    onend: (() => void) | null;
    start(): void;
    stop(): void;
    abort(): void;
}

type SpeechRecognitionConstructor = new () => ISpeechRecognition;

/**
 * Where voice input is. After the associate stops it, the state is `off` straight away, while the last
 * words, which the engine is still finishing, can still land in the box before the message is sent.
 */
export type VoiceInputState = "off" | "starting" | "listening";

/** What the side panel gives voice input. */
export interface IVoiceInputOptions {
    /** Receives the message box's new text each time more speech is recognised. */
    onText: (text: string) => void;
    /** Called when listening ends after some speech was typed into the box. */
    onHeard?: () => void;
    /**
     * Sends the message when the associate taps the mic to stop after it heard something, once the
     * engine has cleanly finished the last words.
     * @param text The message box's text, the last words included.
     */
    onSend?: (text: string) => void;
}

/** Voice input's state and controls. */
export interface IVoiceInput {
    /** Whether the engine offers speech recognition. The mic is only shown when it does. */
    isSupported: boolean;
    state: VoiceInputState;
    /** Why voice input last stopped without the associate asking it to, or an empty string. */
    error: string;
    /**
     * Starts listening, adding what is heard after the text already in the box, and keeps listening
     * through pauses. Called again, it stops listening and, once the engine has finished the last
     * words, hands the box's text to `onSend` when something was heard.
     * @param typed The text in the box now.
     */
    toggle: (typed: string) => void;
    /**
     * Stops listening and ignores anything still being recognised, as when the associate types, sends
     * or closes the panel. Also clears the last error.
     */
    cancel: () => void;
}

/** One tap of the mic: listening that goes on, one recognition after another, until it is stopped. */
interface IListeningRun {
    /** The box's text before the words of the recognition listening now. */
    base: string;
    /** False once the associate stops the mic, or listening cannot go on. */
    keepListening: boolean;
    /** Whether the associate tapped the mic to stop, so the message is sent once the last words land. */
    sendWhenStopped: boolean;
    /** Whether any words were heard since the mic was tapped. */
    heardAny: boolean;
    /** Recognitions in a row that ended without hearing anything, before or straight after audio started. */
    failedStarts: number;
    /** Network errors in a row. */
    networkErrors: number;
}

/** What a recognition needs from the hook that started it. */
interface IListeningHooks {
    recognitionRef: React.MutableRefObject<ISpeechRecognition | null>;
    runRef: React.MutableRefObject<IListeningRun | null>;
    optionsRef: React.MutableRefObject<IVoiceInputOptions>;
    setState: React.Dispatch<React.SetStateAction<VoiceInputState>>;
    setError: (error: string) => void;
}

const START_FAILED_MESSAGE: string = "Voice input couldn't start. Try again, or type your message.";
const STOPPED_MESSAGE: string = "Voice input stopped unexpectedly. Try again, or type your message.";
const UNFINISHED_MESSAGE: string = "Voice input couldn't finish your last words. Check your message, then send it.";

/** Errors that end one recognition but not the listening: the next recognition carries on. */
const RESTARTABLE_ERRORS: string[] = ["no-speech", "aborted", "network"];

/** A recognition that hears nothing and ends sooner than this has failed to start. */
const QUICK_END_MS: number = 1000;

/** How many recognitions in a row may fail to start before listening gives up. */
const MAX_FAILED_STARTS: number = 3;

/** How many network errors in a row listening rides out before it gives up. */
const MAX_NETWORK_RESTARTS: number = 2;

const useStyles = makeStyles({
    status: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "6px",
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    statusIcon: {
        flexShrink: 0,
        fontSize: "16px"
    },

    /* The mic turns red while it listens, the usual sign that audio is being recorded. */
    recordingIcon: {
        color: tokens.colorPaletteRedForeground1
    },

    /* While listening the whole button takes a red tint, so it reads as on at a glance. */
    listeningButton: {
        backgroundColor: tokens.colorPaletteRedBackground1,
        ":hover": {
            backgroundColor: tokens.colorPaletteRedBackground2
        },
        ":hover:active": {
            backgroundColor: tokens.colorPaletteRedBackground2
        }
    },

    errorIcon: {
        color: tokens.colorPaletteRedForeground1
    }
});

/**
 * Finds the engine's speech recognition.
 * @returns Its constructor, or undefined when the engine has none.
 */
function getSpeechRecognitionConstructor(): SpeechRecognitionConstructor | undefined {
    if (typeof window === "undefined") {
        return undefined;
    }

    const speechWindow = window as unknown as {
        SpeechRecognition?: SpeechRecognitionConstructor;
        webkitSpeechRecognition?: SpeechRecognitionConstructor;
    };

    return speechWindow.SpeechRecognition ?? speechWindow.webkitSpeechRecognition;
}

/**
 * The language to listen for: POS's own, which POS writes to the page's lang attribute from the
 * device's culture, such as "en-us", or the engine's when POS has not set one.
 * @returns A language tag with conventional casing, such as "en-US".
 */
function getSpeechLanguage(): string {
    const pageLanguage: string = (document.documentElement.getAttribute("lang") ?? "").trim();
    const language: string = pageLanguage.length > 0 ? pageLanguage : (navigator.language || "en-US");

    return language
        .split(/[-_]/)
        .map((part: string, index: number): string => {
            if (index === 0) {
                return part.toLowerCase();
            }

            if (part.length === 2) {
                return part.toUpperCase();
            }

            return part.length === 4 ? part.charAt(0).toUpperCase() + part.slice(1).toLowerCase() : part;
        })
        .join("-");
}

/**
 * Reads everything recognised so far, interim words included.
 * @param event The engine's `result` event.
 * @returns The words, with single spaces.
 */
function readTranscript(event: ISpeechRecognitionEvent): string {
    const parts: string[] = [];
    for (let index: number = 0; index < event.results.length; index++) {
        const result: SpeechRecognitionResult = event.results[index];
        if (result && result.length > 0 && result[0].transcript) {
            parts.push(result[0].transcript);
        }
    }

    return parts.join(" ").replace(/\s+/g, " ").trim();
}

/**
 * Adds spoken words after the text already in the box.
 * @param typed The box's text before these words.
 * @param spoken The words recognised so far.
 * @returns The box's new text.
 */
function appendSpokenText(typed: string, spoken: string): string {
    if (spoken.length === 0) {
        return typed;
    }

    if (typed.trim().length === 0) {
        return spoken;
    }

    return /\s$/.test(typed) ? `${typed}${spoken}` : `${typed} ${spoken}`;
}

/**
 * Says why listening stopped, in words an associate can act on. Silence and a recognition the engine
 * aborted are not described: listening carries on through them.
 * @param code The Web Speech API error code.
 * @returns The message.
 */
function describeSpeechError(code: string): string {
    switch (code) {
        case "audio-capture":
            return "No microphone was found. Connect one and try again.";
        case "not-allowed":
            return "Microphone access is blocked. Allow the microphone for POS, then try again.";
        case "service-not-allowed":
            return "Voice input isn't available on this device. Type your message instead.";
        case "network":
            return "Voice input couldn't reach the speech service. Try again, or type your message.";
        case "language-not-supported":
            return "Voice input doesn't support this language. Type your message instead.";
        default:
            return STOPPED_MESSAGE;
    }
}

/**
 * Stops a recognition from reaching the box.
 * @param recognition The recognition.
 */
function detach(recognition: ISpeechRecognition): void {
    recognition.onaudiostart = null;
    recognition.onresult = null;
    recognition.onerror = null;
    recognition.onend = null;
}

/**
 * Stops listening and throws away anything still being recognised.
 * @param recognition The recognition, if there is one.
 */
function abandon(recognition: ISpeechRecognition | null): void {
    if (!recognition) {
        return;
    }

    detach(recognition);
    try {
        recognition.abort();
    } catch {
        // It had already ended.
    }
}

/**
 * Ends a listening run: the mic turns off, the status line says why when listening could not go on,
 * and focus can go back to the box when something was heard. When the associate stopped the mic and
 * the engine finished cleanly, what they said is sent.
 * @param run The listening run.
 * @param hooks The hook's refs and state setters.
 * @param message Why listening could not go on, or an empty string.
 */
function endRun(run: IListeningRun, hooks: IListeningHooks, message: string): void {
    run.keepListening = false;
    if (hooks.runRef.current !== run) {
        return;
    }

    hooks.runRef.current = null;
    hooks.setState("off");
    if (message.length > 0) {
        hooks.setError(message);
    }

    const options: IVoiceInputOptions = hooks.optionsRef.current;
    if (run.heardAny && options.onHeard) {
        options.onHeard();
    }

    if (run.sendWhenStopped && message.length === 0 && run.heardAny && run.base.trim().length > 0 && options.onSend) {
        options.onSend(run.base);
    }
}

/**
 * Starts one recognition of a listening run. When the engine ends it, the next one starts and carries
 * on from the words already in the box, until the associate stops the mic or listening cannot go on.
 * @param run The listening run.
 * @param hooks The hook's refs and state setters.
 * @param isRestart Whether an earlier recognition of this run has ended.
 */
function listen(run: IListeningRun, hooks: IListeningHooks, isRestart: boolean): void {
    const failedMessage: string = isRestart ? STOPPED_MESSAGE : START_FAILED_MESSAGE;
    const Recognition: SpeechRecognitionConstructor | undefined = getSpeechRecognitionConstructor();
    let recognition: ISpeechRecognition;
    try {
        if (!Recognition) {
            throw new Error("The engine has no speech recognition.");
        }

        recognition = new Recognition();
        recognition.lang = getSpeechLanguage();
        recognition.continuous = true;
        recognition.interimResults = true;
        recognition.maxAlternatives = 1;
    } catch {
        endRun(run, hooks, failedMessage);
        return;
    }

    const startedAt: number = Date.now();
    let heard: string = "";
    let lastError: string = "";
    const isCurrent = (): boolean => hooks.recognitionRef.current === recognition;

    recognition.onaudiostart = (): void => {
        if (isCurrent()) {
            hooks.setState((current: VoiceInputState) => current === "starting" ? "listening" : current);
        }
    };

    recognition.onresult = (event: ISpeechRecognitionEvent): void => {
        if (!isCurrent()) {
            return;
        }

        heard = readTranscript(event);
        run.heardAny = run.heardAny || heard.length > 0;
        hooks.optionsRef.current.onText(appendSpokenText(run.base, heard));
    };

    recognition.onerror = (event: ISpeechRecognitionErrorEvent): void => {
        if (isCurrent()) {
            lastError = event.error;
        }
    };

    recognition.onend = (): void => {
        if (!isCurrent()) {
            return;
        }

        hooks.recognitionRef.current = null;
        detach(recognition);
        run.base = appendSpokenText(run.base, heard);

        // Hearing something shows the engine and its service work, so the counts start again.
        if (heard.length > 0) {
            run.failedStarts = 0;
            run.networkErrors = 0;
        } else {
            run.failedStarts = Date.now() - startedAt < QUICK_END_MS ? run.failedStarts + 1 : 0;
        }

        if (lastError === "network") {
            run.networkErrors++;
        }

        // After the associate stops the mic, only a real failure is worth saying, or words the engine
        // could not finish, which are left in the box to check rather than sent.
        let message: string = "";
        if (lastError.length > 0 && RESTARTABLE_ERRORS.indexOf(lastError) < 0) {
            message = describeSpeechError(lastError);
        } else if (run.keepListening && run.networkErrors > MAX_NETWORK_RESTARTS) {
            message = describeSpeechError("network");
        } else if (run.keepListening && run.failedStarts >= MAX_FAILED_STARTS) {
            message = STOPPED_MESSAGE;
        } else if (run.sendWhenStopped && run.heardAny && lastError.length > 0 && lastError !== "no-speech") {
            message = UNFINISHED_MESSAGE;
        }

        if (run.keepListening && message.length === 0) {
            listen(run, hooks, true);
            return;
        }

        endRun(run, hooks, message);
    };

    hooks.recognitionRef.current = recognition;
    try {
        recognition.start();
    } catch {
        hooks.recognitionRef.current = null;
        detach(recognition);
        endRun(run, hooks, failedMessage);
    }
}

/**
 * Listens to the associate and types what they say into the message box, until they tap the mic again,
 * which sends it.
 * @param options Where the recognised text goes, and how it is sent.
 * @returns The state and controls for the mic and its status line.
 */
export function useVoiceInput(options: IVoiceInputOptions): IVoiceInput {
    const [isSupported] = React.useState<boolean>(() => getSpeechRecognitionConstructor() !== undefined);
    const [state, setState] = React.useState<VoiceInputState>("off");
    const [error, setError] = React.useState<string>("");

    // The recognition whose words still land in the box. It outlives `state` after the associate
    // stops, so the last words, which the engine is still finishing, are not lost.
    const recognitionRef = React.useRef<ISpeechRecognition | null>(null);
    // The listening started by the associate's last tap, until its last recognition ends.
    const runRef = React.useRef<IListeningRun | null>(null);
    const optionsRef = React.useRef<IVoiceInputOptions>(options);
    React.useEffect(() => {
        optionsRef.current = options;
    });

    const hooks: IListeningHooks = React.useMemo(
        (): IListeningHooks => ({ recognitionRef, runRef, optionsRef, setState, setError }), []);

    const cancel = React.useCallback((): void => {
        abandon(recognitionRef.current);
        recognitionRef.current = null;
        if (runRef.current) {
            runRef.current.keepListening = false;
            runRef.current = null;
        }

        setState("off");
        setError("");
    }, []);

    const toggle = React.useCallback((typed: string): void => {
        const run: IListeningRun | null = runRef.current;
        if (run && run.keepListening) {
            const active: ISpeechRecognition | null = recognitionRef.current;
            if (!active) {
                cancel();
                return;
            }

            // Stopped rather than aborted, so the words the engine is finishing still land in the box,
            // and are sent with the rest when its recognition ends.
            run.keepListening = false;
            run.sendWhenStopped = true;
            setState("off");
            try {
                active.stop();
            } catch {
                cancel();
            }

            return;
        }

        if (!getSpeechRecognitionConstructor()) {
            return;
        }

        abandon(recognitionRef.current);
        recognitionRef.current = null;
        const next: IListeningRun = {
            base: typed,
            keepListening: true,
            sendWhenStopped: false,
            heardAny: false,
            failedStarts: 0,
            networkErrors: 0
        };
        runRef.current = next;
        setError("");
        setState("starting");
        listen(next, hooks, false);
    }, [cancel, hooks]);

    // Signing out unmounts the panel, and the microphone must not stay on for the next operator.
    React.useEffect(() => {
        return () => {
            abandon(recognitionRef.current);
            recognitionRef.current = null;
            if (runRef.current) {
                runRef.current.keepListening = false;
                runRef.current = null;
            }
        };
    }, []);

    return { isSupported, state, error, toggle, cancel };
}

/** What the mic button needs. */
export interface IVoiceInputButtonProps {
    state: VoiceInputState;
    /**
     * Whether stopping the mic sends the message now. It cannot while the agent is still answering, or a
     * file is being prepared, and the words then stay in the box.
     */
    sendsOnStop: boolean;
    onClick: () => void;
}

/**
 * The round mic next to Send. It is a toggle, so its name stays "Voice input" while screen readers
 * announce whether it is on, and it turns red while it listens. Tapping it to stop sends the message.
 * @param props The voice input state and what a tap does.
 * @returns The rendered button.
 */
export const VoiceInputButton: React.FC<IVoiceInputButtonProps> = (props) => {
    const styles = useStyles();
    const isOn: boolean = props.state !== "off";
    let title: string = "Voice input";
    if (isOn) {
        title = props.sendsOnStop ? "Stop and send" : "Stop voice input";
    }

    return (
        <ToggleButton
            className={isOn ? styles.listeningButton : undefined}
            appearance="subtle"
            shape="circular"
            checked={isOn}
            icon={isOn ? <MicPulseRegular className={styles.recordingIcon} /> : <MicRegular />}
            aria-label="Voice input"
            title={title}
            onClick={props.onClick}
        />
    );
};

/** What the voice input status line needs. */
export interface IVoiceInputStatusProps {
    state: VoiceInputState;
    error: string;
    /** Whether stopping the mic sends the message now, as for the mic button. */
    sendsOnStop: boolean;
    /** Applied to the live region, which is always rendered. */
    className?: string;
}

/**
 * Says that the mic is listening, or why it stopped. The live region is always rendered, and empty when
 * there is nothing to say, so screen readers announce each change to it. Empty, it takes no space.
 * @param props The voice input state and its last error.
 * @returns The rendered status line.
 */
export const VoiceInputStatus: React.FC<IVoiceInputStatusProps> = (props) => {
    const styles = useStyles();
    const hasError: boolean = props.error.length > 0;
    let text: string = props.error;
    if (!hasError && props.state === "starting") {
        text = "Starting the mic\u2026";
    } else if (!hasError && props.state === "listening") {
        text = props.sendsOnStop ? "Listening\u2026 tap the mic to send" : "Listening\u2026 tap the mic to stop";
    }

    return (
        <div className={props.className} role="status">
            {text.length > 0 && (
                <div className={styles.status}>
                    {hasError ? (
                        <MicOffRegular className={mergeClasses(styles.statusIcon, styles.errorIcon)} aria-hidden="true" />
                    ) : (
                        <MicPulseRegular className={mergeClasses(styles.statusIcon, styles.recordingIcon)} aria-hidden="true" />
                    )}
                    <span>{text}</span>
                </div>
            )}
        </div>
    );
};
