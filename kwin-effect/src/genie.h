/*
    Dock Glass Genie: the first window of an app pours out of its dock icon.

    SPDX-FileCopyrightText: 2008 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2026 atarico

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "effect/effectwindow.h"
#include "effect/offscreeneffect.h"
#include "effect/timeline.h"

#include <QElapsedTimer>

namespace KWin
{

struct GenieAnimation
{
    // 1 is inside the icon, 0 is the window at its place, as in Magic Lamp.
    TimeLine timeLine;
    // Since the window was added, while it waits for its icon geometry.
    QElapsedTimer waiting;
    bool started = false;
};

class GenieEffect : public OffscreenEffect
{
    Q_OBJECT

public:
    GenieEffect();

    void reconfigure(ReconfigureFlags) override;
    void prePaintScreen(ScreenPrePaintData &data) override;
    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data) override;
    void postPaintScreen() override;
    bool isActive() const override;

    int requestedEffectChainPosition() const override
    {
        // Next to Magic Lamp, which uses 50.
        return 50;
    }

    static bool supported();

protected:
    void apply(EffectWindow *window, int mask, WindowPaintData &data, WindowQuadList &quads) override;

private:
    void slotWindowAdded(EffectWindow *w);
    void slotWindowDeleted(EffectWindow *w);
    bool isFirstWindowOfApp(EffectWindow *w) const;
    void finish(EffectWindow *w);

    std::chrono::milliseconds m_duration;
    QHash<EffectWindow *, GenieAnimation> m_animations;

    enum IconPosition {
        Top,
        Bottom,
        Left,
        Right,
    };
};

} // namespace KWin
