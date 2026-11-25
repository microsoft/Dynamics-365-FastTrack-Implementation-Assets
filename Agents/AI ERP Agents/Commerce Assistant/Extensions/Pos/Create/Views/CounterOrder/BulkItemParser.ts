/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Reads a pasted list of item IDs and quantities the way the POS bulk item entry dialog does, so the counter
 * order accepts the same lists and reports the same mistakes.
 *
 * Each line holds one or more "item ID quantity" pairs. A pair is separated by spaces or a comma, and the
 * quantity may carry an x, as in "ABC x3". ':' or '|' may separate pairs on one line; ';', '/' and '.' may
 * not. A first line such as "Item,Quantity" is skipped as a CSV header. Repeated item IDs are kept.
 */

/**
 * Parsed SKU and quantity for one user-entered bulk item pair.
 */
export interface IBulkLineParseResult {
    /** Original line number in the user's raw input (1-based, post-CSV-skip). */
    readonly lineNumber: number;
    /** The original text of the line as the user typed it. */
    readonly rawText: string;
    /** SKU / Item ID as typed (preserved verbatim: case, leading zeros, etc.). */
    readonly sku: string;
    /** Parsed quantity, a positive integer no larger than MAX_BULK_QUANTITY. */
    readonly quantity: number;
}

/** What is wrong with a line or pair that could not be read. */
export type BulkLineParseErrorKind =
    "unparsable" | "quantityLessThanOne" | "multiPairDelimiter" | "integerSkuRequiresXQty" | "noQuantityFound" | "pairDelimiterMisuse";

/**
 * Parse error for one user-entered bulk item line.
 */
export interface IBulkLineParseError {
    /** Original line number in the user's raw input (1-based, post-CSV-skip). */
    readonly lineNumber: number;
    /** The original text of the line as the user typed it. */
    readonly rawText: string;
    /** SKU if it could be extracted; otherwise undefined. */
    readonly sku?: string;
    /** Misused pair-delimiter character(s) for the "pairDelimiterMisuse" kind; otherwise undefined. */
    readonly delimiter?: string;
    /**
     * Text of just this failing pair (or the unparsed remainder of the line), used to rebuild the list with
     * only the failing pairs. Undefined for line-level errors, where the whole line text is restored.
     */
    readonly pairText?: string;
    /** Which message to show. */
    readonly kind: BulkLineParseErrorKind;
}

/**
 * Result of parsing a bulk item input block.
 */
export interface IBulkParseResult {
    /** Parsed bulk item lines. Duplicate SKUs are intentionally preserved. */
    readonly lines: IBulkLineParseResult[];
    /** Line-level parse errors. */
    readonly errors: IBulkLineParseError[];
    /** True if the parser dropped the first line as a CSV header. */
    readonly csvHeaderSkipped: boolean;
}

/**
 * Quantity token metadata parsed from a user-entered token.
 */
interface IQuantityToken {
    /** Parsed numeric quantity value. */
    readonly quantity: number;
    /** True when the token is a positive integer greater than or equal to one. */
    readonly isValid: boolean;
    /** True when the quantity used the x-prefix modifier. */
    readonly hasXPrefix: boolean;
}

/**
 * Accumulator used while parsing one source line.
 */
interface ILineParseAccumulator {
    /** Parsed bulk item lines collected for the source line. */
    readonly lines: IBulkLineParseResult[];
    /** Parse errors collected for the source line. */
    readonly errors: IBulkLineParseError[];
}

/** Matches Windows, Unix, and old Mac line breaks. */
const LINE_SEPARATOR_PATTERN: RegExp = /\r\n|\n|\r/;
/** Matches separators eligible for first-line CSV header detection. */
const CSV_HEADER_SEPARATOR_PATTERN: RegExp = /[,\t|]/g;
/** Matches pair-boundary-only separators. */
const PAIR_BOUNDARY_SEPARATOR_PATTERN: RegExp = /[:|]+/;
/** Matches separators that may appear inside a pair or between adjacent pairs. */
const PAIR_TOKEN_SEPARATOR_PATTERN: RegExp = /[\s,]+/;
/** Matches delimiters that are not allowed between multiple pairs on one line. */
const DISALLOWED_MULTI_PAIR_SEPARATOR_PATTERN: RegExp = /[;/.]+/g;
/** Matches integer tokens without a sign. */
const POSITIVE_INTEGER_PATTERN: RegExp = /^\d+$/;
/** Matches numeric tokens that are quantity-like even when invalid. */
const NUMERIC_QUANTITY_PATTERN: RegExp = /^-?\d+(?:\.\d+)?$/;
/** Matches lowercase or uppercase x-prefixed integer quantity tokens. */
const X_PREFIX_QUANTITY_PATTERN: RegExp = /^[xX]\d+$/;

/** Largest quantity a single bulk line may add. */
export const MAX_BULK_QUANTITY: number = 1000000;

/**
 * Parses raw bulk item input into SKU/quantity pairs and line-level errors.
 * @param rawText The raw text entered or pasted by the user.
 * @returns The parsed lines, errors, and CSV header skip metadata.
 */
