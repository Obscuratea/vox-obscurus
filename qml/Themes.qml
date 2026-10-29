import QtQuick

// The looks Vox can wear. "system" follows the Plasma colour scheme; the rest bring their own colours.
// style is "soft" (rounded, tonal), "diamond" (violet outlines, cut corners) or "sharp" (square, outlined).
QtObject {
    readonly property var list: [
        { id: "system", name: "Follow system", note: "Plasma colours", style: "auto" },
        { id: "matos-dark", name: "MatOS", note: "Soft · dark", style: "soft",
          window: "#201f25", text: "#e3e1ea", highlight: "#52348e", highlightedText: "#e5defe", accent: "#ccbdff" },
        { id: "matos-light", name: "MatOS Light", note: "Soft · light", style: "soft",
          window: "#eeedf6", text: "#1c1b21", highlight: "#e5defe", highlightedText: "#280056", accent: "#694da9" },
        { id: "diamond", name: "Diamond", note: "CachyOS · dark", style: "diamond",
          window: "#1f122a", text: "#efe9f5", highlight: "#4b3a85", highlightedText: "#efe9f5", accent: "#77acff" },
        { id: "obscura-dark", name: "Obscura", note: "Sharp · dark", style: "sharp",
          window: "#121316", text: "#f2f1ee", highlight: "#00aa88", highlightedText: "#101014", accent: "#00aa88" },
        { id: "obscura-light", name: "Obscura Light", note: "Sharp · light", style: "sharp",
          window: "#f2f1ee", text: "#101014", highlight: "#00aa88", highlightedText: "#101014", accent: "#00aa88" }
    ]

    function find(id) {
        for (const t of list)
            if (t.id === id)
                return t;
        return null;
    }
}
