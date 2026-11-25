// SPDX-License-Identifier: GPL-3.0-or-later
// Which of an app's windows a click on its icon goes to. It has no QML
// imports, so node can test it (test/windows.test.js).

// `windows` are the app's windows in the model's order, which does not change
// as they are used, as {active, lastActivated, stacking}. With one of them in
// front, the next one, so repeated clicks reach them all. Otherwise the one
// used last, or the topmost if none was ever used (lastActivated is NaN). The
// index of that window, or -1 if there are none. The same as Plasma's own
// task manager by default.
export function windowToActivate(windows) {
    const active = windows.findIndex(window => window.active);
    if (active !== -1)
        return (active + 1) % windows.length;
    for (const key of ['lastActivated', 'stacking']) {
        let best = -1;
        windows.forEach((window, i) => {
            if (Number.isFinite(window[key]) && (best === -1 || window[key] > windows[best][key]))
                best = i;
        });
        if (best !== -1)
            return best;
    }
    return windows.length > 0 ? 0 : -1;
}
