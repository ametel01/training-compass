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
  card: "12pt"
  empty-card: "13pt"
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
    rounded: "{rounded.empty-card}"
    padding: "28pt 24pt"
  button-primary:
    backgroundColor: "{colors.compass-blue}"
    textColor: "{colors.surface}"
    typography: "{typography.body}"
---

# Design System: Training Compass

## Overview

**Creative North Star: "The Evidence Field Guide"**

Training Compass is a native iOS field guide for orienting an athlete inside local training, Health context, recovery evidence, and training-max decisions. The built visual world is warm paper, editorial navy headings, SF body copy, compass blue actions, recovery green for positive health states, and crisp white work cards over a flat off-white field.

The system refuses a generic fitness metric wall. It uses large native navigation, five stable tabs, grouped lists, native buttons, alerts, sheets, toggles, and content-unavailable states, then lets the brand live in exact color, serif display moments, compass marks, and evidence-notebook texture.

The current implementation is grounded in `TrainingCompassApp/UI/RootView.swift`, `TrainingCompassApp/UI/CompassDesignSystem.swift`, `PRODUCT.md`, the supplied `design/*.png` references, and the review captures at `.impeccable/review/iphone-today.png`, `.impeccable/review/iphone-today-dark.png`, and `.impeccable/review/ipad-today.png`.

**Key Characteristics:**

- Native iOS structure first: tab shell, navigation stacks, grouped lists, toolbars, alerts, sheets, and Dynamic Type remain the behavioral frame.
- Paper surfaces carry the product's local, durable, field-note character in both light and dark appearances.
- Editorial serif display type appears in orientation moments; SF system typography carries operational content.
- Compass blue is the single interactive tint and primary action color.
- Green and red are semantic state colors, not decoration.
- The app field stays visually flat so evidence, controls, and state color remain the focus.

### Shipped Reference Contract

The shipped native SwiftUI system is pinned to `/Users/alexmetelli/source/training-compass/design/ChatGPT Image Aug 17, 2026, 05_48_07 AM (1).png` with seed `bdb3937c`. Its durable visual contract is a warm off-white field, crisp white 12pt-radius work cards, navy serif editorial page and lift headings, compact SF data type, blue actions, green verified states, and red omissions.

- The shared five-destination shell is Today, Cycle, Progress, Training Maxes (`TMs` in the compact tab item), and Health. Health is the required product adaptation to the four-phone reference, not an optional visual variation.
- Shared primitives are the editorial page header, `CompassCard`, `CompassStatusPill`, and `CompassMetricValue`, composed inside native `TabView`, `NavigationStack`, list, scroll, toolbar, sheet, alert, and control behaviors.
- Today preserves the reference-shaped `KG` / `REPS` / confirm / omit grid. Confirm uses the blue-to-green verified path; omit is an explicit red disposition.
- Progress is a four-question decision surface: main-lift e1RM direction, seven-day Heart-Rate Zone distribution, cardio efficiency direction, and per-session heart-rate drift. Workout archives, activity mix, training-max internals, comparison controls, and source-ledger detail do not belong on this page.
- `compassScreen()` reserves 112pt of bottom scroll-content clearance for the iOS 26 floating tab bar. Preserve native behavior, existing accessibility identifiers, Dynamic Type, Health evidence and source visibility, and every real loading, empty, connected, limited, failure, and populated data state.

Final simulator verification passed on iPhone 17 with 18 imported workouts and 241 recovery samples. The finish reviewer disposition was **ready to ship**; no personal Health details beyond those aggregate verification counts belong in design evidence.

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
- **Contour Line**: Dividers, toolbar separators, tab-bar hairlines, and other restrained structural rules.

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

The app preserves a five-tab iOS shell: Today, Cycle, Progress, Training Maxes (`TMs` in the compact tab item), and Health. Each tab owns a `NavigationStack`, native tab item, and accessibility identifier. Deep destinations stay inside the navigation model.

Most operational surfaces use grouped native `List` sections with a minimum row height of 42pt, hidden scroll backgrounds, warm paper behind the list, visible navigation/tab bar backgrounds, and 112pt of bottom scroll clearance for the floating tab bar. The Today empty state uses the same page header, paper field, and quiet centered work-card treatment.

On iPhone, the first viewport leads with the native inline title, a compass page header, then one grouped work surface. On iPad, the same phone-like content width is presented inside the platform window rather than stretching into a dashboard. This keeps the field-guide density legible and avoids turning the app into a broad metric wall.

## Elevation & Depth

Depth is tonal and structural, not shadow-heavy. The implementation uses warm paper backgrounds, restrained surface-card shadows, native toolbar/tab bar separators, and system grouped list surfaces. The only pronounced depth visible in the review captures comes from native iOS bar/material behavior, especially the floating tab bar treatment on modern iOS.

### Named Rules

**The Tonal Depth Rule.** Separate content with surface color, grouped-list structure, and 1pt strokes before adding shadow.

**The Native Bar Rule.** Navigation and tab depth should come from UIKit/SwiftUI appearances, not custom glass or web-shaped navigation chrome.

## Shapes

The form language is native, rounded, and continuous. Shared work cards use a 12pt continuous rounded rectangle; empty-state cards use 13pt. Compass icons sit in 42pt circles, and larger empty-state icon wells use 72pt circles with a 10 percent blue tint fill. The tab bar uses the platform's rounded/capsule behavior.

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

