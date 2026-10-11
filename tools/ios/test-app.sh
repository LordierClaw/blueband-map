#!/usr/bin/env bash
set -euo pipefail
device=${1:?Simulator identifier required}
result=${2:?Result bundle path required}
scope=${3:-full}
filters=()
if [[ "$scope" == latency ]]; then
  filters+=(
    -only-testing:BlueBandMapTests/VietmapSnapshotRendererTests/testLatencyStyleFetchSurvivesCancelledCameraAndIsSharedWithSuccessor
    -only-testing:BlueBandMapTests/VietmapSnapshotRendererTests/testLatencyProviderFailureIdentifiesStageAndSafeErrorCode
    -only-testing:BlueBandMapTests/AppModelPickerTests/testLatencyQueuedArrivalDoesNotWaitAnotherSecondAfterDelayedACK
    -only-testing:BlueBandMapTests/NavigationReplayTests/testLatencyFullFlowHasMovementZoomDrainAndBoundedAutomaticCompletion
  )
elif [[ "$scope" != full ]]; then
  echo "Unknown iOS test scope" >&2
  exit 2
fi
xcodebuild -project apps/ios/BlueBandMap.xcodeproj -scheme BlueBandMap -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -resultBundlePath "$result" \
  CODE_SIGNING_ALLOWED=NO "${filters[@]}" test
