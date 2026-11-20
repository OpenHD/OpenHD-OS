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

    // Each row gives the height and the opaque and transparent half-widths
    // as fractions of the original. Follow the wings, body and wordmark so
    // the photograph's dark margins never form straight borders.
    readonly property var silhouette: [
        [0.00, 0.035, 0.14],
        [0.13, 0.055, 0.20],
        [0.16, 0.30, 0.45],
        [0.18, 0.485, 0.50],
        [0.22, 0.47, 0.50],
        [0.29, 0.42, 0.485],
        [0.39, 0.31, 0.44],
        [0.48, 0.18, 0.33],
        [0.61, 0.082, 0.25],
        [0.72, 0.15, 0.27],
        [0.82, 0.18, 0.29],
        [0.89, 0.17, 0.26],
        [1.00, 0.12, 0.24]
    ]

    function smoothStep(t) {
        const v = Math.max(0, Math.min(1, t))
        return v * v * (3 - 2 * v)
    }

    function maskArtwork(ctx, x, y, w, h) {
        let section = 0
        ctx.globalCompositeOperation = "destination-in"
        for (let row = 0; row < h; ++row) {
            const heightFraction = Math.min(1, (row + 0.5) / h)
            while (heightFraction > silhouette[section + 1][0])
                ++section
            const start = silhouette[section]
            const end = silhouette[section + 1]
            const progress = (heightFraction - start[0]) / (end[0] - start[0])
            const inner = start[1] + (end[1] - start[1]) * progress
            const outer = start[2] + (end[2] - start[2]) * progress
            const alpha = smoothStep((heightFraction - 0.05) / 0.10)
                * (1 - smoothStep((heightFraction - 0.855) / 0.125))
            const fade = outer - inner
            const mask = ctx.createLinearGradient(x, y, x + w, y)
            for (let stop = 0; stop <= 4; ++stop) {
                const fraction = stop / 4
                const offset = outer - fade * fraction
                const color = Qt.rgba(1, 1, 1, alpha * smoothStep(fraction))
                mask.addColorStop(0.5 - offset, color)
                mask.addColorStop(0.5 + offset, color)
            }
            ctx.fillStyle = mask
            ctx.fillRect(x, y + row, w, 1)
        }
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

            maskArtwork(ctx, x, y, w, h)
        }

        ctx.globalCompositeOperation = "destination-over"
        ctx.fillStyle = baseColor
        ctx.fillRect(0, 0, width, height)

        // Draw the glow across the whole canvas so it continues through the
        // feathered outline. Screen blending has little effect on highlights.
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
