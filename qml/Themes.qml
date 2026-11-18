import QtQuick

// The looks Vox can wear. "default" is the Vox logo look; "system" follows the Plasma colour scheme; the rest bring their own colours.
// style is "soft" (rounded, tonal), "diamond" (violet outlines, cut corners) or "sharp" (square, outlined).
QtObject {
    readonly property var list: [
        // The Vox look: the logo's night-violet panel, magenta-to-violet fader fills, rounded knobs.
        { id: "default", name: "Default", note: "Vox logo · dark", style: "soft",
          window: "#170e30", text: "#efe9ff", highlight: "#33245c", highlightedText: "#f4ecff",
          accent: "#ff4fd8", accentEnd: "#8b5cff" },
        // Glass: the NeuGlass look. A see-through window (the compositor blurs the desktop behind it), frosted lavender-white (or deep indigo) window, blue-to-violet gradient fills, Inter.
        { id: "w12-light", name: "Glass", note: "Glass · light", style: "soft", font: "Inter",
          // glass: a pastel gradient window with brighter, translucent white cards and a white hairline, like the NeuGlass apps.
          gradient: ["#e6eeff", "#efe4ff"], windowAlpha: 0.62, cardFill: "#ffffff", cardAlpha: 0.70, cardEdge: "#ffffff", edgeAlpha: 0.95, tonalFill: "#5b6cff", tonalAlpha: 0.09, wash: 0.62,
          window: "#eef2fd", text: "#1c2340", highlight: "#dde2ff", highlightedText: "#1c2340",
          accent: "#5b6cff", accentEnd: "#b45cf5" },
        { id: "w12-dark", name: "Glass Dark", note: "Glass · dark", style: "soft", font: "Inter",
          gradient: ["#1c1a40", "#2a1b4a"], windowAlpha: 0.68, cardFill: "#2a2352", cardAlpha: 0.72, cardEdge: "#ffffff", edgeAlpha: 0.16, tonalFill: "#ffffff", tonalAlpha: 0.10, wash: 0.62,
          window: "#1b1836", text: "#f1eeff", highlight: "#3a3478", highlightedText: "#f1eeff",
          accent: "#6f7dff", accentEnd: "#c26dff" },
        { id: "system", name: "Follow system", note: "Plasma colours", style: "auto" },
        { id: "matos-dark", name: "Lavender", note: "Soft · dark", style: "soft",
          window: "#201f25", text: "#e3e1ea", highlight: "#52348e", highlightedText: "#e5defe", accent: "#ccbdff" },
        { id: "matos-light", name: "Lavender Light", note: "Soft · light", style: "soft",
          window: "#eeedf6", text: "#1c1b21", highlight: "#e5defe", highlightedText: "#280056", accent: "#694da9" },
        { id: "diamond", name: "Crystal", note: "Outlined · dark", style: "diamond",
          window: "#1f122a", text: "#efe9f5", highlight: "#4b3a85", highlightedText: "#efe9f5", accent: "#77acff" },
        { id: "obscura-dark", name: "Mint", note: "Sharp · dark", style: "sharp",
          window: "#121316", text: "#f2f1ee", highlight: "#00aa88", highlightedText: "#101014", accent: "#00aa88" },
        { id: "obscura-light", name: "Mint Light", note: "Sharp · light", style: "sharp",
          window: "#f2f1ee", text: "#101014", highlight: "#00aa88", highlightedText: "#101014", accent: "#00aa88" },
        // OLED: true black window so the pixels switch off, boxes are outlines (outline: true); the gradient runs light grey to mid grey, no colour.
        { id: "pureblack", name: "Pure Black", note: "OLED · dark", style: "soft", outline: true,
          window: "#000000", text: "#ececec", highlight: "#2b2b2b", highlightedText: "#f5f5f5",
          accent: "#e4e4e4", accentEnd: "#7d7d7d" }
    ]

    function find(id) {
        for (const t of list)
            if (t.id === id)
                return t;
        return null;
    }
}
