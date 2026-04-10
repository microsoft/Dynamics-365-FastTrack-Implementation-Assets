const STORAGE_KEY = "copilot-agent-profiles";

export function loadAgentProfiles() {
    try {
        const data = localStorage.getItem(STORAGE_KEY);
        return data ? JSON.parse(data) : [];
    } catch {
        return [];
    }
}

export function saveAgentProfiles(profiles) {
    try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(profiles));
    } catch {
        // localStorage may be unavailable
    }
}
