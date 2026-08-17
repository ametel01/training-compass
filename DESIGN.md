---
name: Training Compass
description: A calm iOS field guide for evidence-backed training decisions.
colors:
  paper: "#f8f7f2"
  surface: "#fffffc"
  navy: "#091c33"
  compass-blue: "#0654c7"
  recovery-green: "#05803b"
  destructive-red: "#c21a29"
  ink-muted: "#474f5c"
  contour-line: "#e0ded4"
typography:
  display:
    fontFamily: "Georgia-Bold, Georgia, serif"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.5pt"
  body:
    fontFamily: "SF Pro, San Francisco, system-ui, sans-serif"
    fontSize: "Dynamic Type body"
    fontWeight: 400
    lineHeight: 1.25
  label:
    fontFamily: "SF Pro, San Francisco, system-ui, sans-serif"
    fontSize: "Dynamic Type caption"
    fontWeight: 600
    lineHeight: 1.2
rounded:
  icon: "42pt"
  card: "22pt"
  capsule: "continuous circle"
spacing:
  micro: "2pt"
  xs: "3pt"
  sm: "8pt"
  md: "12pt"
  lg: "20pt"
  xl: "24pt"
  empty-y: "42pt"
components:
  compass-brand-mark:
    backgroundColor: "{colors.paper}"
    ringColor: "{colors.navy}"
    needleColor: "{colors.compass-blue}"
    rounded: "{rounded.capsule}"
  tab-shell:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.navy}"
    typography: "{typography.label}"
  page-header:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.navy}"
    typography: "{typography.display}"
  empty-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.navy}"
    typography: "{typography.body}"
    rounded: "{rounded.card}"
    padding: "24pt 42pt"
  button-primary:
    backgroundColor: "{colors.compass-blue}"
    textColor: "{colors.surface}"
    typography: "{typography.body}"
---

# Design System: Training Compass

## Overview

**Creative North Star: "The Evidence Field Guide"**

Training Compass is a native iOS field guide for orienting an athlete inside local training, Health context, recovery evidence, and training-max decisions. The built visual world is warm paper, editorial navy headings, SF body copy, compass blue actions, recovery green for positive health states, and quiet topographic contours behind grouped native surfaces.

The system refuses a generic fitness metric wall. It uses large native navigation, five stable tabs, grouped lists, native buttons, alerts, sheets, toggles, and content-unavailable states, then lets the brand live in exact color, serif display moments, compass marks, and evidence-notebook texture.

The current implementation is grounded in `TrainingCompassApp/UI/RootView.swift`, `TrainingCompassApp/UI/CompassDesignSystem.swift`, `PRODUCT.md`, the supplied `design/*.png` references, and the review captures at `.impeccable/review/iphone-today.png`, `.impeccable/review/iphone-today-dark.png`, and `.impeccable/review/ipad-today.png`.

**Key Characteristics:**

- Native iOS structure first: tab shell, navigation stacks, grouped lists, toolbars, alerts, sheets, and Dynamic Type remain the behavioral frame.
- Paper surfaces carry the product's local, durable, field-note character in both light and dark appearances.
- Editorial serif display type appears in orientation moments; SF system typography carries operational content.
- Compass blue is the single interactive tint and primary action color.
- Green and red are semantic state colors, not decoration.
- Topographic contour lines are background evidence texture, restrained enough to stay behind content.

## Colors

The palette is a warm field-notebook base with navy editorial text, one compass-blue action tint, and semantic health and destructive states.

### Primary

- **Compass Blue**: Primary tint for tab selection, toolbar actions, compass glyphs, primary buttons, links, and focused interactive affordances.

### Secondary

- **Recovery Green**: Positive and connected health states, including authorized Health access and recovery/health success feedback.
- **Destructive Red**: Consequential destructive actions, erasure, removal, and warnings that the native role marks as destructive.

### Neutral

- **Warm Paper**: App background, navigation bar background, tab bar background, and the base of the field-guide surface.
- **Paper Surface**: Raised grouped content, empty-state cards, icon wells, and quiet cards inside scroll views.
- **Editorial Navy**: Display headings, branded page headers, and high-emphasis foreground copy.
- **Muted Ink**: Subtitles, descriptions, provenance details, captions, and lower-emphasis explanation text.
- **Contour Line**: Borders, toolbar separators, tab-bar hairlines, and the topographic contour field.