export function parseBulkItemInput(rawText: string): IBulkParseResult {
    const nonEmptyLines: string[] = (rawText || "")
        .split(LINE_SEPARATOR_PATTERN)
        .map((line: string): string => line.trim())
        .filter((line: string): boolean => line.length > 0);
    const csvHeaderSkipped: boolean = nonEmptyLines.length > 0 && isCsvHeaderLine(nonEmptyLines[0]);
    const linesToParse: string[] = csvHeaderSkipped ? nonEmptyLines.slice(1) : nonEmptyLines;
    const lines: IBulkLineParseResult[] = [];
    const errors: IBulkLineParseError[] = [];

    linesToParse.forEach((line: string, index: number): void => {
        const parsedLine: ILineParseAccumulator = parseLine(line, index + 1);

        lines.push(...parsedLine.lines);
        errors.push(...parsedLine.errors);
    });

    return { lines: lines, errors: errors, csvHeaderSkipped: csvHeaderSkipped };
}

/**
 * Determines whether the first non-empty line is an alphabetic-leaning CSV header.
 * @param line The trimmed line to inspect.
 * @returns True when the line should be skipped as a header; otherwise false.
 */
function isCsvHeaderLine(line: string): boolean {
    const separators: string[] = line.match(CSV_HEADER_SEPARATOR_PATTERN) ?? [];

    if (separators.length !== 1) {
        return false;
    }

    const parts: string[] = line.split(CSV_HEADER_SEPARATOR_PATTERN).map((part: string): string => part.trim());

    return parts.length === 2 && isAlphabeticLeaningHeaderToken(parts[0]) && isAlphabeticLeaningHeaderToken(parts[1]);
}

/**
 * Parses one trimmed non-empty line.
 * @param rawText The trimmed raw line text.
 * @param lineNumber The 1-based non-empty line number after optional header skip.
 * @returns Parsed line entries and errors.
 */
function parseLine(rawText: string, lineNumber: number): ILineParseAccumulator {
    if (hasDisallowedMultiPairDelimiter(rawText)) {
        return { lines: [], errors: [{ lineNumber: lineNumber, rawText: rawText, kind: "multiPairDelimiter" }] };
    }

    const segments: string[] = rawText
        .split(PAIR_BOUNDARY_SEPARATOR_PATTERN)
        .map((segment: string): string => segment.trim())
        .filter((segment: string): boolean => segment.length > 0);

    // When ':' or '|' split the line but a resulting segment is not a complete pair, the delimiter was almost
    // certainly used between an item ID and its quantity (e.g. "A:5 B:3"). Pairing tokens across it would add
    // the wrong item, so the whole line is rejected instead.
    if (segments.length > 1 && segments.some((segment: string): boolean => !isCompletePairSegment(segment))) {
        return {
            lines: [],
            errors: [{
                lineNumber: lineNumber,
                rawText: rawText,
                delimiter: extractMisusedPairDelimiter(rawText),
                kind: "pairDelimiterMisuse"
            }]
        };
    }

    // Each segment is an independent pair with its own text, so an error on one pair (and the rebuilt list)
    // refers only to that pair, not the whole multi-pair line.
    const accumulator: ILineParseAccumulator = { lines: [], errors: [] };
    segments.forEach((segment: string): void => {
        const parsedSegment: ILineParseAccumulator = parseTokens(splitPairTokens(segment), lineNumber, segment);

        accumulator.lines.push(...parsedSegment.lines);
        accumulator.errors.push(...parsedSegment.errors);
    });

    return accumulator;
}

/**
 * Determines whether a line uses a disallowed delimiter between two or more pair-shaped entries.
 * @param rawText The trimmed raw line text.
 * @returns True when a disallowed multi-pair delimiter is present; otherwise false.
 */
function hasDisallowedMultiPairDelimiter(rawText: string): boolean {
    if (!DISALLOWED_MULTI_PAIR_SEPARATOR_PATTERN.test(rawText)) {
        return false;
    }

    DISALLOWED_MULTI_PAIR_SEPARATOR_PATTERN.lastIndex = 0;
    const normalizedLine: string = rawText.replace(DISALLOWED_MULTI_PAIR_SEPARATOR_PATTERN, " ");
    const parsedLine: ILineParseAccumulator = parseTokens(
        normalizedLine.split(/[\s,|:]+/).filter((token: string): boolean => token.length > 0),
        1,
        normalizedLine);
    const pairLikeCount: number = parsedLine.lines.length + parsedLine.errors.filter(
        (error: IBulkLineParseError): boolean => error.kind === "quantityLessThanOne" || error.kind === "integerSkuRequiresXQty").length;

    return pairLikeCount >= 2;
}

/**
 * Determines whether a colon/pipe-delimited segment is a complete pair, as opposed to an orphan token left by
 * a misused ':' or '|'.
 * @param segment The trimmed segment to inspect.
 * @returns True when the segment can form a pair on its own; otherwise false.
 */
function isCompletePairSegment(segment: string): boolean {
    return splitPairTokens(segment).length >= 2;
}

