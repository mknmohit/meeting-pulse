.PHONY: lint mac-local-build mac-local-release

MPUI_SOURCES := mac-app/Packages/MPUI/Sources/MPUI

mac-local-build:
	./mac-app/Tools/build-local.sh

mac-local-release:
	MP_LOCAL_CONFIGURATION=Release MP_LOCAL_BUILD_DIR=build/local-release ./mac-app/Tools/build-local.sh

lint:
	@! rg -n '"[^"]*(seamless|effortless|powerful|robust|leverage|utilize|delve|elevate|unlock|Oops|Uh oh|Something went wrong|An error occurred|Please note that|In order to|At this point in time|Online|Offline|Active|Idle|Status: Green|Enabled|Disabled|N/A|Unknown|Error|Failed|Success)[^"]*"' $(MPUI_SOURCES) --glob '*.swift'
	@! rg -n '—|–|‘|’|“|”' $(MPUI_SOURCES) --glob '*.swift'
	@! rg -n 'displayName == nil|displayName != nil' $(MPUI_SOURCES) --glob '*.swift'
	@rg -n 'displayName\.isEmpty' $(MPUI_SOURCES) --glob '*.swift'
	@rg -n 'STALE_AFTER_SECONDS\s*=\s*180' viewer/src/lib/freshness.ts
	@rg -n 'static let staleAfterSeconds = 180' mac-app/Packages/MPCore/Sources/MPCore/Staleness.swift
	@rg -n 'extension ManualOverride\.Duration: Identifiable, Hashable' mac-app/Packages/MPCore/Sources/MPCore/ManualOverride.swift
