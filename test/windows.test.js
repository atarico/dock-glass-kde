// SPDX-License-Identifier: GPL-3.0-or-later
// Run from the repository root with: node --test
import assert from 'node:assert/strict';
import {test} from 'node:test';

import {windowToActivate} from '../package/contents/ui/windows.mjs';

const win = (over = {}) => ({active: false, lastActivated: NaN, stacking: -1, ...over});

test('with none in front, the window used last, however they are stacked', () => {
    assert.equal(windowToActivate([
        win({lastActivated: 10, stacking: 9}), win({lastActivated: 30, stacking: 1}), win({lastActivated: 20}),
    ]), 1);
});

test('with one in front, the next one, wrapping round', () => {
    assert.equal(windowToActivate([win(), win({active: true}), win()]), 2);
    assert.equal(windowToActivate([win(), win(), win({active: true})]), 0);
    // Not the one used last: that changes with every click.
    assert.equal(windowToActivate([
        win({active: true, lastActivated: 50}), win({lastActivated: 1}), win({lastActivated: 40}),
    ]), 1);
});

test('repeated clicks reach every window', () => {
    const seen = new Set();
    let front = 0;
    for (let i = 0; i < 4; i++) {
        front = windowToActivate([0, 1, 2, 3].map(n => win({active: n === front})));
        seen.add(front);
    }
    assert.deepEqual([...seen].sort(), [0, 1, 2, 3]);
});

test('windows that were never used: the topmost, after any that was used', () => {
    assert.equal(windowToActivate([win({stacking: 2}), win({stacking: 8}), win({stacking: 4})]), 1);
    assert.equal(windowToActivate([win({lastActivated: 3, stacking: 1}), win({stacking: 9})]), 0);
});

test('with nothing known, still a window; with no windows, none', () => {
    const unknown = {lastActivated: undefined, stacking: undefined};
    assert.equal(windowToActivate([win(unknown), win(unknown)]), 0);
    assert.equal(windowToActivate([]), -1);
});
