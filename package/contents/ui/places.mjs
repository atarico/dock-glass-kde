// SPDX-License-Identifier: GPL-3.0-or-later
// The places of the Files stack, read from the bookmarks Dolphin keeps in
// ~/.local/share/user-places.xbel. It has no QML imports, so node can test it
// (test/places.test.js).

function decode(text) {
    return text
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&amp;/g, '&');
}

// The local folders among the places, in Dolphin's order, as
// {name, icon, url, system}. System places (Home, Documents and the like)
// carry English titles that KIO translates when it shows them, so `system`
// tells the caller to do the same. Hidden places and the ones that are not
// folders on this computer (Network, Trash, recent files) are left out.
export function parsePlaces(xbel) {
    const places = [];
    // An exec() loop rather than matchAll(), which QML's engine may lack.
    const bookmark = /<bookmark\s+href="([^"]*)"\s*>([\s\S]*?)<\/bookmark>/g;
    for (let match; (match = bookmark.exec(xbel)) !== null;) {
        const [, url, body] = match;
        if (!url.startsWith('file://') || /<IsHidden>\s*true\s*<\/IsHidden>/.test(body))
            continue;
        const title = decode(body.match(/<title>([\s\S]*?)<\/title>/)?.[1].trim() ?? '');
        const folder = decodeURIComponent(url.replace(/\/+$/, '').split('/').pop() ?? '');
        places.push({
            name: title || folder,
            icon: body.match(/<bookmark:icon\s+name="([^"]*)"/)?.[1] || 'folder',
            url: decode(url),
            system: /<isSystemItem>\s*true\s*<\/isSystemItem>/.test(body),
        });
    }
    return places;
}
