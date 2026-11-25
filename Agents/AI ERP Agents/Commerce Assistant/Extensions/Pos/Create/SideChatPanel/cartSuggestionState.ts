/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Carries automatic cart checks from POS to the panel.
 *
 * POS asks for suggestions from a sale trigger, which lives outside React, so the request cannot be
 * component state. Only the newest request is kept: a cart that changed again before the panel got to
 * the previous request makes that request obsolete. Every request gets a version, which lets the panel
 * drop a reply for a cart that has changed since it asked.
 */

import { ICartSuggestionRequest } from "./sideChatClient";

/** A request waiting for the panel, with the version it was published as. */
export interface IVersionedCartSuggestionRequest {
    version: number;
    request: ICartSuggestionRequest;
}

type Listener = () => void;

let latestVersion: number = 0;
let pending: IVersionedCartSuggestionRequest | null = null;
const listeners = new Set<Listener>();

/**
 * Replaces any waiting request with a newer one and tells the panel.
 * @param request The cart to ask about.
 */
export function publishCartSuggestionRequest(request: ICartSuggestionRequest): void {
    latestVersion += 1;
    pending = { version: latestVersion, request };
    listeners.forEach((listener) => listener());
}

/**
 * Takes the waiting request, if there is one, so it is handled only once.
 * @returns The request and its version, or null when nothing is waiting.
 */
export function takeCartSuggestionRequest(): IVersionedCartSuggestionRequest | null {
    const request: IVersionedCartSuggestionRequest | null = pending;
    pending = null;
    return request;
}

/**
 * Reads the version of the newest request ever published.
 * @returns The version. A reply for any older version is for a cart that has changed since.
 */
export function getLatestCartSuggestionVersion(): number {
    return latestVersion;
}

/**
 * Drops the waiting request and makes every reply still in flight obsolete. Called when the panel is
 * torn down, so a check started for one operator never reaches the next one.
 */
export function clearCartSuggestionRequests(): void {
    latestVersion += 1;
    pending = null;
}

/**
 * Subscribes to newly published requests.
 * @param listener Called whenever a request is published.
 * @returns A function that removes the subscription.
 */
export function subscribeToCartSuggestionRequests(listener: Listener): () => void {
    listeners.add(listener);
    return () => {
        listeners.delete(listener);
    };
}
