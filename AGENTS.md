# AGENTS.md

- please reference `./swiftui-pro` for the best practices

## UI
- **Self-critique before delivering.** After implementing any UI, ask: Does visual weight match content importance? Are buttons grouped by hierarchy (primary → secondary → destructive)? Do columns feel balanced — if one side is dense and the other sparse, reconsider the split. Is empty space intentional or wasted? Does every section have a clear visual purpose? If any of these fail, revise first.
- **No naive layouts.** Avoid dumping controls in rows or columns without hierarchy. Group buttons by function. Give forms and inputs proportional sizing. Every section should feel designed, not assembled.
- **Text in constrained spaces** must use `minimumScaleFactor` and `lineLimit` to prevent clipping or overflow.
- **Never treat "it renders" as done.** UI is a first draft until it looks intentional.

## UX
- UX should be intentional. When details aren't provided, seek clarification before proceeding with a feature.

## REQUIREMENTS
- Make sure to always build the project and verify changes work
