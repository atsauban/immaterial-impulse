import qs.modules.imi.cheatsheet
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io

// The frame join's shape bench as a standalone window:
//
//     qs -p ~/.config/quickshell/imi/bench_frame_join.qml
//
// The page itself is modules/imi/cheatsheet/CheatsheetFrameJoin.qml, which is
// also the cheatsheet's Frame join tab - one implementation, two ways in. This
// file exists for the way the tab cannot be: a window that can be driven from
// a script, so a state can be held still and measured instead of watched.
//
// It lives at the shell's root because that is what makes `qs.` imports
// resolve - Quickshell takes the entry file's directory as the config root, so
// a bench one directory down would be a second copy of everything it is meant
// to be testing.
ShellRoot {
    FloatingWindow {
        id: win
        title: "imi · frame join bench"
        implicitWidth: 1460
        implicitHeight: 820
        // A LITERAL, and the backdrop is painted by a child. A window's clear
        // colour rewrites its requested surface format whenever the alpha
        // crosses 255, and nothing retracts the opaque region that publishes -
        // so a bound one costs the surface its blur for the life of the
        // process (#143, lint_window_clear_color.py).
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: page.ground
        }

        // The page asks for the room its surfaces need at true size; a
        // compositor hands a window whatever it likes. Scrolling is what keeps
        // those two facts from cropping the outline the page exists to show.
        StyledFlickable {
            anchors.fill: parent
            anchors.margins: 14
            // Vertically only. The page already pairs or stacks its panes to
            // the width it is given, so a horizontal scrollbar would just be
            // a way to hide half the comparison off the right edge.
            contentWidth: width
            contentHeight: Math.max(height, page.implicitHeight)
            CheatsheetFrameJoin {
                id: page
                width: parent.width
                height: Math.max(parent.height, implicitHeight)
            }
        }

        //   qs -p <this file> ipc call bench detach
        //   qs -p <this file> ipc call bench set climb 0.8
        // A bench whose only control is a cycling timer can be watched but not
        // measured: every capture lands on a different frame of the motion.
        IpcHandler {
            target: "bench"
            function attach(): void { page.cycling = false; page.attached = true; }
            function detach(): void { page.cycling = false; page.attached = false; }
            function cycle(on: bool): void { page.cycling = on; }
            function set(key: string, value: real): void {
                if (key === "travel") page.travel = value;
                else if (key === "meniscus") page.meniscus = value;
                else if (key === "climb") page.climbFraction = value;
                else if (key === "slant") page.slant = value;
            }
            function state(): string {
                return "attached=" + page.attached + " travel=" + page.travel
                     + " meniscus=" + page.meniscus + " climb=" + page.climbFraction
                     + " slant=" + page.slant;
            }
        }
    }
}
