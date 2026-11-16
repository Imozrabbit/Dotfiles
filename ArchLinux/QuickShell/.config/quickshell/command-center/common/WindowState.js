function toggleState(shown, currentScreenName, focusedScreenName) {
    return {
        shown: !shown,
        screenName: shown ? currentScreenName : focusedScreenName || currentScreenName
    };
}
