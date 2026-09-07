# SauceLabs Setup Guide

> This agent reports XCTest/XCUITest runs to ReportPortal on **all Apple platforms**
> (iOS, macOS, tvOS, watchOS) for both sequential and parallel runs. This guide covers
> one standout case: running **parallel XCUITests on SauceLabs real devices** and merging
> the per-device results into a **single** ReportPortal launch.

For the general agent setup (Info.plist keys, parallel simulators, configuration reference),
see the [main README](../README.md). You only need this guide for the SauceLabs real-device
merge recipe.

---

## Why SauceLabs needs a special recipe

SauceLabs real devices are physically isolated — they don't share a filesystem, environment
variables, or process group. Two consequences drive the whole design:

1. **Env vars don't reach the test process.** Neither `saucectl --env` nor YAML `env:` inject
   variables into the XCUITest process on real devices
   ([saucectl #398](https://github.com/saucelabs/saucectl/issues/398) — "Virtual Devices Only").
   So the agent's `RP_LAUNCH_UUID` sharing (which works for Xcode simulator parallel) **cannot**
   work here.
2. **SauceLabs regenerates the `.xctestrun`.** It builds its own from the uploaded `.ipa + .ipa`,
   so anything you inject into the build's `.xctestrun` is discarded (you'll see
   `XCTestRun Config File = null` in the job metadata).

The **only** configuration that survives to the device is what is **compiled into the test bundle's
`Info.plist` at build time**.

**The approach:** each device creates its own launch tagged with a shared, **run-unique**
`merge_group`; after all shards finish, a post-run merge step combines exactly this run's launches.

> **Launches without `merge_group` (the "3 of 6" symptom) — fixed in the agent.** Older agent
> builds sent a legacy `"tags"` field next to `"attributes"` in the start-launch request.
> Server-side, ReportPortal treats both names as **the same field** (`@JsonAlias`) and keeps
> whichever appears last in the JSON — and Swift serializes dictionary keys in per-process random
> order, so each shard was a coin flip: when `"tags"` landed last, it silently **replaced every
> keyed attribute, including `merge_group`**, and the merge couldn't find that launch. The agent
> no longer sends the legacy field, so every launch keeps its attributes deterministically. As
> defense-in-depth, if `startLaunch` ever gets a 409 (a launch with its UUID already exists), the
> agent back-fills the full attribute set onto that launch. **Use an agent build that includes
> these fixes** — launches created by older builds can still randomly lose their attributes.

---

## Two paths — pick one

| | **Shared launch** (recommended) | **Post-run merge** (legacy) |
|---|---|---|
| How | `ReportPortalLaunchUUID` in the test bundle's `Info.plist`; every shard joins one launch on HTTP 409 | `merge_group` attribute + a ~290-line script that queries and merges launches afterwards |
| Farm retries | Re-run the same bundle ⇒ same launch, automatically | Each retry is another launch to merge |
| CI needs | One `PUT /launch/{uuid}/finish` at the end of the job | `jq`, `curl`, the vendored merge script, discovery/settle polling |
| Use it when | The agent is ≥ 4.1 (has `ReportPortalLaunchUUID`) | Pinned to an older agent |

**Shared launch — the whole recipe:**

```xml
<!-- test target Info.plist, once -->
<key>ReportPortalLaunchUUID</key>
<string>$(RP_LAUNCH_UUID)</string>
```

```yaml
env:
  RP_LAUNCH_UUID: ${{ github.run_id }}-${{ github.run_attempt }}
```

```bash
xcodebuild build-for-testing -scheme YourScheme \
  -destination 'generic/platform=iOS' -derivedDataPath ./DerivedData \
  RP_LAUNCH_UUID="$RP_LAUNCH_UUID"

saucectl run --config .sauce/config.yml       # blocks until all shards finish

curl -sf -X PUT -H "Authorization: Bearer $RP_TOKEN" -H "Content-Type: application/json" \
  -d "{\"endTime\":\"$(date +%s000)\"}" \
  "$RP_ENDPOINT/api/v1/$RP_PROJECT/launch/$RP_LAUNCH_UUID/finish"
```

No `merge_group`, no `PlistBuddy`, no merge script. The value is used as the launch id
verbatim, so any run-unique string works.

> **Why the separate finish call.** With one shared launch the agent deliberately does not
> finalize it (`ReportPortalSkipFinish` defaults to on in this mode). Finishing a launch
> force-finishes its still-running items with the status carried by the finish request, so
> whichever shard finished first would stamp the other shards' in-flight items and set the
> launch's `endTime` while five devices are still reporting. Exactly one actor closes the
> launch, once, at the end.

The rest of this guide documents the **legacy post-run merge**.

---

## Quick Start (legacy post-run merge)

### Prerequisites

- **saucectl** CLI (`npm i -g saucectl`)
- **ReportPortal 5.0+** with an API token that can merge launches (member/PM role)
- A CI with a post-step capability (e.g. GitHub Actions)
- macOS runner for building `.ipa` + test-runner `.ipa`
- `jq` and `curl` on the runner that executes the merge step, and **network access to ReportPortal**

### Step 1 — Inject a run-unique `merge_group` (before build)

Set the test target's `ReportPortalMergeGroup` to a **run-unique** value, injected **before**
`xcodebuild` so it is compiled into the bundle and signed normally:

```bash
MERGE_GROUP="regression-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"   # unique per run + re-run
PLIST="ExampleUITests/Info.plist"     # ← your test target's INFOPLIST_FILE
/usr/libexec/PlistBuddy -c "Delete :ReportPortalMergeGroup" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :ReportPortalMergeGroup string $MERGE_GROUP" "$PLIST"
```

> **Do not patch the built/signed `.xctest`.** Modifying a file inside the signed runner bundle
> invalidates its code signature and it won't install on a real device. Always inject into the
> **source** `Info.plist` before the build (or via an `xcodebuild` build setting — see below).

> **Do not set `ReportPortalSkipFinish`.** Let each device finalize its own launch — see
> [skipFinish](#skipfinish--leave-it-off) below for why.

### Step 2 — Build and run

```bash
xcodebuild build-for-testing \
  -scheme YourScheme \
  -destination 'generic/platform=iOS' \
  -derivedDataPath ./DerivedData

saucectl run --config .sauce/config.yml        # blocks until all shards finish
```

### Step 3 — Merge launches (next step, same job)

`saucectl run` is blocking, so the merge is simply the next step — no special post-action needed:

```bash
export RP_ENDPOINT="https://reportportal.example.com"
export RP_PROJECT="your_project"
export RP_TOKEN="…"                                  # same token as in Info.plist works
export RP_MERGE_GROUP="regression-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"   # SAME value as Step 1
# Wait for all shard launches before merging (avoids "merged 4 of 6"). Pick ONE:
export RP_DISCOVER_STABLE_POLLS="3"   # count-agnostic: merge once no new launch appears for 3 polls (use if the count varies)
# export RP_EXPECTED_LAUNCHES="6"     # OR exact shard count, if it's fixed

./scripts/merge_rp_launches.sh
```

The script:
1. Queries ReportPortal for launches tagged `merge_group=<your run-unique value>` (values are
   URL-encoded, so spaces/`&`/`#` are safe).
2. Waits for those launches to finish; force-finishes and re-checks any still `IN_PROGRESS`.
3. Calls `POST /api/v2/{project}/launch/merge` with `mergeType: DEEP`.
4. Outputs the merged launch URL.

Because the merge group is run-unique, you don't need `ci_run_id` on SauceLabs — leave
`RP_CI_RUN_ID` unset for real-device runs.

### Alternative injection: `xcodebuild` build setting

Instead of `PlistBuddy`, set the value once in the test target's `Info.plist`:

```
ReportPortalMergeGroup = $(RP_MERGE_GROUP)
```

…and pass it at build time (this survives XcodeGen if the placeholder lives in the spec):

```bash
xcodebuild build-for-testing -scheme YourScheme \
  -destination 'generic/platform=iOS' -derivedDataPath ./DerivedData \
  RP_MERGE_GROUP="regression-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
```

If `RP_MERGE_GROUP` is not passed, the placeholder expands to an empty string and the agent emits
no `merge_group` (safe — no garbage value).

---

## GitHub Actions — complete two-job workflow

```yaml
name: SauceLabs Regression

on:
  schedule:
    - cron: '0 6 * * 1-5'   # weekdays at 6 AM
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-latest          # xcodebuild requires macOS
    steps:
      - uses: actions/checkout@v4

      # If you use XcodeGen, generate the project first:
      # - run: xcodegen generate

      # ── Inject a RUN-UNIQUE merge_group BEFORE xcodebuild (compiled in + signed) ──
      - name: Inject run-unique merge_group (pre-build)
        run: |
          MERGE_GROUP="regression-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
          PLIST="ExampleUITests/Info.plist"     # ← your test target's INFOPLIST_FILE
          /usr/libexec/PlistBuddy -c "Delete :ReportPortalMergeGroup" "$PLIST" 2>/dev/null || true
          /usr/libexec/PlistBuddy -c "Add :ReportPortalMergeGroup string $MERGE_GROUP" "$PLIST"
          echo "Injected merge_group = $MERGE_GROUP"

      - name: Build for testing
        run: |
          xcodebuild build-for-testing \
            -scheme YourScheme \
            -destination 'generic/platform=iOS' \
            -derivedDataPath ./DerivedData

      # build-for-testing produces .app bundles (not .ipa), so wrap each one in the
      # Payload/ zip layout SauceLabs expects. (If you already build IPAs via fastlane
      # gym or xcodebuild -exportArchive, skip this and upload those instead.)
      - name: Package artifacts
        run: |
          PRODUCTS=./DerivedData/Build/Products
          APP=$(find "$PRODUCTS" -name "*.app" ! -name "*-Runner.app" -print -quit)
          RUNNER=$(find "$PRODUCTS" -name "*-Runner.app" -print -quit)
          test -n "$APP" && test -n "$RUNNER"   # fail fast if either bundle is missing
          mkdir -p ./build
          package_ipa() {  # $1 = .app path, $2 = output .ipa
            rm -rf Payload && mkdir Payload
            cp -R "$1" Payload/
            zip -qry "$2" Payload
            rm -rf Payload
          }
          package_ipa "$APP"    ./build/Example.ipa
          package_ipa "$RUNNER" ./build/ExampleUITests-Runner.ipa

      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: test-artifacts
          path: build/

  test:
    runs-on: ubuntu-latest         # saucectl + merge script only need curl/jq
    needs: build
    steps:
      - uses: actions/checkout@v4

      - name: Download build artifacts
        uses: actions/download-artifact@v4
        with:
          name: test-artifacts
          path: build/

      - name: Install saucectl
        run: npm i -g saucectl

      - name: Run tests on SauceLabs       # blocks until ALL shards finish
        env:
          SAUCE_USERNAME: ${{ secrets.SAUCE_USERNAME }}
          SAUCE_ACCESS_KEY: ${{ secrets.SAUCE_ACCESS_KEY }}
        run: saucectl run --config .sauce/config.yml

      # if: always() → merge runs even when tests fail (failures are expected).
      # Same merge_group value as the build job (run_id + run_attempt match across jobs).
      - name: Merge ReportPortal launches
        if: always()
        env:
          RP_ENDPOINT: ${{ secrets.RP_ENDPOINT }}
          RP_PROJECT:  ${{ secrets.RP_PROJECT }}
          RP_TOKEN:    ${{ secrets.RP_TOKEN }}
          RP_MERGE_GROUP: regression-${{ github.run_id }}-${{ github.run_attempt }}
          RP_DISCOVER_STABLE_POLLS: "3"   # count-agnostic — merge once no new launch appears for 3 polls
          # RP_EXPECTED_LAUNCHES: "6"     # OR exact shard count, if it's fixed
        run: ./scripts/merge_rp_launches.sh
```

---

## The merge script

Save the following as **`scripts/merge_rp_launches.sh`** in your repo (vendor it — commit a copy
rather than fetching it at runtime), then `chmod +x scripts/merge_rp_launches.sh`. It is portable
across macOS and Ubuntu and needs only `curl` + `jq`:

```bash
#!/usr/bin/env bash
# Copyright 2026 EPAM Systems — Apache License 2.0
# merge_rp_launches.sh — Query ReportPortal for launches matching a merge_group
# attribute, wait for them to finish, and merge them into a single launch.
# Portable: macOS + Ubuntu/Linux. Dependencies: curl, jq.
set -euo pipefail

# --- Configuration (env vars, overridable by positional CLI args) ---
RP_ENDPOINT="${RP_ENDPOINT:-${1:-}}"
RP_PROJECT="${RP_PROJECT:-${2:-}}"
RP_TOKEN="${RP_TOKEN:-${3:-}}"
RP_MERGE_GROUP="${RP_MERGE_GROUP:-${4:-}}"
RP_CI_RUN_ID="${RP_CI_RUN_ID:-${GITHUB_RUN_ID:-}}"
RP_EXPECTED_LAUNCHES="${RP_EXPECTED_LAUNCHES:-}"
RP_MERGED_LAUNCH_NAME="${RP_MERGED_LAUNCH_NAME:-"${RP_MERGE_GROUP:-} (merged)"}"
RP_MERGE_FINALIZE_TIMEOUT="${RP_MERGE_FINALIZE_TIMEOUT:-120}"
RP_DISCOVER_TIMEOUT="${RP_DISCOVER_TIMEOUT:-300}"
RP_DISCOVER_POLL="${RP_DISCOVER_POLL:-5}"
RP_DISCOVER_STABLE_POLLS="${RP_DISCOVER_STABLE_POLLS:-0}"

# --- Token masking (single source of truth, reused by log() and rp_curl_retry) ---
mask() {
  if [[ -n "${RP_TOKEN:-}" ]]; then
    printf '%s' "${1//$RP_TOKEN/***}"
  else
    printf '%s' "$1"
  fi
}

log() {
  local level="$1"; shift
  printf "%-5s %s\n" "$level" "$(mask "$*")" >&2
}

# --- Proxy support ---
curl_opts=(-s -S --fail-with-body)
if [[ -n "${HTTPS_PROXY:-${https_proxy:-}}" ]]; then
  curl_opts+=(--proxy "${HTTPS_PROXY:-${https_proxy:-}}")
fi

# --- curl with retry + exponential backoff (3 attempts, no retry on 4xx) ---
rp_curl_retry() {
  local attempt=0 max=3 delay=2 http_code body tmpfile
  while (( attempt < max )); do
    tmpfile=$(mktemp)
    http_code=$(curl "${curl_opts[@]}" -w '%{http_code}' -o "$tmpfile" \
      -H "Authorization: Bearer ${RP_TOKEN}" \
      -H "Content-Type: application/json" \
      "$@" 2>/dev/null) || true
    body=$(mask "$(cat "$tmpfile")")
    rm -f "$tmpfile"

    if [[ "$http_code" =~ ^2 ]]; then
      printf '%s' "$body"
      return 0
    elif [[ "$http_code" =~ ^4 ]]; then
      log WARN "HTTP $http_code (no retry): ${body:0:200}"
      printf '%s' "$body"
      return 1
    else
      attempt=$((attempt + 1))
      if (( attempt < max )); then
        log INFO "HTTP $http_code, retrying in ${delay}s (attempt $((attempt + 1))/$max)"
        sleep "$delay"
        delay=$((delay * 2))
      else
        log ERROR "HTTP $http_code after $max attempts: ${body:0:200}"
        printf '%s' "$body"
        return 1
      fi
    fi
  done
}

# --- Validation ---
validate() {
  local missing=()
  [[ -z "${RP_ENDPOINT:-}" ]]    && missing+=(RP_ENDPOINT)
  [[ -z "${RP_PROJECT:-}" ]]     && missing+=(RP_PROJECT)
  [[ -z "${RP_TOKEN:-}" ]]       && missing+=(RP_TOKEN)
  [[ -z "${RP_MERGE_GROUP:-}" ]] && missing+=(RP_MERGE_GROUP)

  if (( ${#missing[@]} > 0 )); then
    log ERROR "Missing required parameters: ${missing[*]}"
    exit 3
  fi

  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      log ERROR "Required dependency not found: $cmd"
      exit 3
    fi
  done

  # Numeric tunables must be plain integers — a unit-suffixed value like "60s" would
  # otherwise abort the arithmetic below under set -e/-u. Fall back with a warning.
  if ! [[ "$RP_MERGE_FINALIZE_TIMEOUT" =~ ^[0-9]+$ ]]; then
    log WARN "RP_MERGE_FINALIZE_TIMEOUT='${RP_MERGE_FINALIZE_TIMEOUT}' is not an integer (seconds); using 120"
    RP_MERGE_FINALIZE_TIMEOUT=120
  fi
  if [[ -n "${RP_EXPECTED_LAUNCHES:-}" ]] && ! [[ "$RP_EXPECTED_LAUNCHES" =~ ^[0-9]+$ ]]; then
    log WARN "RP_EXPECTED_LAUNCHES='${RP_EXPECTED_LAUNCHES}' is not an integer; ignoring"
    RP_EXPECTED_LAUNCHES=""
  fi
  if ! [[ "$RP_DISCOVER_TIMEOUT" =~ ^[0-9]+$ ]]; then
    log WARN "RP_DISCOVER_TIMEOUT='${RP_DISCOVER_TIMEOUT}' is not an integer (seconds); using 300"
    RP_DISCOVER_TIMEOUT=300
  fi
  if ! [[ "$RP_DISCOVER_POLL" =~ ^[0-9]+$ ]] || (( RP_DISCOVER_POLL < 1 )); then
    log WARN "RP_DISCOVER_POLL='${RP_DISCOVER_POLL}' is not a positive integer (seconds); using 5"
    RP_DISCOVER_POLL=5
  fi
  if ! [[ "$RP_DISCOVER_STABLE_POLLS" =~ ^[0-9]+$ ]]; then
    log WARN "RP_DISCOVER_STABLE_POLLS='${RP_DISCOVER_STABLE_POLLS}' is not an integer; using 0 (disabled)"
    RP_DISCOVER_STABLE_POLLS=0
  fi
}

# --- API helpers ---
api_v1() { echo "${RP_ENDPOINT%/}/api/v1/${RP_PROJECT}"; }
api_v2() { echo "${RP_ENDPOINT%/}/api/v2/${RP_PROJECT}"; }

# --- Step 1: Find launches by merge_group, then narrow by ci_run_id client-side ---
# Query parameters go through --data-urlencode so values with spaces/&/# are encoded.
# ci_run_id is filtered in jq (not as a second URL attribute filter) to avoid ReportPortal's
# ambiguous "repeated attributeKey/attributeValue" pairing, which can over-match other runs.
find_launches() {
  local quiet="${1:-0}" resp
  resp=$(rp_curl_retry -G "$(api_v1)/launch" \
    --data-urlencode "filter.has.attributeKey=merge_group" \
    --data-urlencode "filter.has.attributeValue=${RP_MERGE_GROUP}" \
    --data-urlencode "page.size=50") || return 1

  if [[ -n "${RP_CI_RUN_ID:-}" ]]; then
    local filtered fcount
    filtered=$(echo "$resp" | jq --arg rid "$RP_CI_RUN_ID" \
      '.content = ((.content // []) | map(select(any(.attributes[]?; .key == "ci_run_id" and .value == $rid))))' \
      2>/dev/null || true)
    fcount=$(echo "$filtered" | jq '.content | length' 2>/dev/null || echo 0)
    if [[ -n "$filtered" ]] && (( fcount > 0 )); then
      printf '%s' "$filtered"
      return 0
    fi
    if [[ "$quiet" != "1" ]]; then
      log WARN "No launches matched ci_run_id=${RP_CI_RUN_ID}; falling back to merge_group-only filter (cannot disambiguate concurrent CI runs — see docs/SAUCELABS_SETUP.md)"
    fi
  fi

  printf '%s' "$resp"
}

# --- Step 1b: Discovery — wait for launches before merging ---
# A single snapshot races with per-device launch finalization and ReportPortal's attribute
# indexing: a shard that finalizes a moment after `saucectl run` returns is invisible at t=0, so a
# naive merge combines only the launches present then (the "merged 4 of 6" symptom). Two opt-in
# waiting modes avoid this (either or both; both bounded by RP_DISCOVER_TIMEOUT, polled every
# RP_DISCOVER_POLL seconds):
#   * RP_EXPECTED_LAUNCHES=N     — wait until N launches carry the merge_group (precise; needs the count).
#   * RP_DISCOVER_STABLE_POLLS=K — wait until the count stops growing for K consecutive polls
#                                  (count-agnostic; best when the shard count is dynamic/unknown).
# With neither set, discovery is a single snapshot (legacy behavior).
discover_launches() {
  if [[ -z "${RP_EXPECTED_LAUNCHES:-}" ]] && (( RP_DISCOVER_STABLE_POLLS == 0 )); then
    find_launches
    return $?
  fi

  local deadline resp count prev=-1 stable=0
  deadline=$(( $(date +%s) + RP_DISCOVER_TIMEOUT ))
  while :; do
    resp=$(find_launches 1) || return 1
    count=$(echo "$resp" | jq '((.content // []) | length)' 2>/dev/null || echo 0)

    # Precise target reached.
    if [[ -n "${RP_EXPECTED_LAUNCHES:-}" ]] && (( count >= RP_EXPECTED_LAUNCHES )); then
      log INFO "Discovered ${count}/${RP_EXPECTED_LAUNCHES} launches"
      printf '%s' "$resp"; return 0
    fi

    # Count has settled: same (non-zero) count for RP_DISCOVER_STABLE_POLLS consecutive polls.
    if (( RP_DISCOVER_STABLE_POLLS > 0 )) && (( count > 0 )) && (( count == prev )); then
      stable=$(( stable + 1 ))
      if (( stable >= RP_DISCOVER_STABLE_POLLS )); then
        log INFO "Launch count stable at ${count} for ${RP_DISCOVER_STABLE_POLLS} polls; merging"
        printf '%s' "$resp"; return 0
      fi
    else
      stable=0
    fi

    if (( $(date +%s) >= deadline )); then
      log WARN "Discovery timed out after ${RP_DISCOVER_TIMEOUT}s at ${count} launch(es); merging what is available (a shard may have failed to report — check SauceLabs)"
      printf '%s' "$resp"; return 0
    fi

    prev=$count
    if [[ -n "${RP_EXPECTED_LAUNCHES:-}" ]]; then
      log INFO "Found ${count}/${RP_EXPECTED_LAUNCHES} launch(es); waiting ${RP_DISCOVER_POLL}s for the rest…"
    else
      log INFO "Found ${count} launch(es); waiting ${RP_DISCOVER_POLL}s for the count to settle…"
    fi
    sleep "$RP_DISCOVER_POLL"
  done
}

# NOTE: earlier revisions had a "Step 1c: orphan patching" fallback here that adopted
# same-named launches missing merge_group. It was removed: the query had no time bound, so
# with launch history containing attribute-less launches (produced by agent builds that
# still had the legacy-"tags" bug) it could stamp the CURRENT run's merge_group onto stale
# launches and merge old results into the run. The agent now fixes attribute loss at the
# source, so a missing shard means the shard genuinely failed — check SauceLabs instead.

wait_for_launches() {
  local ids_json="$1"
  local deadline=$(( $(date +%s) + RP_MERGE_FINALIZE_TIMEOUT ))
  local all_done id resp status

  while (( $(date +%s) < deadline )); do
    all_done=true
    for id in $(echo "$ids_json" | jq -r '.[]'); do
      # A failed status query means we don't KNOW the launch is terminal — keep polling.
      resp=$(rp_curl_retry -X GET "$(api_v1)/launch?filter.eq.id=${id}&page.size=1") || { all_done=false; continue; }
      status=$(echo "$resp" | jq -r '.content[0].status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
      case "$status" in
        PASSED|FAILED|STOPPED|INTERRUPTED) ;;
        *) all_done=false ;;
      esac
    done
    if $all_done; then return 0; fi
    sleep 2
  done

  log WARN "Timeout (${RP_MERGE_FINALIZE_TIMEOUT}s) waiting for launches to finish"
  return 1
}

# --- Step 3: Force-finish an open launch (best-effort, but surface failures) ---
finish_launch() {
  local uuid="$1" ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if ! rp_curl_retry -X PUT "$(api_v2)/launch/${uuid}/finish" -d "{\"endTime\":\"${ts}\"}" >/dev/null; then
    log WARN "Force-finish failed for launch ${uuid}"
  fi
}

# --- Step 4: Merge ---
merge_launches() {
  local ids_json="$1" name="$2" body
  body=$(jq -n --argjson ids "$ids_json" --arg name "$name" '{
    launches: $ids,
    mergeType: "DEEP",
    name: $name,
    extendSuitesDescription: true
  }')
  rp_curl_retry -X POST "$(api_v2)/launch/merge" -d "$body"
}

# --- Main ---
main() {
  validate
  log INFO "Merging launches for merge_group=${RP_MERGE_GROUP}"

  local response
  response=$(discover_launches) || { log ERROR "Failed to query launches"; exit 1; }

  local ids uuids count
  ids=$(echo "$response" | jq -c '[(.content // [])[].id]')
  uuids=$(echo "$response" | jq -r '[(.content // [])[].uuid] | .[]')
  count=$(echo "$ids" | jq 'length')

  if (( count == 0 )); then
    # "Nothing to merge" is not a failure: the merge step usually runs with `if: always()`,
    # so exit 0 to avoid reddening a pipeline that simply produced no launches.
    log WARN "No launches found for merge_group=${RP_MERGE_GROUP} (nothing to merge)"
    exit 0
  fi

  log INFO "Found $count launch(es)"

  if [[ -n "${RP_EXPECTED_LAUNCHES:-}" ]] && (( count != RP_EXPECTED_LAUNCHES )); then
    log WARN "Expected $RP_EXPECTED_LAUNCHES launches, found $count"
  fi

  # Wait for launches to finish; if they don't, force-finish and re-poll so they reach a
  # terminal status before merging (the merge API rejects a mix of statuses).
  if ! wait_for_launches "$ids"; then
    log INFO "Force-finishing open launches"
    for uuid in $uuids; do
      finish_launch "$uuid"
    done
    if ! wait_for_launches "$ids"; then
      log WARN "Launches still not all terminal after force-finish; attempting merge anyway"
    fi
  fi

  log INFO "Merging $count launches: $(echo "$ids" | jq -c '.')"
  local merge_resp merged_id
  if merge_resp=$(merge_launches "$ids" "$RP_MERGED_LAUNCH_NAME"); then
    merged_id=$(echo "$merge_resp" | jq -r '.id // empty' 2>/dev/null || true)
    if [[ -n "$merged_id" ]]; then
      log INFO "Merged launch: ${RP_ENDPOINT%/}/ui/#${RP_PROJECT}/launches/all/${merged_id}"
      exit 0
    fi
  fi

  # Merge failed — print individual launch UUIDs for manual recovery.
  log ERROR "Merge failed. Individual launch UUIDs:"
  for uuid in $uuids; do
    log ERROR "  $uuid"
  done
  exit 2
}

main "$@"
```

---

## Configuration reference

### `merge_group` resolution (3-tier)

Tags launches so the post-run merge can find exactly this run's launches:

| Priority | Source | When used |
|----------|--------|-----------|
| 1 | `RP_MERGE_GROUP` env var | CI/CD where env vars reach the test process (simulators, some farms) |
| 2 | `ReportPortalMergeGroup` in Info.plist | **SauceLabs real devices** (env vars blocked) — inject a run-unique value at build time |
| 3 | none emitted | Standard Xcode parallel / sequential runs |

### skipFinish — leave it off

`ReportPortalSkipFinish` controls whether the agent finalizes its launch or leaves it `IN_PROGRESS`
for the merge script. **The default is off, and that is the recommendation.** If you turn it on,
every device's launch stays `IN_PROGRESS` and the merge script waits the full
`RP_MERGE_FINALIZE_TIMEOUT` (default 120s) for a terminal status that never arrives before
force-finishing — a guaranteed delay on every run. With it off, each device finalizes its own launch
(already `PASSED`/`FAILED`), so the merge is immediate; the script's force-finish stays a safety net.

### `ci_run_id` — leave unset on SauceLabs

`ci_run_id` (`RP_CI_RUN_ID`, falling back to `GITHUB_RUN_ID`) disambiguates concurrent runs **only
when env vars reach the process** — which they don't on SauceLabs real devices. That is exactly why
the **`merge_group` must be run-unique** instead. Leave `RP_CI_RUN_ID` unset for real-device runs.

### Merge script environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RP_ENDPOINT` | Yes | — | ReportPortal base URL |
| `RP_PROJECT` | Yes | — | ReportPortal project name |
| `RP_TOKEN` | Yes | — | ReportPortal API token |
| `RP_MERGE_GROUP` | Yes | — | Run-unique merge group to query (same value injected at build) |
| `RP_DISCOVER_STABLE_POLLS` | No¹ | `0` (off) | **Count-agnostic wait.** When >0, re-query until the launch count stops growing for this many consecutive polls, then merge. Best when the shard count is dynamic/unknown. |
| `RP_EXPECTED_LAUNCHES` | No¹ | — | **Precise wait.** When set, re-query until exactly this many launches appear, then merge. Use when the shard count is fixed. |
| `RP_DISCOVER_TIMEOUT` | No | `300` | Hard cap (seconds) on the wait above; after it, merge whatever was found |
| `RP_DISCOVER_POLL` | No | `5` | Seconds between discovery re-queries |
| `RP_CI_RUN_ID` | No | `$GITHUB_RUN_ID` | Narrows the query when present; leave unset for SauceLabs real-device runs |
| `RP_MERGE_FINALIZE_TIMEOUT` | No | `120` | Seconds to wait for in-progress launches to finalize |
| `RP_MERGED_LAUNCH_NAME` | No | `{RP_MERGE_GROUP} (merged)` | Name for the merged launch |
| `HTTPS_PROXY` | No | — | Honored for the merge runner if ReportPortal is behind a proxy |

> ¹ **Set one of these on SauceLabs.** Without either, discovery is a single snapshot: shards that
> finalize a moment after `saucectl run` returns aren't visible yet, so the merge silently combines
> only the launches present at that instant (the classic "merged 4 of 6"). Prefer
> `RP_DISCOVER_STABLE_POLLS` (e.g. `3`) when the device count can vary; use `RP_EXPECTED_LAUNCHES`
> when it's fixed. Both are bounded by `RP_DISCOVER_TIMEOUT`.

---

## Copy-paste prompt for your coding agent

To wire SauceLabs + merge into **your own project**, paste the prompt below into an AI coding agent
(e.g. Claude Code) **running inside your app's repo**. It is self-contained: fill in the four
`<…>` placeholders first.

````text
You are working inside an iOS app repository that runs XCUITests on SauceLabs real devices.
Goal: report each device's results to ReportPortal and MERGE all of one run's launches into a
single ReportPortal launch. Follow these steps exactly; stop and ask if a fact below is unknown.

Project facts (fill these in before running):
- Test target name: <e.g. MyAppUITests>
- Test target Info.plist path (INFOPLIST_FILE): <e.g. MyAppUITests/Info.plist>
- Scheme used for build-for-testing: <e.g. MyApp>
- Number of SauceLabs shards/devices per run: <fixed number, or "varies">

Hard constraints (do not violate):
1. Inject the merge_group into the test target's SOURCE Info.plist BEFORE xcodebuild, using
   PlistBuddy or an xcodebuild build setting. NEVER patch the built/signed .xctest bundle — that
   breaks code signing and the runner won't install on a real device.
2. The merge_group MUST be run-unique: regression-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}. Use the
   SAME expression in the build job and the merge step so they match automatically.
3. Do NOT set ReportPortalSkipFinish. Let each device finalize its own launch.
4. Leave RP_CI_RUN_ID unset for real-device runs (env vars don't reach the device; merge_group is
   the join key).
5. Put RP_TOKEN, SAUCE_USERNAME, SAUCE_ACCESS_KEY, RP_ENDPOINT, RP_PROJECT in CI secrets — never
   hardcode them.
6. The merge runner (Ubuntu) must have network access to ReportPortal and have curl + jq.

Tasks:
1. Ensure the ReportPortal XCTest agent is a dependency of the test target, and that the test
   target's Info.plist has: NSPrincipalClass (the agent's RPListener), PushTestDataToReportPortal,
   ReportPortalURL (BASE url only — the agent appends /api/v2/{project}), ReportPortalProjectName,
   ReportPortalToken, ReportPortalLaunchName.
