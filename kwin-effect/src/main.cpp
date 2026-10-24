/*
    SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "genie.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED(GenieEffect,
                              "metadata.json",
                              return GenieEffect::supported();)

} // namespace KWin

#include "main.moc"
