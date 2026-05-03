---
created: 2026-05-03T06:19:10Z
title: Replace deprecated CLGeocoder with MKReverseGeocodingRequest
area: ui
files:
  - CellGuard/Views/AnalyticsView.swift:220
  - CellGuard/Views/AnalyticsView.swift:230
---

## Problem

iOS 26 deprecated `CLGeocoder` and its `reverseGeocodeLocation` method in favor of MapKit's new `MKReverseGeocodingRequest` API. Xcode currently emits these as build warnings:

```
'CLGeocoder' was deprecated in iOS 26.0: Use MapKit
'reverseGeocodeLocation' was deprecated in iOS 26.0: Use MKReverseGeocodingRequest
```

Non-blocking today (warnings only, the app builds and runs), but Apple historically converts deprecated symbols to hard errors within 1–2 major iOS releases. Should be migrated before iOS 27 lands to avoid an emergency port.

## Solution

Migrate the two call sites in `AnalyticsView.swift` to `MKReverseGeocodingRequest` (MapKit). Verify equivalent behavior — placemark resolution from `CLLocation` coordinates — and check whether the new API requires any Info.plist additions or capability changes. Suggested target: milestone v1.4 or a small standalone phase. Trivial scope (~30–60 min), no architectural impact.
