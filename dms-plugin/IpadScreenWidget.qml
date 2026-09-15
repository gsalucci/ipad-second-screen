import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "ipad-screen"

    readonly property string toolDir: "@TOOLDIR@"

    // NOT named `state`: that is Item's own state-machine property, and assigning
    // an arbitrary string to it makes QML hunt for a State of that name.
    property string screenState: "down"     // down | up | connected
    property bool busy: false

    // DankBar instantiates one widget per screen, and Proc.runCommand debounces
    // by id: a shared id means one instance's poll swallows the other's and only
    // one of the bars ever updates. Key the id to this instance's screen.
    readonly property string procKey: "ipadScreen." + (parentScreen?.name ?? "x")

    readonly property bool active: screenState !== "down"

    readonly property string pillIcon: busy ? "sync"
        : screenState === "connected" ? "cast_connected"
        : screenState === "up" ? "tablet_mac"
        : "tablet_mac"

    readonly property color pillColor: busy ? Theme.surfaceTextMedium
        : screenState === "connected" ? Theme.primary
        : screenState === "up" ? Theme.warning
        : Theme.surfaceTextMedium

    function refresh() {
        Proc.runCommand(procKey + ".status",
                        ["sh", "-c", toolDir + "/second-screen status"],
                        (stdout, exitCode) => {
                            const s = (stdout || "").trim();
                            if (s === "down" || s === "up" || s === "connected")
                                root.screenState = s;
                        }, 50);
    }

    function run(action) {
        if (busy)
            return;
        busy = true;
        // Bringing the output up forces a DRM connector and waits for wayvnc to
        // bind, so give it a generous timeout rather than the default.
        Proc.runCommand(procKey + ".action",
                        ["sh", "-c", toolDir + "/second-screen " + action + " >/dev/null 2>&1"],
                        (stdout, exitCode) => {
                            root.busy = false;
                            root.refresh();
                        }, 0, 120000);
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    pillClickAction: () => root.run("toggle")
    pillRightClickAction: () => root.run("down")

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.pillIcon
                size: root.iconSize
                color: root.pillColor
                anchors.verticalCenter: parent.verticalCenter

                RotationAnimator on rotation {
                    running: root.busy
                    from: 0
                    to: 360
                    duration: 1200
                    loops: Animation.Infinite
                }
            }

            StyledText {
                visible: root.active && !root.busy
                text: "iPad"
                font.pixelSize: Theme.fontSizeSmall
                color: root.pillColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.pillIcon
            size: root.iconSize
            color: root.pillColor
        }
    }
}
