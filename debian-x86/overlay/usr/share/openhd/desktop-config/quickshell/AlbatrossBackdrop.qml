import QtQuick

Canvas {
    id: backdrop

    property url artwork: "file:///usr/share/backgrounds/openhd-3.0.png"
    readonly property color baseColor: "#010409"
    readonly property real artworkAspect: 1365 / 768

    Component.onCompleted: loadImage(artwork)
    onImageLoaded: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function feather(ctx, x, y, w, h, horizontal, start, end) {
        const mask = ctx.createLinearGradient(x, y, horizontal ? x + w : x, horizontal ? y : y + h)
        mask.addColorStop(0, "transparent")
        mask.addColorStop(start, "white")
        mask.addColorStop(1 - end, "white")
        mask.addColorStop(1, "transparent")
        ctx.fillStyle = mask
        ctx.fillRect(x, y, w, h)
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        if (isImageLoaded(artwork)) {
            const w = Math.floor(Math.min(width * 0.65, height * 0.50 * artworkAspect))
            const h = w / artworkAspect
            const x = Math.round((width - w) / 2)
            const y = Math.round(height * 0.02)
            ctx.drawImage(artwork, x, y, w, h)

            // Fade only the margins. The wings run almost to the side edges,
            // while the original image has more space above and below the mark.
            ctx.globalCompositeOperation = "destination-in"
            feather(ctx, x, y, w, h, true, 0.014, 0.014)
            feather(ctx, x, y, w, h, false, 0.14, 0.145)
        }

        ctx.globalCompositeOperation = "destination-over"
        ctx.fillStyle = baseColor
        ctx.fillRect(0, 0, width, height)

        // Draw the glow across the whole canvas so it continues through the
        // feathered margins. Screen blending has little effect on highlights.
        ctx.globalCompositeOperation = "qt-screen"
        const cx = width / 2
        const cy = height * 0.29
        const glow = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(width * 0.44, height * 0.53))
        glow.addColorStop(0, "#052235")
        glow.addColorStop(0.35, "#031525")
        glow.addColorStop(0.72, "#01040b")
        glow.addColorStop(1, "#000000")
        ctx.fillStyle = glow
        ctx.fillRect(0, 0, width, height)
    }
}
