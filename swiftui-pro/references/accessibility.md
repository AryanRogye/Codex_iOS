# Accessibility

- Respect the user’s accessibility settings for fonts, colors, animations, and more.
- Do not force specific font sizes. Prefer text styles (`.font(.body)`, `.font(.headline)`, etc.) and platform-appropriate scaling.
- If you *need* a custom font size, use `@ScaledMetric` when targeting older platform releases. When targeting iOS 26 or macOS 26 and later, `.font(.body.scaled(by:))` is also available to get font size adjustment.
- Flag instances where images have unclear or unhelpful VoiceOver readings, e.g. `Image(.newBanner2026)`. If they are decorative, suggest using `Image(decorative:)` or `accessibilityHidden()`, otherwise attach an `accessibilityLabel()`.
- If the user has “Reduce Motion” enabled, replace large, motion-based animations with opacity instead.
- If buttons have complex or frequently changing labels, recommend using `accessibilityInputLabels()` to provide better Voice Control commands. For example, if a button had a live-updating share price for Apple such as “AAPL $271.68”, adding an input label for “Apple” would be a big improvement.
- Icon-only controls must always have an accessible name. Outside space-constrained contexts such as toolbars, prefer visible text with `Button("Label", systemImage: "plus", action: myAction)`. In toolbars or other icon-only contexts, require `accessibilityLabel()`.
- If color is an important differentiator in the user interface, make sure to respect the environment’s `.accessibilityDifferentiateWithoutColor` setting by showing some kind of variation beyond just color – icons, patterns, strokes, etc.
- The same is true of `Menu`: using `Menu("Options", systemImage: "ellipsis.circle") { }` is much better than just using an image.
- Never use `onTapGesture()` unless you specifically need tap location or tap count. All other tappable elements should be a `Button`.
- If `onTapGesture()` must be used, make sure to add `.accessibilityAddTraits(.isButton)` or similar so it can be read by VoiceOver correctly.
- On macOS and other keyboard-driven contexts, interactive elements should be reachable and understandable through keyboard focus, not only pointer hover.
