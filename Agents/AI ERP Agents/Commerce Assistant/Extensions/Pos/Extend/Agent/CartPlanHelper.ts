/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Turns the cart the agent planned from what a customer is shopping for, such as a beach vacation,
 * into a checklist the associate reviews in the side panel.
 *
 * The agent chooses the products and says why; POS reads every product from the channel itself, so
 * the names, prices and pictures shown are Commerce's. POS also keeps the plan to one product per need:
 * a product named twice, two variants of one product, or two products for the same need are left out,
 * so the customer never gets a cart of near-identical things. With a budget for each item, POS checks
 * the channel's prices against it and leaves anything over it unselected.
 *
 * Nothing is added to the sale here. The associate adds the products from the checklist.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ProxyEntities } from "PosApi/Entities";
import { StringExtensions } from "PosApi/TypeExtensions";
import {
    AgentCartBudgetScope,
    IAgentCartBudget,
    IAgentCartPlan,
    IAgentCartPlanItem,
    IAgentCartPlanReceipt,
    IAgentCartPlanReceiptItem,
    IAgentProductCard,
    IAgentProductSelection
} from "ContosoSideChat";
import { IResolvedProductCards, resolveProductCardsAsync } from "./ProductCardResolver";

/** The most products one plan shows. */
export const MAX_CART_PLAN_ITEMS: number = 8;

/** The longest texts shown, so a wordy plan cannot crowd the panel. */
const MAX_INTENT_LENGTH: number = 80;
const MAX_HEADLINE_LENGTH: number = 90;
const MAX_SUMMARY_LENGTH: number = 400;
const MAX_NEED_LENGTH: number = 40;
const MAX_REASON_LENGTH: number = 160;

/** Prices are compared to the budget to the cent. */
const PRICE_TOLERANCE: number = 0.005;

/** What POS made of the agent's plan. */
export interface ICartPlanExecutionResult {
    summary: string;
    receipt: IAgentCartPlanReceipt;
}

/**
 * Reads the products the agent planned from the channel and keeps one product per need.
 * @param plan The plan the agent returned.
 * @param productSelections The exact variants the agent chose for some of the products, if any.
 * @param context The POS extension context.
 * @returns The checklist for the panel, and a summary for the receipt.
 * @throws When the plan is incomplete or none of its products can be read from the channel.
 */
export async function buildCartPlanAsync(
    plan: IAgentCartPlan | undefined,
    productSelections: ReadonlyArray<IAgentProductSelection> | undefined,
    context: IExtensionContext
): Promise<ICartPlanExecutionResult> {
    if (!plan || typeof plan !== "object") {
        throw new Error("The cart plan was missing.");
    }

    const intent: string = shorten(plan.intent, MAX_INTENT_LENGTH);
    if (intent.length === 0) {
        throw new Error("The cart plan did not say what the customer is shopping for.");
    }

    const summary: string = shorten(plan.summary, MAX_SUMMARY_LENGTH);
    const requestedItems: ReadonlyArray<IAgentCartPlanItem> = Array.isArray(plan.items) ? plan.items : [];
    const items: IAgentCartPlanItem[] = keepOnePerNeed(requestedItems);
    if (items.length === 0) {
        throw new Error("The cart plan did not include any products.");
    }

    const selections: IAgentProductSelection[] = Array.isArray(productSelections)
        ? productSelections.filter((selection: IAgentProductSelection) =>
            !!selection && items.some((item: IAgentCartPlanItem) => item.productId === selection.productId))
        : [];
    const resolved: IResolvedProductCards = await resolveProductCardsAsync(
        items.map((item: IAgentCartPlanItem) => item.productId),
        context,
        selections);
    const budget: IAgentCartBudget | undefined = readBudget(plan.budget);
    const perItemLimit: number | undefined =
        budget && budget.appliesTo !== "total" ? budget.amount : undefined;

    const receiptItems: IAgentCartPlanReceiptItem[] = [];
    const seenProducts: { [key: string]: boolean } = {};
    items.forEach((item: IAgentCartPlanItem) => {
        if (receiptItems.length >= MAX_CART_PLAN_ITEMS) {
            return;
        }

        const card: IAgentProductCard | undefined = resolved.cards.filter(
            (candidate: IAgentProductCard) => candidate.recordId === item.productId)[0];
        if (!card) {
            return;
        }

        // Two variants of one product, or one product named by its master and by a variant, are the same thing.
        const keys: string[] = getProductKeys(card, resolved.productsByRecordId[card.recordId]);
        if (keys.some((key: string) => seenProducts[key])) {
            context.logger.logInformational(
                `Cart plan: left product ${card.recordId} out because the plan already has it or another variant of it.`);
            return;
        }

        keys.forEach((key: string) => {
            seenProducts[key] = true;
        });

        const receiptItem: IAgentCartPlanReceiptItem = { card: card, need: item.need, reason: item.reason };
        if (perItemLimit !== undefined && typeof card.price === "number" && card.price > perItemLimit + PRICE_TOLERANCE) {
            receiptItem.overBudget = true;
        }

        receiptItems.push(receiptItem);
    });

    if (receiptItems.length === 0) {
        throw new Error("None of the planned products could be read from the channel.");
    }

    const receipt: IAgentCartPlanReceipt = {
        intent: intent,
        summary: summary,
        items: receiptItems
    };

    const headline: string = shorten(plan.headline, MAX_HEADLINE_LENGTH);
    if (headline.length > 0) {
        receipt.headline = headline;
    }

    if (budget) {
        receipt.budget = budget;
    }

    const omittedCount: number = requestedItems.length - receiptItems.length;
    if (omittedCount > 0) {
        receipt.omittedCount = omittedCount;
        context.logger.logInformational(
            `Cart plan: showed ${receiptItems.length} of the ${requestedItems.length} products the agent planned.`);
    }

    return {
        summary: `Planned ${describeItemCount(receiptItems.length)} for ${intent.charAt(0).toLowerCase()}${intent.slice(1)}.`,
        receipt: receipt
    };
}