- **Shape:** Leading title stack inset through the native top safe area.
- **Primary:** Warm Paper background with the platform navigation bar retained.
- **Typography:** Navy serif title for the page name; compact SF caption for an optional date or supporting orientation line.
- **Behavior:** This is the visible top-level orientation heading; the native navigation bar remains responsible for actions, back navigation, and platform behavior.

### Work Card, Status Pill, And Metric

- **Work card:** `CompassCard` is a crisp Paper Surface with 12pt continuous corners, 12pt internal padding, and restrained tonal lift.
- **Status pill:** `CompassStatusPill` uses compact SF type and a low-opacity semantic fill; blue is active/default, green is verified, and red is reserved for omission or failure.
- **Metric:** `CompassMetricValue` keeps labels and source detail compact while values use semibold monospaced digits for fast comparison.

### Today Set Grid

- **Columns:** Preserve the compact `KG`, `REPS`, confirm, and omit controls beside planned set evidence.
- **State:** Confirmed actuals become green verified evidence; omitted or failed rows use restrained red treatment without hiding the disposition.
- **Behavior:** Keep the existing text-field, button, keyboard, accessibility-label, and accessibility-identifier contracts.

### Progress Decision Surface

- **Purpose:** Answer four questions only: are the four main-lift e1RMs increasing, how measured training time is distributed across HR Zones 1–5, whether distance per heartbeat is improving, and what heart-rate drift occurred in each recent cardio session.
- **e1RM:** Show Squat, Deadlift, Bench Press, and Overhead Press together. Each row carries the latest eligible e1RM and its trailing-90-day direction; insufficient history is an answer, not a reason to expose the underlying archive.
- **e1RM evidence:** Direction compares the first and last eligible observations in the inclusive trailing 90-day window and requires at least two observations. Eligible evidence is the primary plus set outside deload weeks; failed, omitted, assistance, non-plus, and additional sets stay excluded.
- **HR zones:** Use the current seven-day window. Show duration plus percent of measured heart-rate time for Zones 1–5 and disclose overall workout HR coverage. When maximum heart rate is missing, the only secondary action opens the focused Maximum Heart Rate form; other empty zone states explain missing measured HR without showing that action.
- **Cardio efficiency:** Define the metric as distance per heartbeat. Compare the latest eligible distance-based cardio session across available history with the median of up to four preceding sessions of the same activity. Require at least 80 percent heart-rate coverage.
- **Heart-rate drift:** Limit rows to cardio sessions in the current seven-day window. Remove the first 10 elapsed minutes, split the remaining elapsed interval into equal halves, calculate time-weighted average heart rate for each half, then show `(second − first) / first × 100`. Require at least 80 percent HR coverage in each half. Drift is displayed neutrally in Compass Blue; the product does not invent a good/bad threshold.
- **Observed HR intervals:** Zone, efficiency, and drift calculations are time-weighted over source-observed intervals. An instantaneous sample may own time forward to the next sample only when the gap is at most 60 seconds; larger gaps and workout edges remain uncovered.
- **Visual rule:** Use four linear `CompassCard` blocks with fine dividers and compact monospaced measurements. Never restore workout counts, activity mix, run history, event history, training-max values, or verbose calculation explanations to the Progress destination.

### Health Control Surface

- **Purpose:** Keep Health operational, not analytical. The top-level destination exposes only read approval, refresh, and the choice to add completed strength-session summaries to Apple Health.
- **Layout:** Use one `CompassCard` beneath the Health page header. The card contains connection state, one short freshness/workout summary, one primary action, and the write-back toggle only after read approval.
- **Automatic refresh:** After the owner completes the Health read request, persist that completed-request fact locally. On launch, foreground, or Health observer delivery, reconcile once on the first app open of each local calendar day. Every automatic trigger uses the same due check. Manual refresh is the sole bypass and is not rate-limited by the daily policy.
- **Progressive disclosure:** Maximum-heart-rate configuration belongs to its focused Progress route. Deep rebuild remains in Settings. Recovery evidence, stream-by-stream diagnostics, source preference controls, and workout-history rows do not appear on the top-level Health destination.
- **States:** Before approval, show one `Approve Health Access` button. When connected, show `Refresh Health Data` and `Add completed sessions to Health`. Conditional connection/write errors may add a single recovery action; loading changes the refresh label in place.

### Empty State Card

- **Shape:** 13pt continuous rounded rectangle with restrained tonal lift.
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
- **Rows:** Minimum row height is 42pt; row content uses SF headline, subheadline, caption, and caption2 styles.
- **State:** Provenance, failure, cached, limited-history, and attention labels stay textual and source-specific.

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
- **Do** use the structural line token only for quiet dividers and platform hairlines.
- **Do** verify light mode, dark mode, and iPad framing when changing shared visual primitives.

### Don't:

- **Don't** invent testimonials, commercial proof, medical claims, or cloud-service claims in UI copy.
- **Don't** turn Health, recovery, or training insights into unexplained scores; keep source and coverage visible.
- **Don't** add a web-like dashboard grid, custom global navigation, hover-only affordances, or decorative cards inside cards.
- **Don't** introduce a second action tint, ornamental green/red usage, or one-off accent colors.
- **Don't** hard-code type sizes where native Dynamic Type styles are available.
- **Don't** let field-guide decoration outrank the local record, explicit choices, and recoverable actions.
