// Auto-scroll behavior for the chat messages list
// Auto-scroll behavior initialized
let isAutoScrolling = false;
/**
 * Sets --chat-viewport-height on the scroll container so that
 * .current-turn-section.has-messages can use it for min-height.
 */
function updateViewportHeight() {
    const scrollContainer = document.querySelector('.message-list-container');
    if (!scrollContainer) return;
    const scStyle = window.getComputedStyle(scrollContainer);
    const containerPaddingTop = parseFloat(scStyle.paddingTop);
    const containerPaddingBottom = parseFloat(scStyle.paddingBottom);
    const hasPrevious = !!document.querySelector('.previous-messages-section');
    const currentTurn = document.querySelector('.current-turn-section');
    const ctPaddingTop = currentTurn
        ? parseFloat(window.getComputedStyle(currentTurn).paddingTop)
        : 0;
    const height = hasPrevious
        ? scrollContainer.clientHeight - ctPaddingTop
        : scrollContainer.clientHeight - containerPaddingTop - containerPaddingBottom;
    scrollContainer.style.setProperty('--chat-viewport-height', height + 'px');
}
window.addEventListener('resize', updateViewportHeight);
function programmaticScrollTo(scrollContainer, options) {
    isAutoScrolling = true;
    scrollContainer.scrollTo(options);
    const delay = options.behavior === 'smooth' ? 500 : 50;
    setTimeout(() => { isAutoScrolling = false; }, delay);
}
/**
 * Scrolls to the bottom of the container — called on every new user message.
 * This reliably shows the new user message at the top of the visible area
 * because min-height on .current-turn-section.has-messages pushes it there.
 */
function scrollToBottom(smooth) {
    const scrollContainer = document.querySelector('.message-list-container');
    if (!scrollContainer) return;
    programmaticScrollTo(scrollContainer, {
        top: scrollContainer.scrollHeight,
        behavior: smooth ? 'smooth' : 'instant'
    });
}
window.scrollCurrentTurnToTop = function (smooth = true) {
    updateViewportHeight();
    scrollToBottom(smooth);
};
window.scrollCurrentTurnToTopForced = function () {
    updateViewportHeight();
    requestAnimationFrame(() => {
        requestAnimationFrame(() => {
            updateViewportHeight();
            scrollToBottom(true); // smooth animation
        });
    });
};
window.scrollChatToBottom = function (smooth = true) {
    scrollToBottom(smooth);
};
if (!window.customElements.get('chat-messages')) window.customElements.define('chat-messages', class ChatMessages extends HTMLElement {
    connectedCallback() {
        updateViewportHeight();
        setTimeout(() => window.scrollCurrentTurnToTopForced(), 100);
    }
    disconnectedCallback() { }
});
document.addEventListener('DOMContentLoaded', () => {
    setTimeout(() => {
        updateViewportHeight();
        window.scrollCurrentTurnToTopForced();
    }, 200);
});