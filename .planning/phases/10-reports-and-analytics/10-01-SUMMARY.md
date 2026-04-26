# Phase 10: Reports & Analytics Summary

## Objective
Correct misleading summary report metrics and introduce a location-based analytics dashboard with heatmaps and rankings.

## Changes
- **CellGuard/Models/ConnectivityEvent.swift**:
  - Added `locationCluster` computed property to generate stable ~1.1km grid cell identifiers (`"LAT, LON"`).
- **CellGuard/Models/SummaryReport.swift**:
  - Refactored `monitoringDays` to count unique calendar days containing data (REPORT-01).
  - Added `dropRatio` calculation (drops / cellular-only events) for more meaningful signal-to-noise reporting (REPORT-02).
  - Migrated location counting to use the new `locationCluster` property.
- **CellGuard/Views/SummaryReportView.swift**:
  - Displayed the new "Drop Ratio (Cellular)" metric.
  - Updated "Monitoring Period" label to "Days Monitored" for clarity.
- **CellGuard/Views/AnalyticsView.swift (New)**:
  - Introduced a new analytics dashboard (ANALYTICS-01).
  - Implemented a Drop Heatmap using Swift Charts (`RectangleMark`) with switchable X-axis dimensions: Hour of Day, Radio Tech, or Interface Type.
  - Implemented a ranked list of location clusters sorted by total drop count (ANALYTICS-02).
- **CellGuard/Views/DashboardView.swift**:
  - Added a "Location Analytics" navigation link to the main dashboard.

## Verification Results
- **Automated**:
  - Build succeeded via `xcodebuild`.
  - Manual code review confirmed `dropRatio` uses cellular events as the denominator.
- **Manual (UAT)**:
  - Verified navigation to the new Analytics view.
  - Verified heatmap switching between dimensions.
  - Verified ranked list sorting.
