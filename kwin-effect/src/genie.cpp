/*
    Dock Glass Genie: the first window of an app pours out of its dock icon,
    the same way Magic Lamp restores a minimized window. The deformation is
    Magic Lamp's, from KWin 6.8.1 (src/plugins/magiclamp/magiclamp.cpp), run
    from the icon to the window.

    SPDX-FileCopyrightText: 2008 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2026 atarico

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// based on minimize animation by Rivo Laks <rivolaks@hot.ee>

#include "genie.h"
#include "effect/effecthandler.h"

using namespace std::chrono_literals;

namespace KWin
{

// How long a new window may wait, hidden, for the dock to publish its icon
// geometry. Without one by then, it is shown as it is.
static constexpr qint64 s_iconWaitMs = 400;

GenieEffect::GenieEffect()
{
    reconfigure(ReconfigureAll);
    connect(effects, &EffectsHandler::windowAdded, this, &GenieEffect::slotWindowAdded);
    connect(effects, &EffectsHandler::windowDeleted, this, &GenieEffect::slotWindowDeleted);

    setVertexSnappingMode(RenderGeometry::VertexSnappingMode::None);
}

bool GenieEffect::supported()
{
    return OffscreenEffect::supported() && effects->animationsSupported();
}

void GenieEffect::reconfigure(ReconfigureFlags)
{
    // Magic Lamp's default, so opening matches minimizing and restoring.
    m_duration = animationTime(250ms);
}

void GenieEffect::prePaintScreen(ScreenPrePaintData &data)
{
    // We need to mark the screen windows as transformed. Otherwise the
    // whole screen won't be repainted, resulting in artefacts.
    data.mask |= PAINT_SCREEN_WITH_TRANSFORMED_WINDOWS;

    effects->prePaintScreen(data);
}

void GenieEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data)
{
    auto animationIt = m_animations.find(w);
    if (animationIt != m_animations.end()) {
        GenieAnimation &animation = *animationIt;
        if (!animation.started && w->iconGeometry().isValid()) {
            animation.started = true;
        }
        if (animation.started) {
            animation.timeLine.advance(view);
        }
        data.setTransformed();
    }

    effects->prePaintWindow(view, w, data);
}

void GenieEffect::apply(EffectWindow *w, int, WindowPaintData &data, WindowQuadList &quads)
{
    auto animationIt = m_animations.constFind(w);
    if (animationIt == m_animations.constEnd()) {
        return;
    }
    // Hidden until the dock says where its icon is.
    if (!(*animationIt).started) {
        data.setOpacity(0.0);
        return;
    }

    // 0 = at its place, 1 = inside the icon
    const qreal progress = (*animationIt).timeLine.value();

    Rect geo = w->frameGeometry().toRect();
    Rect icon = w->iconGeometry().toRect();
    IconPosition position = Top;

    // Assumption: there is a panel containing the icon position
    EffectWindow *panel = nullptr;
    const auto stackingOrder = effects->stackingOrder();
    for (EffectWindow *window : stackingOrder) {
        if (!window->isDock()) {
            continue;
        }
        // we have to use intersects as there seems to be a Plasma bug
        // the published icon geometry might be bigger than the panel
        if (window->frameGeometry().intersects(icon)) {
            panel = window;
            break;
        }
    }
    if (panel) {
        // Assumption: width of horizontal panel is greater than its height and vice versa
        const RectF windowScreen = effects->clientArea(ScreenArea, w);

        if (panel->width() >= panel->height()) {
            // horizontal panel
            if (icon.verticalCenter() <= windowScreen.verticalCenter()) {
                position = Top;
            } else {
                position = Bottom;
            }
        } else {
            // vertical panel
            if (icon.horizontalCenter() <= windowScreen.horizontalCenter()) {
                position = Left;
            } else {
                position = Right;
            }
        }

        // If the panel is hidden, move the icon offscreen so the animation looks correct.
        if (panel->isHidden()) {
            const RectF panelScreen = effects->clientArea(ScreenArea, panel);
            switch (position) {
            case Bottom:
                icon.moveTop(panelScreen.y() + panelScreen.height());
                break;
            case Top:
                icon.moveTop(panelScreen.y() - icon.height());
                break;
            case Left:
                icon.moveLeft(panelScreen.x() - icon.width());
                break;
            case Right:
                icon.moveLeft(panelScreen.x() + panelScreen.width());
                break;
            }
        }
    } else {
        // we did not find a panel, so it might be autohidden
        RectF iconScreen = effects->clientArea(ScreenArea, icon.topLeft());
        // as the icon geometry could be overlap a screen edge we use an intersection
        RectF rect = iconScreen.intersected(icon);
        // here we need a different assumption: icon geometry borders one screen edge
        // this assumption might be wrong for e.g. task applet being the only applet in panel
        // in this case the icon borders two screen edges
        // there might be a wrong animation, but not distorted
        if (rect.left() == iconScreen.left()) {
            position = Left;
        } else if (rect.right() == iconScreen.right()) {
            position = Right;
        } else if (rect.top() == iconScreen.top()) {
            position = Top;
        } else {
            position = Bottom;
        }
    }

    quads = quads.makeGrid(40);
    float quadFactor; // defines how fast a quad is vertically moved: y coordinates near to window top are slowed down
                      // it is used as quadFactor^3/windowHeight^3
                      // quadFactor is the y position of the quad but is changed towards becoming the window height
                      // by that the factor becomes 1 and has no influence any more
    float offset[2] = {0, 0}; // how far has a quad to be moved? Distance between icon and window multiplied by the progress and by the quadFactor
    float p_progress[2] = {0, 0}; // the factor which defines how far the x values have to be changed
                                  // factor is the current moved y value diveded by the distance between icon and window
    WindowQuad lastQuad;
    lastQuad[0].setX(-1);
    lastQuad[0].setY(-1);
    lastQuad[1].setX(-1);
    lastQuad[1].setY(-1);
    lastQuad[2].setX(-1);
    lastQuad[2].setY(-1);

    if (position == Bottom) {
        const float height_cube = float(geo.height()) * float(geo.height()) * float(geo.height());
        const float maxY = icon.y() - geo.y();

        for (WindowQuad &quad : quads) {
            if (quad[0].y() != lastQuad[0].y() || quad[2].y() != lastQuad[2].y()) {
                quadFactor = quad[0].y() + (geo.height() - quad[0].y()) * progress;
                offset[0] = (icon.y() + quad[0].y() - geo.y()) * progress * ((quadFactor * quadFactor * quadFactor) / height_cube);
                quadFactor = quad[2].y() + (geo.height() - quad[2].y()) * progress;
                offset[1] = (icon.y() + quad[2].y() - geo.y()) * progress * ((quadFactor * quadFactor * quadFactor) / height_cube);
                p_progress[1] = std::min(offset[1] / (icon.y() - geo.y() - float(quad[2].y())), 1.0f);
                p_progress[0] = std::min(offset[0] / (icon.y() - geo.y() - float(quad[0].y())), 1.0f);
            } else {
                lastQuad = quad;
            }

            p_progress[0] = std::abs(p_progress[0]);
            p_progress[1] = std::abs(p_progress[1]);

            // x values are moved towards the center of the icon
            quad[0].setX((icon.x() + icon.width() * (quad[0].x() / geo.width()) - (quad[0].x() + geo.x())) * p_progress[0] + quad[0].x());
            quad[1].setX((icon.x() + icon.width() * (quad[1].x() / geo.width()) - (quad[1].x() + geo.x())) * p_progress[0] + quad[1].x());
            quad[2].setX((icon.x() + icon.width() * (quad[2].x() / geo.width()) - (quad[2].x() + geo.x())) * p_progress[1] + quad[2].x());
            quad[3].setX((icon.x() + icon.width() * (quad[3].x() / geo.width()) - (quad[3].x() + geo.x())) * p_progress[1] + quad[3].x());

            quad[0].setY(std::min(maxY, float(quad[0].y()) + offset[0]));
            quad[1].setY(std::min(maxY, float(quad[1].y()) + offset[0]));
            quad[2].setY(std::min(maxY, float(quad[2].y()) + offset[1]));
            quad[3].setY(std::min(maxY, float(quad[3].y()) + offset[1]));
        }
    } else if (position == Top) {
        const float height_cube = float(geo.height()) * float(geo.height()) * float(geo.height());
        const float minY = icon.y() + icon.height() - geo.y();

        for (WindowQuad &quad : quads) {
            if (quad[0].y() != lastQuad[0].y() || quad[2].y() != lastQuad[2].y()) {
                quadFactor = geo.height() - quad[0].y() + (quad[0].y()) * progress;
                offset[0] = (geo.y() - icon.height() + geo.height() + quad[0].y() - icon.y()) * progress * ((quadFactor * quadFactor * quadFactor) / height_cube);
                quadFactor = geo.height() - quad[2].y() + (quad[2].y()) * progress;
                offset[1] = (geo.y() - icon.height() + geo.height() + quad[2].y() - icon.y()) * progress * ((quadFactor * quadFactor * quadFactor) / height_cube);
                p_progress[0] = std::min(offset[0] / (geo.y() - icon.height() + geo.height() - icon.y() - float(geo.height() - quad[0].y())), 1.0f);
                p_progress[1] = std::min(offset[1] / (geo.y() - icon.height() + geo.height() - icon.y() - float(geo.height() - quad[2].y())), 1.0f);
            } else {
                lastQuad = quad;
            }

            offset[0] = -offset[0];
            offset[1] = -offset[1];

            p_progress[0] = std::abs(p_progress[0]);
            p_progress[1] = std::abs(p_progress[1]);

            // x values are moved towards the center of the icon
            quad[0].setX((icon.x() + icon.width() * (quad[0].x() / geo.width()) - (quad[0].x() + geo.x())) * p_progress[0] + quad[0].x());
            quad[1].setX((icon.x() + icon.width() * (quad[1].x() / geo.width()) - (quad[1].x() + geo.x())) * p_progress[0] + quad[1].x());
            quad[2].setX((icon.x() + icon.width() * (quad[2].x() / geo.width()) - (quad[2].x() + geo.x())) * p_progress[1] + quad[2].x());
            quad[3].setX((icon.x() + icon.width() * (quad[3].x() / geo.width()) - (quad[3].x() + geo.x())) * p_progress[1] + quad[3].x());

            quad[0].setY(std::max(minY, float(quad[0].y()) + offset[0]));
            quad[1].setY(std::max(minY, float(quad[1].y()) + offset[0]));
            quad[2].setY(std::max(minY, float(quad[2].y()) + offset[1]));
            quad[3].setY(std::max(minY, float(quad[3].y()) + offset[1]));
        }
    } else if (position == Left) {
        const float width_cube = float(geo.width()) * float(geo.width()) * float(geo.width());
        const float minX = icon.x() + icon.width() - geo.x();

        for (WindowQuad &quad : quads) {
            if (quad[0].x() != lastQuad[0].x() || quad[1].x() != lastQuad[1].x()) {
                quadFactor = geo.width() - quad[0].x() + (quad[0].x()) * progress;
                offset[0] = (geo.x() - icon.width() + geo.width() + quad[0].x() - icon.x()) * progress * ((quadFactor * quadFactor * quadFactor) / width_cube);
                quadFactor = geo.width() - quad[1].x() + (quad[1].x()) * progress;
                offset[1] = (geo.x() - icon.width() + geo.width() + quad[1].x() - icon.x()) * progress * ((quadFactor * quadFactor * quadFactor) / width_cube);
                p_progress[0] = std::min(offset[0] / (geo.x() - icon.width() + geo.width() - icon.x() - float(geo.width() - quad[0].x())), 1.0f);
                p_progress[1] = std::min(offset[1] / (geo.x() - icon.width() + geo.width() - icon.x() - float(geo.width() - quad[1].x())), 1.0f);
            } else {
                lastQuad = quad;
            }

            offset[0] = -offset[0];
            offset[1] = -offset[1];

            p_progress[0] = std::abs(p_progress[0]);
            p_progress[1] = std::abs(p_progress[1]);

            // y values are moved towards the center of the icon
            quad[0].setY((icon.y() + icon.height() * (quad[0].y() / geo.height()) - (quad[0].y() + geo.y())) * p_progress[0] + quad[0].y());
            quad[1].setY((icon.y() + icon.height() * (quad[1].y() / geo.height()) - (quad[1].y() + geo.y())) * p_progress[1] + quad[1].y());
            quad[2].setY((icon.y() + icon.height() * (quad[2].y() / geo.height()) - (quad[2].y() + geo.y())) * p_progress[1] + quad[2].y());
            quad[3].setY((icon.y() + icon.height() * (quad[3].y() / geo.height()) - (quad[3].y() + geo.y())) * p_progress[0] + quad[3].y());

            quad[0].setX(std::max(minX, float(quad[0].x()) + offset[0]));
            quad[1].setX(std::max(minX, float(quad[1].x()) + offset[1]));
            quad[2].setX(std::max(minX, float(quad[2].x()) + offset[1]));
            quad[3].setX(std::max(minX, float(quad[3].x()) + offset[0]));
        }
    } else if (position == Right) {
        const float width_cube = float(geo.width()) * float(geo.width()) * float(geo.width());
        const float maxX = icon.x() - geo.x();

        for (WindowQuad &quad : quads) {
            if (quad[0].x() != lastQuad[0].x() || quad[1].x() != lastQuad[1].x()) {
                quadFactor = quad[0].x() + (geo.width() - quad[0].x()) * progress;
                offset[0] = (icon.x() + quad[0].x() - geo.x()) * progress * ((quadFactor * quadFactor * quadFactor) / width_cube);
                quadFactor = quad[1].x() + (geo.width() - quad[1].x()) * progress;
                offset[1] = (icon.x() + quad[1].x() - geo.x()) * progress * ((quadFactor * quadFactor * quadFactor) / width_cube);
                p_progress[0] = std::min(offset[0] / (icon.x() - geo.x() - float(quad[0].x())), 1.0f);
                p_progress[1] = std::min(offset[1] / (icon.x() - geo.x() - float(quad[1].x())), 1.0f);
            } else {
                lastQuad = quad;
            }

            p_progress[0] = std::abs(p_progress[0]);
            p_progress[1] = std::abs(p_progress[1]);

            // y values are moved towards the center of the icon
            quad[0].setY((icon.y() + icon.height() * (quad[0].y() / geo.height()) - (quad[0].y() + geo.y())) * p_progress[0] + quad[0].y());
            quad[1].setY((icon.y() + icon.height() * (quad[1].y() / geo.height()) - (quad[1].y() + geo.y())) * p_progress[1] + quad[1].y());
            quad[2].setY((icon.y() + icon.height() * (quad[2].y() / geo.height()) - (quad[2].y() + geo.y())) * p_progress[1] + quad[2].y());
            quad[3].setY((icon.y() + icon.height() * (quad[3].y() / geo.height()) - (quad[3].y() + geo.y())) * p_progress[0] + quad[3].y());

            quad[0].setX(std::min(maxX, float(quad[0].x()) + offset[0]));
            quad[1].setX(std::min(maxX, float(quad[1].x()) + offset[1]));
            quad[2].setX(std::min(maxX, float(quad[2].x()) + offset[1]));
            quad[3].setX(std::min(maxX, float(quad[3].x()) + offset[0]));
        }
    }
}

void GenieEffect::postPaintScreen()
{
    QList<EffectWindow *> finished;
    for (auto it = m_animations.cbegin(); it != m_animations.cend(); ++it) {
        const GenieAnimation &animation = it.value();
        if (animation.started ? animation.timeLine.done() : animation.waiting.elapsed() > s_iconWaitMs) {
            finished.append(it.key());
        }
    }
    for (EffectWindow *w : std::as_const(finished)) {
        finish(w);
    }

    effects->addRepaintFull();

    // Call the next effect.
    effects->postPaintScreen();
}

bool GenieEffect::isFirstWindowOfApp(EffectWindow *w) const
{
    const QString windowClass = w->windowClass();
    const auto windows = effects->stackingOrder();
    for (EffectWindow *other : windows) {
        if (other != w && !other->isDeleted() && other->isNormalWindow() && other->windowClass() == windowClass) {
            return false;
        }
    }
    return true;
}

void GenieEffect::slotWindowAdded(EffectWindow *w)
{
    if (effects->activeFullScreenEffect() || !w->isNormalWindow() || !w->isVisible() || w->isMinimized()) {
        return;
    }
    if (!isFirstWindowOfApp(w)) {
        return;
    }

    // Plasma's open animations leave a window that another effect grabs.
    w->setData(WindowAddedGrabRole, QVariant::fromValue(static_cast<void *>(this)));

    GenieAnimation &animation = m_animations[w];
    animation.waiting.start();
    animation.timeLine.setDirection(TimeLine::Backward);
    animation.timeLine.setDuration(m_duration);
    animation.timeLine.setEasingCurve(QEasingCurve::Linear);

    redirect(w);
    effects->addRepaintFull();
}

void GenieEffect::slotWindowDeleted(EffectWindow *w)
{
    m_animations.remove(w);
}

void GenieEffect::finish(EffectWindow *w)
{
    m_animations.remove(w);
    unredirect(w);
    w->setData(WindowAddedGrabRole, QVariant());
}

bool GenieEffect::isActive() const
{
    return !m_animations.isEmpty();
}

} // namespace KWin

#include "moc_genie.cpp"
