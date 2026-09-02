#!/bin/bash
# ladder.sh DEMO DYLIB [RUNS] -- shrink the repro one ingredient at a time.
#
# Each rung is a claim about what the fault needs. Run them in order and stop at
# the first rung that stops dying with RUNS runs behind it; the rung above it is
# the smallest test known to trigger. Deaths are ~exponential (dossier section 5),
# so a single clean run means nothing -- RUNS should be >= 6 before believing
# "this rung does not reproduce".
set -u
DEMO="${1:?usage: ladder.sh <demo.sdfz> <libMoltenVK.dylib> [runs]}"
DYLIB="${2:?}"
RUNS="${3:-6}"
HERE="$(cd "$(dirname "$0")" && pwd)"
run() { tag="$1"; shift; echo "=== $tag"; python3 -u "$HERE/replaysoak.py" --tag "$tag" \
        --demo "$DEMO" --dylib "$DYLIB" --argbuffers 1 --runs "$RUNS" "$@" 2>&1 | grep -E "VERDICT|PERF|BAD|IPS"; }

# 0  baseline: the live harness's regime -- catch-up sim rate, camera walking,
#    the user's widgets and the user's graphics settings
run L0 --speed 8 --minutes 8
# 1  is the camera the ingredient? dossier says a static camera survives for hours
run L1 --speed 8 --minutes 8 --nocamera
# 2  is the catch-up sim rate the ingredient, or just wall-clock exposure?
run L2 --speed 1 --minutes 12
# 3  sim frozen after 3000 frames, camera still walking: GPU churn without unit churn
run L3 --speed 8 --minutes 8 --pausefrom 3000
# 4  stock BAR widgets only, no user overrides (dossier #4: dies faster)
run L4 --speed 8 --minutes 8 --no-userlua
# 5  the three GL4 widgets from issue 5, dropped one at a time
run L5a --speed 8 --minutes 8 --nowidget gui_healthbars_gl4.lua
run L5b --speed 8 --minutes 8 --nowidget gfx_unit_stencil_gl4.lua
run L5c --speed 8 --minutes 8 --nowidget gui_unit_firestate_icons.lua
# 6  graphics settings: the load replay-check.sh was accidentally testing
run L6 --speed 8 --minutes 8 --cfg "Shadows=0;MSAALevel=0;Water=0"
run L7 --speed 8 --minutes 8 --cfg "VSync=-1"
