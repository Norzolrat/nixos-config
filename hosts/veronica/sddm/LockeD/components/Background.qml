import QtQuick 2.15

Item {
    // solid color fallback
    Rectangle {
        anchors.fill: parent
        color: (config.type === "color") ? (config.color || "#1d99f3") : "black"
        visible: config.type === "color"
    }

    // image background (resolve path relative to theme root)
    Image {
        anchors.fill: parent
        visible: config.type === "image"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true

        // If Background is absolute ("/", "file:", "qrc:"), use it as-is.
        // Otherwise, resolve relative to the theme root (.. from components/)
        source: {
            if (config.type !== "image") return "";
            var bg = config.Background || "backgrounds/default.png";
            var abs = bg.startsWith("/") || bg.startsWith("file:") || bg.startsWith("qrc:");
            return abs ? bg : Qt.resolvedUrl("../" + bg);
        }
    }
}
