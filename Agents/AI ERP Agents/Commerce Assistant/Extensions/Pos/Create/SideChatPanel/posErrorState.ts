/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Carries the POS operation that last failed on the associate's screen to the panel.
 *
 * POS views report failures from outside React, so the failure cannot be component state. Only the
 * newest failure is kept, and only for a few minutes: the agent should help with what just went wrong,
 * not with something from earlier in the shift. Every failure gets a version, which lets the panel offer
 * help once per failure.
 */

import { IAgentPosErrorContext } from "./agentContracts";

/** How long a failure stays relevant to what the associate asks next. */
export const POS_ERROR_LIFETIME_MS: number = 10 * 60 * 1000;

/** A failure the panel can help with, with the version it was published as. */
export interface IVersionedPosError {
    version: number;
    error: IAgentPosErrorContext;
    /** When POS reported it, in milliseconds since the epoch. */
    reportedAt: number;
}

type Listener = () => void;

let latestVersion: number = 0;
let current: IVersionedPosError | null = null;
let helpRequestedVersion: number = 0;
const listeners = new Set<Listener>();

function notify(): void {
    listeners.forEach((listener) => listener());
}

/**
 * Replaces any earlier failure with a newer one and tells the panel.
 * @param error The failure, with diagnostic fields only.
 */
export function publishPosError(error: IAgentPosErrorContext): void {
    latestVersion += 1;
    current = { version: latestVersion, error: { ...error }, reportedAt: Date.now() };
    helpRequestedVersion = 0;
    notify();
}

/** Forgets the failure, for example when the operation it was about succeeds. */
export function clearPosError(): void {
    if (current === null && helpRequestedVersion === 0) {
        return;
    }

    latestVersion += 1;
    current = null;
    helpRequestedVersion = 0;
    notify();
}

/**
 * Reads the failure, while it is recent.
 * @param now The time to measure its age against. Defaults to the current time.
 * @returns The failure and its version, or null when there is none or it is too old to matter.
 */
export function getPosError(now: number = Date.now()): IVersionedPosError | null {
    if (current !== null && now - current.reportedAt >= POS_ERROR_LIFETIME_MS) {
        current = null;
        helpRequestedVersion = 0;
    }

    return current;
}

/**
 * Asks the panel to get help with the current failure, as if the associate had chosen its help chip.
 * @returns True when there was a recent failure to ask about.
 */
export function requestPosErrorHelp(): boolean {
    const error: IVersionedPosError | null = getPosError();
    if (error === null) {
        return false;
    }

    helpRequestedVersion = error.version;
    notify();
    return true;
}

/**
 * Takes the waiting help request, if there is one, so it is handled only once.
 * @returns The failure to ask about, or null when no help was requested for the current failure.
 */
export function takePosErrorHelpRequest(): IVersionedPosError | null {
    const requestedVersion: number = helpRequestedVersion;
    helpRequestedVersion = 0;

    const error: IVersionedPosError | null = getPosError();
    return error !== null && error.version === requestedVersion ? error : null;
}

/**
 * Subscribes to failures being reported, cleared and asked about.
 * @param listener Called whenever any of them happens.
 * @returns A function that removes the subscription.
 */
export function subscribeToPosError(listener: Listener): () => void {
    listeners.add(listener);
    return () => {
        listeners.delete(listener);
    };
}