/**
 * Keeps the well-formed items, the first time each product and each need appears.
 * @param items The items the agent planned.
 * @returns The items to look up, in the agent's order, with their texts trimmed.
 */
function keepOnePerNeed(items: ReadonlyArray<IAgentCartPlanItem>): IAgentCartPlanItem[] {
    const kept: IAgentCartPlanItem[] = [];
    const seenProductIds: number[] = [];
    const seenNeeds: string[] = [];

    items.forEach((item: IAgentCartPlanItem) => {
        if (!item || typeof item.productId !== "number" || !isFinite(item.productId) || item.productId <= 0
            || Math.floor(item.productId) !== item.productId) {
            return;
        }

        const need: string = shorten(item.need, MAX_NEED_LENGTH);
        const needKey: string = need.toLowerCase();
        if (need.length === 0 || seenProductIds.indexOf(item.productId) >= 0 || seenNeeds.indexOf(needKey) >= 0) {
            return;
        }

        seenProductIds.push(item.productId);
        seenNeeds.push(needKey);
        kept.push({ productId: item.productId, need: need, reason: shorten(item.reason, MAX_REASON_LENGTH) });
    });

    return kept;
}

/**
 * Names a product the way another plan item could name the same product again: by its master product
 * and by its item number, which every variant of a product shares.
 */
function getProductKeys(card: IAgentProductCard, product: ProxyEntities.SimpleProduct | undefined): string[] {
    const masterId: number = product && typeof product.MasterProductId === "number" && product.MasterProductId > 0
        ? product.MasterProductId
        : card.recordId;
    const keys: string[] = [`master:${masterId}`];
    const itemId: string | undefined = product?.ItemId ?? card.itemId;
    if (typeof itemId === "string" && !StringExtensions.isNullOrWhitespace(itemId)) {
        keys.push(`item:${itemId.trim().toLowerCase()}`);
    }

    return keys;
}

/**
 * Reads the budget the agent passed on, if it is usable.
 * @param budget The budget from the plan.
 * @returns The budget, or undefined when there is none or it is not a positive amount.
 */
function readBudget(budget: IAgentCartBudget | undefined): IAgentCartBudget | undefined {
    if (!budget || typeof budget.amount !== "number" || !isFinite(budget.amount) || budget.amount <= 0) {
        return undefined;
    }

    const appliesTo: AgentCartBudgetScope = budget.appliesTo === "total" ? "total" : "eachItem";
    const read: IAgentCartBudget = { amount: budget.amount, appliesTo: appliesTo };
    if (typeof budget.currency === "string" && /^[A-Za-z]{3}$/.test(budget.currency.trim())) {
        read.currency = budget.currency.trim().toUpperCase();
    }

    return read;
}

function shorten(value: unknown, maxLength: number): string {
    if (typeof value !== "string") {
        return StringExtensions.EMPTY;
    }

    const text: string = value.replace(/\s+/g, " ").trim();
    return text.length > maxLength ? `${text.slice(0, maxLength - 1).trim()}\u2026` : text;
}

function describeItemCount(count: number): string {
    return count === 1 ? "1 item" : `${count} items`;
}
