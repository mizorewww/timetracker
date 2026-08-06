# Page-Switching Audit & UIKit/Catalyst Assessment — Implementation Memory

Status: complete (measurement + analysis)

Branch: `perf/page-switching-2026-08-06`

## Why this document exists

The user asked for a full re-measurement of page-switch performance, a
detailed pain-point analysis, and an assessment of whether slow parts should
be rebuilt with UIKit (and the Mac platform moved to Catalyst). This document
records the numbers, the breakdown of where the remaining time goes, and the
honest verdict on UIKit/Catalyst.

## Measurement protocol

- iPhone 17 Pro simulator, iOS 27. In-app millisecond trace
  (SWITCH-BEGIN → APPEAR, sandbox file copied out by the harness), three
  rounds per fixture, continuous host sampling of the cold-switch windows.
- Fixtures: dense (1,200 tasks / 1,580 segments / 24 active timers / 400
  inbox / 120 countdowns) and regular demo seed (~30 tasks).

## Final numbers (all optimizations incl. TabView preheat)

Dense fixture (the app's stated target profile):

| Page | Cold first switch | Warm switch |
| --- | --- | --- |
| Tasks | 243–477 (median ~400) | 46–117 |
| Inbox | 108–171 | 23–84 |
| Pomodoro | 108 (preheated; was 245–262) | 14–51 |
| Analytics | 111 (preheated; was 84–163) | 101–214* |
| Today | 103–172 | ~120 |

Regular data: Tasks cold 243, every other page cold 77–155, all warm 14–61
(except Analytics 101–152*).

*Analytics warm varies run to run (101–214 ms): its page re-layouts charts
and lists on each appearance; see pain points.

Baseline for comparison (user's original complaint): Tasks cold 948 ms,
warm 100–190 ms per page.

## Pain-point analysis (where the remaining time goes)

1. **Tasks first switch (~400 ms dense)**: after preheating, the switch
   window is ~21% AttributeGraph LayoutDescriptor construction + ~7% Swift
   protocol-conformance resolution (both one-time-per-process, mostly
   pre-resolved now) and the rest List first layout (row-count dependent;
   243 ms on regular data vs ~400 ms dense) plus TabView scheduling. The
   layout part is UIKit collection-view infrastructure — it would survive a
   UIKit rewrite.
2. **Pomodoro first switch**: was 245–262 ms, now 108 ms after preheating.
   The remaining cost is view-tree construction of the timer face.
3. **Analytics warm (101–214 ms, noisy)**: the page re-layouts its list and
   charts on every appearance, and with active timers its minute-bucket
   refresh can re-trigger a snapshot load. Largest remaining warm-switch
   anomaly; not yet fully attributed.
4. **Everything else**: warm switches 14–120 ms; the residual is system
   layout and tab-switch scheduling, not app code (all app-side projections
   are revision-cached).

## UIKit/Catalyst assessment (verdict: not worth it now)

What a UIKit rebuild would and would not fix:

- **It would not remove the remaining Tasks first-switch cost.** The
  post-preheat window is dominated by list first layout + system scheduling,
  which live in UIKit's own collection view — the same machinery a
  UICollectionView rewrite would use. The SwiftUI-specific costs
  (LayoutDescriptor reflection, protocol conformance) are already amortized
  by preheating; a rewrite would pay their replacement cost (manual cell
  registration/configuration) for no measured gain.
- **Catalyst changes only the Mac rendering path.** The iOS app (the primary
  target) is untouched by Catalyst. On the Mac, the measured pain points are
  the same SwiftUI layout costs that preheating already handles on iOS; the
  native Mac app would become an iOS-app-in-a-window, losing window/menu/
  keyboard conventions and requiring rework of `#if os(macOS)` branches,
  entitlements, and the Watch/Live Activity/Widget surface story — for an
  unquantified rendering-path gain.
- **Where UIKit would help (if a pain point ever demands it):** a single
  `UIViewRepresentable` hosting a `UICollectionView` for the Tasks list, if
  measurements ever show SwiftUI List's *scrolling* (not first-mount) cost
  dominating. First-mount latency is not a scrolling problem and is not
  currently the bottleneck after preheat.

Recommendation: stay on SwiftUI. Continue to amortize one-time Swift runtime
costs with preheating (done), and if Analytics warm noise becomes
user-visible, profile that page specifically before any rewrite decision.

## Gates

`make test` 175/175, `make localization-check` 9/9, `make format-check`
0/725, signed `make build-macos` / `make build-ios` succeed. All measurement
scaffolding removed; zero simulators/processes left behind.
