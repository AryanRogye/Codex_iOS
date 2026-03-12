# macOS-specific SwiftUI review

## Desktop-first layout

- Review macOS interfaces as resizable windows, not fixed phone screens. Layouts should still make sense when the window grows or shrinks.
- Prefer desktop patterns such as sidebars, split views, inspectors, toolbars, and panels for information-dense apps rather than forcing iPhone-style tab bars, giant cards, or bottom-anchored actions.
- Do not blindly apply iOS touch spacing to macOS. Desktop UI can be denser, but it still needs clear grouping and click targets.
- When text appears in constrained areas such as sidebars, toolbars, and table-like rows, make sure truncation is intentional. `lineLimit()` and `minimumScaleFactor()` should be considered where clipping would otherwise occur.
- App-wide preferences should generally live in a `Settings` scene or dedicated settings window, not inside the main content flow.

## Input and interaction

- macOS is keyboard- and pointer-first. Review whether primary actions have appropriate keyboard shortcuts and whether app-wide actions belong in commands or menus.
- Hover, right click, drag and drop, and multi-selection are first-class macOS interactions. Suggest them when they fit the task instead of assuming touch gestures.
- Avoid making swipe actions, long-presses, or bottom sheets the primary way to discover important features. If such an interaction exists in shared code, ensure macOS has an equally discoverable desktop alternative.
- Prefer `Button`, `Menu`, `Toggle`, `Picker`, and other standard controls over gesture-only interactions.

## Windows, menus, and files

- Consider whether the app should use `WindowGroup`, `Window`, `Settings`, `MenuBarExtra`, or `DocumentGroup` rather than forcing everything into one window.
- For app-wide actions such as preferences, import/export, and workspace management, review whether they belong in menu commands or toolbar items rather than buried in a detail view.
- File workflows on macOS should use system document APIs where possible and respect sandbox/security-scoped access when relevant.
- Destructive actions should clearly name the affected item and attach confirmation UI to the relevant window or view context.

## Toolbars and discoverability

- Toolbar items should have clear meaning. Icon-only controls need an `accessibilityLabel()`, and `help()` is often appropriate on macOS.
- Group primary, secondary, and destructive actions intentionally. Toolbars should not become a flat dump of unrelated controls.
- Check that symbols and metaphors make sense on macOS rather than assuming iOS-only UI patterns.

## Accessibility on macOS

- Review keyboard navigation, focus behavior, VoiceOver output, Increase Contrast, and Reduce Motion in addition to text scaling.
- Do not rely on hover state, color alone, or pointer precision to communicate essential information.
