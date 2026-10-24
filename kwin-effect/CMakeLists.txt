# SPDX-License-Identifier: GPL-3.0-or-later
# Dock Glass Genie, a KWin effect: the first window of an app pours out of
# its dock icon. It links against the installed KWin, so it has to be rebuilt
# for every KWin version.
#
#   cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
#   cmake --build build
#   sudo cmake --install build
cmake_minimum_required(VERSION 3.16)
project(dockglass-genie)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Makes KDEInstallDirs pick Qt 6's plugin directory.
set(QT_MAJOR_VERSION 6)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

# KWin's CMake config needs Qt6::Widgets to be known.
find_package(Qt6 6.6 CONFIG REQUIRED COMPONENTS Core Gui Widgets)
find_package(KWin REQUIRED COMPONENTS kwineffects)

if(KWin_VERSION VERSION_LESS 6.8)
    message(FATAL_ERROR "Dock Glass Genie is written for KWin 6.8, found ${KWin_VERSION}.")
endif()

add_library(dockglassgenie MODULE src/genie.cpp src/main.cpp)
target_link_libraries(dockglassgenie PRIVATE KWin::kwin)
install(TARGETS dockglassgenie DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins)
