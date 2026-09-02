# ADR 0013: Explicit background navigation session

- Status: Accepted
- Date: 2026-09-02

## Decision

Only a user-started navigation session owns background location and Bluetooth execution. Starting navigation creates a `CLBackgroundActivitySession`, enables `CLLocationManager` background updates, and keeps the existing Xiaomi session alive under the `location` and `bluetooth-central` background modes. Stopping navigation disables those updates and invalidates the activity session. Foreground GPS prewarming does not start background activity.

All application-envelope, render, navigation-update, Xiaomi SPP, authentication, and ThirdPartyApp wire contracts remain unchanged. Mi Fitness must not own the same Band connection concurrently.

## Consequences

An active route can continue receiving GPS and updating the Band after the iPhone is locked while iOS permits background execution. This decision does not add automatic reconnect, state restoration, force-quit recovery, or a guarantee that iOS will never terminate the process. Locked-screen update latency, continuous BLE delivery, turns, U-turns, and cleanup after stopping navigation require acceptance on a real iPhone and Xiaomi Smart Band 10.