function splitPairTokens(segment: string): string[] {
    return segment.split(PAIR_TOKEN_SEPARATOR_PATTERN).filter((token: string): boolean => token.length > 0);
}

/**
 * Parses a token array into one or more SKU/quantity pairs.
 * @param tokens The ordered token list.
 * @param lineNumber The source line number.
 * @param rawText The text the tokens came from, used for messages and line-level error text.
 * @returns Parsed entries and errors.
 */
function parseTokens(tokens: string[], lineNumber: number, rawText: string): ILineParseAccumulator {
    const lines: IBulkLineParseResult[] = [];
    const errors: IBulkLineParseError[] = [];

    for (let index: number = 0; index < tokens.length;) {
        // A give-up error is scoped to the unparsed remainder of the line, never the whole line, so a sibling
        // pair from the same line that was already added is not restored to the list.
        if (index + 1 >= tokens.length) {
            errors.push({ lineNumber: lineNumber, rawText: rawText, kind: "unparsable", pairText: tokens.slice(index).join(" ") });
            break;
        }

        const parsedPair: IBulkLineParseResult | IBulkLineParseError | undefined =
            parseTwoTokenPair(tokens[index], tokens[index + 1], lineNumber, rawText);

        if (parsedPair === undefined) {
            errors.push({ lineNumber: lineNumber, rawText: rawText, kind: "noQuantityFound", pairText: tokens.slice(index).join(" ") });
            break;
        }

        if ("quantity" in parsedPair) {
            lines.push(parsedPair);
        } else {
            errors.push({ ...parsedPair, pairText: `${tokens[index]} ${tokens[index + 1]}` });
        }

        index += 2;
    }

    return { lines: lines, errors: errors };
}

/**
 * Parses a two-token SKU/quantity pair.
 * @param firstToken The SKU token.
 * @param secondToken The quantity token.
 * @param lineNumber The source line number.
 * @param rawText The text the tokens came from.
 * @returns A parsed pair, a quantity error, or undefined when the tokens cannot form a pair.
 */
function parseTwoTokenPair(
    firstToken: string,
    secondToken: string,
    lineNumber: number,
    rawText: string
): IBulkLineParseResult | IBulkLineParseError | undefined {
    const firstQuantity: IQuantityToken | undefined = parseQuantityToken(firstToken);
    const secondQuantity: IQuantityToken | undefined = parseQuantityToken(secondToken);

    if (firstQuantity?.hasXPrefix === true) {
        // "x3 12345" reads as a quantity before an item ID; only an integer item ID gets the specific message.
        return POSITIVE_INTEGER_PATTERN.test(secondToken)
            ? { lineNumber: lineNumber, rawText: rawText, kind: "integerSkuRequiresXQty" }
            : undefined;
    }

    if (secondQuantity === undefined) {
        return undefined;
    }

    if (!secondQuantity.isValid) {
        return { lineNumber: lineNumber, rawText: rawText, sku: firstToken, kind: "quantityLessThanOne" };
    }

    return { lineNumber: lineNumber, rawText: rawText, sku: firstToken, quantity: secondQuantity.quantity };
}

/**
 * Parses a quantity token, including the x-prefix (x/X) modifier.
 * @param token The token to parse.
 * @returns Quantity metadata, or undefined when the token is not quantity-like.
 */
function parseQuantityToken(token: string): IQuantityToken | undefined {
    if (X_PREFIX_QUANTITY_PATTERN.test(token)) {
        return createQuantityToken(token.substring(1), true);
    }

    if (NUMERIC_QUANTITY_PATTERN.test(token)) {
        return createQuantityToken(token, false);
    }

    return undefined;
}

function createQuantityToken(token: string, hasXPrefix: boolean): IQuantityToken {
    const quantity: number = Number(token);

    return { quantity: quantity, isValid: isPositiveInteger(token) && quantity >= 1, hasXPrefix: hasXPrefix };
}

/**
 * Extracts the distinct pair-boundary delimiter character(s) (':' or '|') in a line, so the error can name
 * the delimiter to replace with a space.
 * @param rawText The full trimmed source line.
 * @returns The distinct delimiters, comma-joined (for example ":" or ":, |").
 */
function extractMisusedPairDelimiter(rawText: string): string {
    const found: string[] = rawText.match(/[:|]/g) ?? [];
    return found.filter((delimiter: string, index: number): boolean => found.indexOf(delimiter) === index).join(", ");
}

/**
 * Determines whether a token is a positive integer within the allowed quantity range.
 * @param token The token to inspect.
 * @returns True when the token is a positive integer in [1, MAX_BULK_QUANTITY]; otherwise false.
 */
function isPositiveInteger(token: string): boolean {
    if (!POSITIVE_INTEGER_PATTERN.test(token)) {
        return false;
    }

    const value: number = Number(token);
    return value >= 1 && value <= MAX_BULK_QUANTITY;
}

/**
 * Determines whether a token looks like CSV header text rather than item data.
 * @param token The token to inspect.
 * @returns True when the token is alphabetic-leaning header text; otherwise false.
 */
function isAlphabeticLeaningHeaderToken(token: string): boolean {
    return /[A-Za-z]/.test(token) && !/\d/.test(token);
}
