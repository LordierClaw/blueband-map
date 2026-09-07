# Navigation visibility, roundabout exits and latency

Inline on main. The supplied 0.5.18 log is truncated at 1,025 bytes before the visibility event. It confirms a 4,499 ms transfer and 5,454 ms fix-to-display sample, not the cause of the reported stop.

Confirmed defects: all roundabouts share a right-exit glyph; the live Route v4 response supplies exit 2 in Vietnamese instruction text and no numeric angle/exit field. Street and distance use different alignment/width. A renderer timeout latches requiresReconnect and ignores subsequent matching display results, so a suspended Band cannot resume that transfer after waking.

1. Center both HUD labels on the same axis. Show a neutral standard roundabout symbol with the provider's exit number; never assume exit 2 means straight at every roundabout.
2. Preserve the existing image transfer contracts. Investigate lifecycle recovery with deterministic delayed-publication tests. Make reset/recovery explicitly acknowledged and scoped to the failed run before admitting fresh transfers.
3. Keep a newest GPS request, bounded images/chunks/cache, and measure existing transmission choices before changing throughput. Document chunked image versus dynamic tiling/prediction tradeoffs against observed times.
4. Run make test, lint/diff checks, iOS CI and package both changed components. Report source/package evidence separately from device acceptance and the missing full visibility log.
