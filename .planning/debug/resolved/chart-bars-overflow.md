---
status: resolved
trigger: "Chart bars extend beyond graph bounds and bleed into segmented picker above"
created: 2026-04-22
updated: 2026-04-22
---

## Symptoms

- **Expected:** Chart bars stay within the chart's frame, never overlapping elements above
- **Actual:** Tall bars (e.g. 4 drops in one hour bucket) extend upward past the chart area into the time window picker
- **Error messages:** None (visual rendering bug)
- **Timeline:** Likely present since chart implementation
- **Reproduction:** Accumulate enough drops in a single time bucket to produce a tall bar (visible in 24h view around hour 19 in screenshot)

## Current Focus

- hypothesis: yMax computed from individual TimeBucket counts, not stacked totals per time slot. BarMark with foregroundStyle(by:) stacks Silent+Overt bars, so stacked total can exceed yMax, causing bars to render beyond the chartYScale domain. Additionally, no .clipped() modifier prevents visual overflow.
- test: Check if Silent+Overt in same time bucket sum exceeds yMax
- expecting: Stacked total > yMax causes rendering beyond chart bounds
- next_action: RESOLVED

## Evidence

- timestamp: 2026-04-22T11:01 | source: screenshot | finding: Red bar at hour ~19 extends well above chart into segmented picker. Y-axis shows 0-4 scale.
- timestamp: 2026-04-22T11:01 | source: code review | finding: yMax = max(buckets.map(\.count).max() + 1, 3) uses individual bucket max, not sum per time slot. BarMark stacks types by default with foregroundStyle(by:).
- timestamp: 2026-04-22T11:02 | source: code fix | finding: Fixed yMax to sum counts per bucketStart (stacked total), added .clipped() as safety measure. Build succeeded.

## Eliminated

(none -- root cause confirmed on first hypothesis)

## Resolution

- root_cause: yMax was computed from the maximum individual TimeBucket count, but Swift Charts stacks Silent+Overt bars in the same time slot via foregroundStyle(by:). When both types share a bucket, the visual stacked height exceeds yMax, causing bars to render beyond the chartYScale domain and overflow the frame.
- fix: Changed yMax to compute stacked totals per time slot (summing all types sharing the same bucketStart), and added .clipped() modifier after .frame(height: 150) as a safety measure to prevent any future overflow.
- verification: Build succeeded (xcodebuild). Visual verification needed on device.
- files_changed: CellGuard/Views/DropTimelineChart.swift
