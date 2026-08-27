# CipherBook design system

## Visual thesis

CipherBook looks like a public transit dispatch ledger crossed with a tamper-evident evidence envelope. It refuses the generic crypto dashboard: the mechanism occupies the first viewport and every control belongs to the seal/reveal workflow.

## Palette

- Dispatch cobalt `#2536F5` owns major fields.
- Carbon `#101114` anchors type and controls.
- Ticket white `#F4F3EE` is the reading surface.
- Signal yellow `#F4D13D` marks pending actions.
- Verified green `#35C86F` marks completed actions.
- Fault red `#F05252` is reserved for failed or invalid states.

## Typography

Use Bahnschrift Condensed for display and Segoe UI for body copy, with narrow system fallbacks. Monospace is restricted to hashes, block heights, and compact state labels.

## Composition and components

The main artifact is a large sealed-position docket divided by strong black rules. Corners are mostly square; small controls may use an 8px radius. Buttons use hard offset shadows and visibly depress on activation. Phase states read left-to-right like a departure board.

## Motion and responsive behavior

The authored moment is the seal closing: the commitment output clips into view and the docket changes from yellow pending to green sealed. Reduced-motion users receive the final state immediately. On narrow screens, phase columns stack while the primary action remains above secondary explanation.
