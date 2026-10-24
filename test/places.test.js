// SPDX-License-Identifier: GPL-3.0-or-later
// Run from the repository root with: node --test
import assert from 'node:assert/strict';
import {test} from 'node:test';

import {parsePlaces} from '../package/contents/ui/places.mjs';

// The shape Dolphin writes to ~/.local/share/user-places.xbel.
function bookmark({href, title, icon, system = false, hidden = false}) {
    return `
 <bookmark href="${href}">
  <title>${title}</title>
  <info>
   <metadata owner="http://freedesktop.org">
    <bookmark:icon name="${icon}"/>
   </metadata>
   <metadata owner="http://www.kde.org">
    <ID>1792790340/0</ID>${system ? '\n    <isSystemItem>true</isSystemItem>' : ''}${hidden ? '\n    <IsHidden>true</IsHidden>' : ''}
   </metadata>
  </info>
 </bookmark>`;
}

function xbel(...bookmarks) {
    return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xbel>
<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks">
 <info>
  <metadata owner="http://www.kde.org">
   <kde_places_version>4</kde_places_version>
  </metadata>
 </info>${bookmarks.join('')}
</xbel>`;
}

test('local folders come in the order Dolphin shows them, with their icons', () => {
    const places = parsePlaces(xbel(
        bookmark({href: 'file:///home/ana', title: 'Home', icon: 'user-home', system: true}),
        bookmark({href: 'file:///home/ana/Documents', title: 'Documents', icon: 'folder-documents', system: true}),
        bookmark({href: 'file:///home/ana/Projects', title: 'Projects', icon: 'folder'})));
    assert.deepEqual(places, [
        {name: 'Home', icon: 'user-home', url: 'file:///home/ana', system: true},
        {name: 'Documents', icon: 'folder-documents', url: 'file:///home/ana/Documents', system: true},
        {name: 'Projects', icon: 'folder', url: 'file:///home/ana/Projects', system: false},
    ]);
});

test('hidden places and places that are not local folders are left out', () => {
    const places = parsePlaces(xbel(
        bookmark({href: 'file:///home/ana', title: 'Home', icon: 'user-home', system: true}),
        bookmark({href: 'file:///home/ana/Music', title: 'Music', icon: 'folder-music', system: true, hidden: true}),
        bookmark({href: 'remote:/', title: 'Network', icon: 'folder-network', system: true}),
        bookmark({href: 'trash:/', title: 'Trash', icon: 'user-trash', system: true}),
        bookmark({href: 'recentlyused:/files', title: 'Recent Files', icon: 'document-open-recent', system: true})));
    assert.deepEqual(places.map(place => place.url), ['file:///home/ana']);
});

test('XML escapes in titles and URLs are decoded', () => {
    const places = parsePlaces(xbel(
        bookmark({href: 'file:///home/ana/R%26D', title: 'R&amp;D &lt;old&gt;', icon: 'folder'})));
    assert.equal(places[0].name, 'R&D <old>');
    assert.equal(places[0].url, 'file:///home/ana/R%26D');
});

test('a place with no title is named after its folder, and one with no icon gets a folder icon', () => {
    const places = parsePlaces(xbel(
        ' <bookmark href="file:///home/ana/Code%20Base">\n  <title></title>\n </bookmark>'));
    assert.deepEqual(places, [{name: 'Code Base', icon: 'folder', url: 'file:///home/ana/Code%20Base', system: false}]);
});

test('an empty or unreadable file gives no places', () => {
    assert.deepEqual(parsePlaces(''), []);
    assert.deepEqual(parsePlaces('not xml at all'), []);
});
