---
name: Mediterranean Executive Management
colors:
  surface: '#fbf8fd'
  surface-dim: '#dbd9de'
  surface-bright: '#fbf8fd'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f5f3f7'
  surface-container: '#efedf2'
  surface-container-high: '#e9e7ec'
  surface-container-highest: '#e3e2e6'
  on-surface: '#1b1b1f'
  on-surface-variant: '#44464f'
  inverse-surface: '#303034'
  inverse-on-surface: '#f2f0f4'
  outline: '#757780'
  outline-variant: '#c5c6d0'
  surface-tint: '#4a5d8d'
  primary: '#041e4b'
  on-primary: '#ffffff'
  primary-container: '#1f3461'
  on-primary-container: '#8a9dd1'
  inverse-primary: '#b2c6fc'
  secondary: '#755b00'
  on-secondary: '#ffffff'
  secondary-container: '#fed977'
  on-secondary-container: '#785d00'
  tertiary: '#321a00'
  on-tertiary: '#ffffff'
  tertiary-container: '#502d00'
  on-tertiary-container: '#c8945d'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d9e2ff'
  primary-fixed-dim: '#b2c6fc'
  on-primary-fixed: '#001945'
  on-primary-fixed-variant: '#314674'
  secondary-fixed: '#ffe08f'
  secondary-fixed-dim: '#e6c364'
  on-secondary-fixed: '#241a00'
  on-secondary-fixed-variant: '#584400'
  tertiary-fixed: '#ffdcbd'
  tertiary-fixed-dim: '#f5bb82'
  on-tertiary-fixed: '#2c1600'
  on-tertiary-fixed-variant: '#653e0f'
  background: '#fbf8fd'
  on-background: '#1b1b1f'
  surface-variant: '#e3e2e6'
typography:
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 26px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  status-label:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '700'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  container-padding: 20px
  gutter: 16px
  touch-target-min: 48px
  stack-sm: 4px
  stack-md: 12px
  stack-lg: 24px
---

## Brand & Style
The design system is engineered for property management professionals who require a high-end, reliable tool that balances Mediterranean luxury with operational precision. The brand personality is authoritative, organized, and premium, evoking the feeling of a trusted concierge service rather than a simple utility.

The design style utilizes **Corporate Modernism** with subtle **Glassmorphism** accents. It prioritizes clarity and high-quality finishes, using white space and precise alignment to facilitate rapid inspections under high-glare Mediterranean conditions. The interface feels established and secure, reflecting the high-value assets being managed.

## Colors
The palette is anchored by a deep **Dark Navy**, symbolizing stability and institutional trust. **Gold** is used sparingly as an accent for primary actions and premium highlights, ensuring it doesn't distract from operational data. 

Status indicators use a refined, slightly desaturated palette to maintain the professional aesthetic:
- **Good:** Forest green for successful inspections.
- **Attention Required:** Ochre for maintenance warnings.
- **Urgent:** Deep crimson for critical repairs.

Backgrounds remain a clean, clinical white to maximize contrast and legibility during on-site property walkthroughs.

## Typography
This design system employs **Inter** for its exceptional legibility and systematic feel. The hierarchy is strictly enforced to ensure that property data is easily digestible. 

- **Headlines:** Use tight letter-spacing and bold weights to ground the page.
- **Labels:** Small-cap labels provide a metadata layer that distinguishes property specs (e.g., Sq Meters, Location) from user input.
- **Mobile Adjustments:** Large headlines scale down on mobile to prevent awkward line breaks while maintaining a strong visual anchor at the top of inspection forms.

## Layout & Spacing
The layout follows a **Fluid Grid** model optimized for mobile-first property inspections. A 4-column grid is used for mobile devices with a consistent 20px outer margin to ensure content doesn't feel cramped against the bezel.

Spacing follows an 8px rhythmic scale. For property lists and inspection checklists, vertical rhythm is prioritized (12px or 16px between items) to prevent mis-taps. Elements are grouped into "Logical Containers" with 24px of separation to clearly delineate different sections of a property report (e.g., Exterior vs. Interior).

## Elevation & Depth
Depth is created through **Tonal Layers** and **Ambient Shadows**. 

1.  **Base Layer:** Solid White (#FFFFFF).
2.  **Card Layer:** Subtle, extra-diffused shadows (0px 4px 20px rgba(31, 52, 97, 0.08)) to lift property cards above the background without creating visual clutter.
3.  **Interactive Elements:** Buttons utilize a slight inner-glow when active to simulate a "pressed" physical feel.
4.  **Overlays:** Modal sheets for adding notes or photos use a 20px backdrop blur to maintain the context of the property behind the interface, reinforcing a premium, modern feel.

## Shapes
The shape language is **Rounded**, strike a balance between friendly hospitality and professional architectural structure. 
- **Standard UI (Buttons, Inputs):** 0.5rem (8px) corner radius.
- **Property Cards:** 1rem (16px) corner radius to create a soft, contained look for complex data.
- **Status Pills:** Fully rounded (pill-shaped) to distinguish them from interactive buttons.

## Components
- **Buttons:** Primary buttons are Dark Navy with White text. Secondary buttons use a Gold border with Dark Navy text. Minimum height is 52px for superior touch-accuracy on the move.
- **Property Cards:** White background with a 1px Neutral Gray border and the "Ambient Shadow" defined in Elevation. They include a top-right corner slot for Status Pills.
- **Status Indicators:** Encapsulated pills with a light tint of the status color as background and a high-contrast dark version of that color for text.
- **Progress Bars:** Thin, 4px height bars. The track is light gray; the fill is Gold to represent completion of an inspection or lease process.
- **Input Fields:** Labeled with "Label-caps" typography. Fields have a subtle gray background (#F4F7F9) that transitions to a Dark Navy border on focus.
- **Inspection Checklists:** Large, custom-styled checkboxes (24x24px) with a Dark Navy fill and a Gold checkmark to signify high-value task completion.