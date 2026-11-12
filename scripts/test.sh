#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
mkdir -p .build/checks
swiftc -swift-version 5 Sources/Timefold/Models.swift Sources/Timefold/GlobalHotKey.swift Sources/Timefold/WindowSizing.swift Sources/Timefold/TaskSelection.swift Sources/Timefold/TextPlanParser.swift Sources/Timefold/Store.swift Tests/ModelChecks.swift Tests/TextPlanChecks.swift Tests/ColloquialPlanChecks.swift -o .build/checks/ModelChecks
.build/checks/ModelChecks