2. Vendor the merge script: create scripts/merge_rp_launches.sh containing the script published in
   the agent's docs/SAUCELABS_SETUP.md, and `chmod +x` it. Do not fetch it at runtime.
3. In the GitHub Actions build job (macOS): BEFORE build-for-testing, inject
   ReportPortalMergeGroup=regression-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT} into the test target's
   source Info.plist (PlistBuddy). Then build-for-testing, package the app .ipa + *-Runner.ipa, and
   upload them as artifacts.
4. In the test job (Ubuntu): download artifacts, `npm i -g saucectl`, run `saucectl run` (it blocks
   until all shards finish), then add an `if: always()` step that runs scripts/merge_rp_launches.sh
   with RP_ENDPOINT/RP_PROJECT/RP_TOKEN from secrets, RP_MERGE_GROUP set to the SAME run-unique
   expression, and the discovery wait:
     - if shard count varies: RP_DISCOVER_STABLE_POLLS: "3"
     - if shard count is fixed: RP_EXPECTED_LAUNCHES: "<count>"
5. If the project uses XcodeGen, run `xcodegen generate` before the build, and prefer setting
   ReportPortalMergeGroup=$(RP_MERGE_GROUP) in the spec, passing RP_MERGE_GROUP at build time.

Verify if possible: run the merge script with --help or a dry run, and confirm a built test bundle's
Info.plist actually contains the injected ReportPortalMergeGroup (PlistBuddy -c "Print
:ReportPortalMergeGroup"). Report exactly which files you changed and the final workflow diff.
````

---

## Troubleshooting

### No launches found (merge script reports 0)
The script exits `0` (so an `if: always()` step doesn't redden a pipeline that produced no launches).
Check: (1) `merge_group` reached the agent — open a launch in ReportPortal → Attributes; it must
show your run-unique value; (2) the injected value exactly equals `RP_MERGE_GROUP` passed to the
merge step (using `${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}` in both makes them match); (3) the merge
ran after `saucectl run` returned.

### Fewer launches merged than devices ("merged 4 of 6")
Search ReportPortal for the `merge_group`:
- **All N exist, only some merged** → discovery race: the merge queried once before the last shards
  finalized/indexed. **Fix:** set `RP_DISCOVER_STABLE_POLLS` (count-agnostic) or
  `RP_EXPECTED_LAUNCHES` (fixed), and raise `RP_DISCOVER_TIMEOUT` if the instance is slow.
- **Only some exist** → those shards never reported (device allocation failure, crash, no network to
  RP). Inspect the missing shard's SauceLabs console for `📡 Launch created` / `📎 merge_group`. The
  script merges what it finds and warns; it does not fail the workflow.

### Merge API errors
- **400 "launches must have the same status":** one is still `IN_PROGRESS`; the script polls,
  force-finishes, re-checks — raise `RP_MERGE_FINALIZE_TIMEOUT` if needed.
- **404 on merge endpoint:** ReportPortal older than 5.0 (merge requires 5.0+).
- **403 Forbidden:** `RP_TOKEN` lacks merge permission in the project.

### Code signature / install failures on real devices
Never modify the `.xctest` after build. Inject `merge_group` into the source Info.plist **before**
`xcodebuild` (Step 1) so the build signs it normally.

### Network / proxy
The Ubuntu merge runner must reach ReportPortal. For internal/VPN-only instances use a self-hosted
runner or `HTTPS_PROXY` (the script honors `HTTPS_PROXY`/`https_proxy`). For custom CA certs set
`CURL_CA_BUNDLE`. The script never uses `--insecure`; tokens are auto-masked as `***` in logs.

---

See the [main README](../README.md) for the general agent overview and the full configuration
reference.