### Named Rules

**The One Tint Rule.** Compass Blue is the only general interaction color; do not introduce extra action colors for variety.

**The Evidence Color Rule.** Green and red must map to real state or consequence. They do not decorate static layouts.

**The Paper Adapts Rule.** Light and dark appearances keep the same roles, but values adapt through semantic `UIColor` providers rather than fixed one-mode hex values.

## Typography

**Display Font:** Georgia-Bold through UIKit navigation appearance, and SwiftUI system serif for page and empty-state display moments.
**Body Font:** SF Pro / San Francisco system text through SwiftUI Dynamic Type styles.
**Label/Mono Font:** SF Pro / San Francisco system captions and labels.

**Character:** The pairing is editorial but operational. Serif type gives orientation and calm authority; SF carries dense training, Health, provenance, and form content without fighting native iOS expectations.

### Hierarchy

- **Display** (bold, Dynamic Type large title/title2, compact line height): Page orientation, empty-state titles, and branded headers such as Today.
- **Headline** (system headline): Section-leading row titles, workout types, lift names, and important list summaries.
- **Title** (system title2 serif where branded): Empty-state headings and compact editorial emphasis.
- **Body** (system body/subheadline): Operational descriptions, settings explanations, recovery prompts, and row content.
- **Label** (caption/caption2, semibold where status-bearing): Source badges, state labels, provenance details, and compact explanatory links.

### Named Rules

**The Serif Orientation Rule.** Use serif type only when the user is orienting to a surface or an empty state; do not use it for dense row data, forms, or controls.

**The Dynamic Type Rule.** New UI must use SwiftUI text styles and native controls so type scales with the user's iOS settings.

## Layout

The app preserves a five-tab iOS shell: Today, Cycle, Progress, TMs, and Health. Each tab owns a `NavigationStack`, native tab item, and accessibility identifier. Deep destinations stay inside the navigation model.

Most operational surfaces use grouped native `List` sections with a minimum row height of 46pt, hidden scroll backgrounds, warm paper behind the list, and visible navigation/tab bar backgrounds. The Today empty state uses a `ScrollView` with 20pt horizontal padding, 18pt top padding, 22pt vertical rhythm between header and card, and 32pt bottom padding.

On iPhone, the first viewport leads with the native inline title, a compass page header, then one grouped work surface. On iPad, the same phone-like content width is presented inside the platform window rather than stretching into a dashboard. This keeps the field-guide density legible and avoids turning the app into a broad metric wall.

## Elevation & Depth

Depth is tonal and structural, not shadow-heavy. The implementation uses warm paper backgrounds, surface cards, 1pt contour-line strokes, native toolbar/tab bar separators, and system grouped list surfaces. The only pronounced depth visible in the review captures comes from native iOS bar/material behavior, especially the floating tab bar treatment on modern iOS.

### Named Rules

**The Tonal Depth Rule.** Separate content with surface color, grouped-list structure, and 1pt strokes before adding shadow.

**The Native Bar Rule.** Navigation and tab depth should come from UIKit/SwiftUI appearances, not custom glass or web-shaped navigation chrome.

## Shapes

The form language is native, rounded, and continuous. Compass icons sit in 42pt circles. Empty-state cards use a 22pt continuous rounded rectangle with a 1pt contour-line stroke. Larger empty-state icon wells use 72pt circles with a 10 percent blue tint fill. The tab bar uses the platform's rounded/capsule behavior.

Grouped lists, toggles, text fields, navigation links, edit buttons, confirmation dialogs, and sheets remain native. Shapes should feel like iOS controls on paper, not a custom web card system.

## Components

### Tab Shell

- **Shape:** Native iOS tab bar with platform rounding and material behavior.
- **Primary:** Five stable destinations: Today, Cycle, Progress, TMs, Health.
- **State:** Selected tab uses Compass Blue; unselected icons and labels use native foreground treatment.
- **Icons:** SF Symbols only: `sun.max`, `calendar`, `chart.line.uptrend.xyaxis`, `scalemass`, and `heart.text.square`.

