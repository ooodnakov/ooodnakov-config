# Palette's Learning Journal

## 2024-05-11 - Nerd Font Icon Accessibility

**Learning:** Custom widget bars that rely on decorative font glyphs
(like Nerd Fonts or FontAwesome) can create confusing experiences for
screen readers because they read out unpronounceable unicode strings
or meaningless character names.

**Action:** Always add `aria-hidden="true"` to icon elements and use
`aria-label` along with appropriate `role` attributes on their parent
containers to ensure screen readers provide meaningful context
(e.g., "Network status" instead of "󰤨"). Ensure parity across all
similar configurations.