### Compass Brand Mark

- **Shape:** Fine navy compass ring, eight restrained ticks, and a southwest-to-northeast two-tone blue needle on Warm Paper.
- **App icon:** The full-bleed 1024px raster master lives in `TrainingCompassApp/Resources/Assets.xcassets/AppIcon.appiconset`. iOS supplies the platform corner mask; the source artwork must remain square and opaque.
- **In-app component:** `CompassBrandMark` redraws the same geometry with semantic adaptive colors so it stays crisp and legible in light and dark appearances.
- **Use:** Branded orientation moments only: top-level page headers, app preparation/identity, and the privacy shield badge.
- **Rule:** Functional navigation and status actions keep their existing SF Symbols; the brand mark does not replace symbols whose job is to communicate an action or state.

### Page Header

- **Shape:** 42pt compass icon circle plus leading text stack.
- **Primary:** Warm Paper background, Paper Surface icon well, and the shared Compass Brand Mark.
- **Typography:** Serif large title for the page name; SF subheadline for date or supporting orientation copy.
- **Behavior:** This is an orientation component for top-level paper surfaces, not a replacement for native navigation titles.

### Empty State Card

- **Shape:** 22pt continuous rounded rectangle with 1pt Contour Line stroke.
- **Primary:** Paper Surface background, centered 72pt icon well, serif title, muted SF body message.
- **Use:** Quiet loading/empty moments where the user needs state clarity without urgency.
- **Behavior:** Text stays centered and multiline. The card remains a work surface, not a marketing hero.

### Buttons

- **Shape:** Native SwiftUI buttons and toolbar buttons. Prominent completion actions use `.buttonStyle(.borderedProminent)`.
- **Primary:** Compass Blue through `.tint(...)`; destructive actions use native destructive role.
- **Focus / Disabled:** Inherit platform focus, disabled, and accessibility behavior.
- **Rule:** Do not replace native buttons with custom colored rectangles unless the surrounding screen already has a component-specific reason.

### Grouped Lists

- **Style:** `.listStyle(.grouped)` with hidden default scroll background and Warm Paper behind it.
- **Rows:** Minimum row height is 46pt; row content uses SF headline, subheadline, caption, and caption2 styles.
- **State:** Provenance, failure, cached, limited-history, and attention labels stay textual and source-specific.

### Health Status And Evidence Rows

- **Style:** Dense VStack rows with 3pt internal text spacing and caption/caption2 provenance lines.
- **State:** Orange appears only for warnings/failures that need attention; green appears for connected/success states.
- **Behavior:** Explanation links use SF Symbols `info.circle` and preserve navigation to evidence explanations.

### Privacy Shield

- **Style:** Full-screen native system background with `lock.shield.fill`, title, and secondary message.
- **Use:** Sensitive content concealment only.
- **Rule:** It should stay simple and system-colored so privacy concealment reads as a platform safety state.

## Do's and Don'ts

### Do:

- **Do** keep the five-tab native shell and top-level navigation stacks intact.
- **Do** apply `compassScreen()` to new app surfaces so tint, grouped lists, bars, and paper background stay consistent.
- **Do** use SF Symbols for icons and native iOS controls for toggles, edit buttons, destructive actions, toolbars, sheets, alerts, and navigation links.
- **Do** use `CompassBrandMark` for product identity and orientation; keep action and status iconography semantic.
- **Do** use serif display type for orientation moments and SF system styles for operational content.
- **Do** treat contour lines as background texture only; they should never reduce text contrast or obscure controls.
- **Do** verify light mode, dark mode, and iPad framing when changing shared visual primitives.

### Don't:

- **Don't** invent testimonials, commercial proof, medical claims, or cloud-service claims in UI copy.
- **Don't** turn Health, recovery, or training insights into unexplained scores; keep source and coverage visible.
- **Don't** add a web-like dashboard grid, custom global navigation, hover-only affordances, or decorative cards inside cards.
- **Don't** introduce a second action tint, ornamental green/red usage, or one-off accent colors.
- **Don't** hard-code type sizes where native Dynamic Type styles are available.
- **Don't** let field-guide decoration outrank the local record, explicit choices, and recoverable actions.
