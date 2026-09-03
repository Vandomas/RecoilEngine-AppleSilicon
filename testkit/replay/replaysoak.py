#!/usr/bin/env python3
"""Offline device-loss soak: replay a recorded 8v8 with a frame-keyed camera walk.

Same verdict vocabulary as testkit/specjoin.py, but no lobby, no live battle and
no 75s flood-protection wait between runs. The three things that specjoin does
and scripts/replay-check.sh does NOT do -- copy the user's springsettings.cfg,
copy the user's LuaUI, and move the camera -- are all done here, because they
are the ingredients the live harness says are load-bearing.
"""
import argparse, os, re, shutil, subprocess, sys, time, glob

DD = os.path.expanduser("~/Library/Application Support/Beyond-All-Reason-mac")
APP = os.environ.get("SPEC_APP", "/Applications/BAR-uptest.app")
IPSDIR = "/Library/Logs/DiagnosticReports"
BAD = re.compile(r"mvk-error|DEVICE LOST|Invalid Resource|Lost VkDevice|OUT_OF_DEVICE", re.I)
HERE = os.path.dirname(os.path.abspath(__file__))


def make_wd(tag, args):
    wd = f"/tmp/replaysoak-{tag}"
    shutil.rmtree(wd, ignore_errors=True)
    os.makedirs(wd)
    for d in ("pool", "packages", "maps", "games", "rapid"):
        os.symlink(f"{DD}/{d}", f"{wd}/{d}")
    if os.path.isdir(f"{DD}/cache"):
        subprocess.run(["cp", "-R", f"{DD}/cache", f"{wd}/cache"])
    # the user's real graphics settings: VSync=0, MSAA 4x, Shadows=1, Water=4.
    # engine defaults are VSync=-1 (adaptive, ON), MSAALevel=0, Shadows=2 --
    # a materially lighter and vblank-capped workload.
    shutil.copy(f"{DD}/springsettings.cfg", wd)
    with open(f"{wd}/springsettings.cfg", "a") as fh:
        # HostPortDefault, NOT HostPort: ClientSetup.cpp only defines
        # HostPortDefault, so replay-check.sh's "HostPort =" line is a no-op and
        # every replay binds 8452. Per-run ports let runs go back to back.
        fh.write(f"\nHostPortDefault = {args.port}\n")
        if args.demofromdemo:
            # live clients buffer the whole netstream in RAM (DemoRecorder.cpp:32);
            # demo playback does not unless this is on (PreGame.cpp:63,119)
            fh.write("DemoFromDemo = 1\n")
        for line in args.cfg.split(";"):
            if line.strip():
                fh.write(line.strip() + "\n")
    if args.userlua and os.path.isdir(f"{DD}/LuaUI"):
        subprocess.run(["cp", "-R", f"{DD}/LuaUI", f"{wd}/LuaUI"])
    os.makedirs(f"{wd}/LuaUI/Widgets", exist_ok=True)
    shutil.copy(f"{HERE}/replayctl.lua", f"{wd}/LuaUI/Widgets/replayctl.lua")
    if args.jitter:
        shutil.copy(f"{HERE}/jitter.lua", f"{wd}/LuaUI/Widgets/jitter.lua")
    if args.hover:
        shutil.copy(f"{HERE}/hoverprobe.lua", f"{wd}/LuaUI/Widgets/hoverprobe.lua")
    if args.hexprobe:
        shutil.copy(f"{HERE}/hexprobe.lua", f"{wd}/LuaUI/Widgets/hexprobe.lua")
    for f in args.override:
        # keep Shaders/ files under LuaUI/Shaders, everything else is a widget
        sub = "Shaders" if os.path.basename(os.path.dirname(f)) == "Shaders" else "Widgets"
        os.makedirs(f"{wd}/LuaUI/{sub}", exist_ok=True)
        shutil.copy(f, f"{wd}/LuaUI/{sub}/{os.path.basename(f)}")
    if args.shotat:
        shutil.copy(f"{HERE}/shotat.lua", f"{wd}/LuaUI/Widgets/shotat.lua")
    if args.savepause:
        shutil.copy(f"{HERE}/savepause.lua", f"{wd}/LuaUI/Widgets/savepause.lua")
    if args.blink:
        shutil.copy(f"{HERE}/blinkprobe.lua", f"{wd}/LuaUI/Widgets/blinkprobe.lua")
    if args.wraptest:
        shutil.copy(f"{HERE}/wraptest.lua", f"{wd}/LuaUI/Widgets/wraptest.lua")
        os.makedirs(f"{wd}/LuaUI/Include", exist_ok=True)
        shutil.copy(args.wraptest, f"{wd}/LuaUI/Include/chat_emoji.lua")
    if args.fantest:
        shutil.copy(f"{HERE}/fantest.lua", f"{wd}/LuaUI/Widgets/fantest.lua")
        shutil.copy(f"{HERE}/vaofan.lua", f"{wd}/LuaUI/Widgets/vaofan.lua")
    if args.compareat:
        shutil.copy(f"{HERE}/camcompare.lua", f"{wd}/LuaUI/Widgets/camcompare.lua")
    if args.perflog:
        shutil.copy(f"{HERE}/perflog.lua", f"{wd}/LuaUI/Widgets/perflog.lua")
    if args.luaprof:
        shutil.copy(f"{HERE}/luaprof.lua", f"{wd}/LuaUI/Widgets/luaprof.lua")
    for f in args.nowidget:
        p = f"{wd}/LuaUI/Widgets/{f}"
        if os.path.exists(p):
            os.remove(p)
            print(f"  removed widget {f}")
    open(f"{wd}/LuaUI/rsoak.txt", "w").write(
        f"speed={args.speed} preSpeed={args.prespeed} camPeriod={args.camperiod} camSmooth={args.camsmooth} "
        f"endFrame={args.endframe} pauseFrom={args.pausefrom} pauseTo={args.pauseto} "
        f"camera={0 if args.nocamera else 1} skipTo={args.skipto}\n"
        + (f"disable={args.disable}\n" if args.disable else "")
        + ("debug=1\n" if args.debugoverlay else "")
        + (f"shotAt={args.shotat}\n" if args.shotat else "")
        + (f"compareAt={args.compareat}\n" if args.compareat else "")
        + (f"savePeriod={args.savepause}\n" if args.savepause else "")
        + (f"blinkAt={args.blink}\n" if args.blink and "," in args.blink else "")
        + ("hoverLoop=1\n" if args.hoverloop else "")
        + (f"skipMode={args.skipmode}\n" if args.skipmode != "speed" else ""))
    return wd


def ips_set():
    return set(glob.glob(f"{IPSDIR}/gpuEvent-spring-*.ips"))


def run(demo, wd, icd, args):
    env = dict(os.environ,
        EGL_PLATFORM="surfaceless", GALLIUM_DRIVER="zink",
        MESA_LOADER_DRIVER_OVERRIDE="zink", MESA_GL_VERSION_OVERRIDE="4.6",
        VK_ICD_FILENAMES=icd, VK_DRIVER_FILES=icd,
        MVK_CONFIG_LOG_LEVEL=os.environ.get("MVK_CONFIG_LOG_LEVEL", "1"),
        DYLD_FALLBACK_LIBRARY_PATH=f"{APP}/Contents/Frameworks",
        SPRING_DATADIR=f"{APP}/Contents/Resources",
        MVK_CONFIG_USE_COMMAND_POOLING=args.pooling)
    if args.argbuffers is not None:
        env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] = args.argbuffers
    for kv in args.env:
        k, _, v = kv.partition("=")
        env[k] = v
    if args.mvkperf:
        # style 2 prints one summary when the device goes away, the frame-count style
        # only fires from a swapchain present which the readback path never does
        env.update(MVK_CONFIG_PERFORMANCE_TRACKING="1", MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE="2",
                   MVK_CONFIG_LOG_LEVEL="3")
    if args.hud:
        os.makedirs(f"{wd}/hud", exist_ok=True)
        env.update(GALLIUM_HUD="fps,frametime,cpu,ps-invocations,vs-invocations,primitives-generated,ia-vertices",
                   GALLIUM_HUD_DUMP_DIR=f"{wd}/hud", GALLIUM_HUD_VISIBLE="0", GALLIUM_HUD_PERIOD="1")
    # the crash rate drifted a lot across the day on identical settings, so record what
    # the machine looked like going in
    try:
        mp = subprocess.run(["memory_pressure"], capture_output=True, text=True, timeout=20).stdout
        freePct = re.search(r"free percentage:\s*(\d+)", mp)
        sw = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True, timeout=10).stdout
        swUsed = re.search(r"used = ([\d.,]+)M", sw)
        args.machine = (f"freePct={freePct.group(1) if freePct else '?'} "
                        f"swapUsedM={swUsed.group(1).replace(',', '.') if swUsed else '?'}")
    except Exception as e:
        args.machine = f"machine=unknown({e})"
    ips0 = ips_set()
    errlog = open(f"{wd}/stderr.log", "wb")
    proc = subprocess.Popen([f"{APP}/Contents/MacOS/spring", "--write-dir", wd, "-window", demo],
                            env=env, stdout=errlog, stderr=subprocess.STDOUT)
    infolog, t0 = f"{wd}/infolog.txt", time.time()
    deadline = t0 + args.minutes * 60
    started, verdict, bad = False, None, []
    while time.time() < deadline:
        time.sleep(5)
        gone = proc.poll() is not None
        if gone:
            # the process can die inside one 5s tick, so read the logs before
            # calling it a plain exit -- device loss lands in stderr.log and the
            # engine segfaults right after
            txt = ""
            for p2 in (infolog, f"{wd}/stderr.log"):
                if os.path.exists(p2):
                    txt += open(p2, errors="replace").read()
            hits = [l for l in txt.splitlines() if BAD.search(l)]
            if hits:
                bad, verdict = hits, "DEVICE-LOSS"
                break
        if gone:
            # a replay that reaches the recorded game's end is quit by BAR's own
            # <autoquit> widget with status 0 -- that is the natural clean end,
            # anything else that exits is a failure
            verdict = "demo-end" if proc.returncode == 0 else f"engine-exited({proc.returncode})"
            break
        txt = ""
        for p in (infolog, f"{wd}/stderr.log"):
            if os.path.exists(p):
                txt += open(p, errors="replace").read()
        if not started and "RSOAK-BOOT" in txt:
            started = True
            print(f"  simulating at t+{time.time()-t0:.0f}s")
        hits = [l for l in txt.splitlines() if BAD.search(l)]
        if hits:
            bad, verdict = hits, "DEVICE-LOSS"
            time.sleep(10)
            break
        if not started and time.time() - t0 > args.loadwait:
            subprocess.run(["sample", str(proc.pid), "3", "-file", f"{wd}/sample.txt"], capture_output=True)
            verdict = "stuck-loading"
            break
    if verdict is None:
        verdict = "clean" if started else "stuck-loading"
    frames = 0
    if os.path.exists(infolog):
        m = re.findall(r"\[f=(\d+)\]", open(infolog, errors="replace").read())
        if m:
            frames = int(m[-1])
    proc.kill()
    # macOS writes gpuEvent-*.ips well after the fault; a 3s window misses them.
    # Even 25s is not a guarantee -- the smoke run's device loss produced none at all.
    time.sleep(25)
    print(f"MACHINE {args.machine}")
    return verdict, bad, frames, time.time() - t0, sorted(ips_set() - ips0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--demo", required=True)
    ap.add_argument("--dylib", required=True)
    ap.add_argument("--minutes", type=float, default=12)
    ap.add_argument("--speed", type=int, default=1, help="/setspeed; the live spec client runs at 5-8x sim while catching up")
    ap.add_argument("--prespeed", type=int, default=20,
                    help="speed used until the first sim frame, to warp through the demo's "
                         "replayed pregame (106s at 1x on the All That Glitters sample)")
    ap.add_argument("--camperiod", type=int, default=0,
                    help="sim frames between camera jumps; 0 = 120*speed, i.e. the live harness's "
                         "4 wall-seconds per jump. Set it explicitly to hold camera churn per SIM "
                         "frame constant across speeds instead.")
    ap.add_argument("--camsmooth", type=float, default=1.5)
    ap.add_argument("--endframe", type=int, default=0, help="quitforce at this sim frame (0 = run to --minutes)")
    ap.add_argument("--pausefrom", type=int, default=0)
    ap.add_argument("--pauseto", type=int, default=0)
    ap.add_argument("--nocamera", action="store_true")
    ap.add_argument("--nowidget", action="append", default=[])
    ap.add_argument("--userlua", action="store_true", default=True)
    ap.add_argument("--jitter", action="store_true", help="log the spread of frame deltas")
    ap.add_argument("--hoverloop", action="store_true", help="with --hover: sweep for the whole run instead of quitting after one pass")
    ap.add_argument("--hover", action="store_true", help="sweep the cursor and screenshot each stop")
    ap.add_argument("--hexprobe", action="store_true", help="zoom onto each team start and screenshot the selection shapes")
    ap.add_argument("--perflog", action="store_true", help="write the engine profiler top zones to infolog every 5s")
    ap.add_argument("--luaprof", action="store_true", help="per-widget lua callin time to infolog every 5s")
    ap.add_argument("--env", action="append", default=[], help="extra KEY=VAL for the engine environment, repeatable")
    ap.add_argument("--override", action="append", default=[], help="widget file to copy into the run's LuaUI/Widgets, shadowing the game's own")
    ap.add_argument("--savepause", type=int, default=0, help="save then pause every N sim frames (0 = off)")
    ap.add_argument("--blink", default="", help="park the cursor at this x,y screen fraction and shoot a burst")
    ap.add_argument("--wraptest", default="", help="path to a chat_emoji.lua to exercise with the wrap probe")
    ap.add_argument("--skipmode", default="speed", choices=["speed", "skip"], help="how --skipto gets there: warp speed, or the engine's /skip (no draws, like a mid-game join)")
    ap.add_argument("--loadwait", type=int, default=240, help="seconds to allow for loading before calling the run stuck")
    ap.add_argument("--fantest", action="store_true", help="draw a triangle-fan vs triangle-list comparison overlay")
    ap.add_argument("--compareat", type=int, default=0, help="pause at this sim frame and shoot a fixed set of camera poses")
    ap.add_argument("--shotat", default="", help="comma separated sim frames to screenshot from a fixed camera")
    ap.add_argument("--debugoverlay", action="store_true", help="turn the /debug overlay on so the detailed cpu zones tick")
    ap.add_argument("--disable", default="", help="widget names to /luaui disablewidget at game start, ';' separated")
    ap.add_argument("--mvkperf", action="store_true", help="MoltenVK performance summary at exit (needs log level 3)")
    ap.add_argument("--hud", action="store_true", help="dump gallium hud counters per frame into <wd>/hud")
    ap.add_argument("--skipto", type=int, default=0, help="stay at --prespeed until this sim frame, then --speed")
    ap.add_argument("--no-userlua", dest="userlua", action="store_false")
    ap.add_argument("--demofromdemo", action="store_true")
    ap.add_argument("--pooling", default="0")
    ap.add_argument("--argbuffers", default=None, help="MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS")
    ap.add_argument("--cfg", default="", help="extra springsettings lines, ';' separated")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--runs", type=int, default=1)
    args = ap.parse_args()
    if not args.port:
        args.port = 8500 + (os.getpid() % 400)
    if not args.camperiod:
        args.camperiod = 120 * args.speed

    icd_dir = f"/tmp/replaysoak-icd-{args.tag}"
    os.makedirs(icd_dir, exist_ok=True)
    icd = f"{icd_dir}/moltenvk_icd.json"
    open(icd, "w").write('{"ICD":{"api_version":"1.3.0","library_path":"%s",'
                         '"is_portability_driver":true},"file_format_version":"1.0.1"}' % args.dylib)

    # which engine, zink and MoltenVK a run actually used: the review found series
    # where this could not be told apart afterwards
    import hashlib
    def sha12(path):
        try:
            return hashlib.sha256(open(path, "rb").read()).hexdigest()[:12]
        except OSError:
            return "missing"
    gallium = glob.glob(f"{APP}/Contents/Frameworks/libgallium*.dylib")
    stack = (f"app={APP} spring={sha12(f'{APP}/Contents/MacOS/spring')} "
             f"libgallium={sha12(gallium[0]) if gallium else 'missing'} "
             f"mvk={sha12(args.dylib)} dylib={args.dylib}")
    print(f"STACK {stack}")

    rc = 0
    for i in range(args.runs):
        tag = args.tag if args.runs == 1 else f"{args.tag}{i+1}"
        wd = make_wd(tag, args)
        open(f"{wd}/provenance.txt", "w").write(stack + "\n")
        verdict, bad, frames, alive, ips = run(args.demo, wd, icd, args)
        print(f"VERDICT {verdict} tag={tag} demo={os.path.basename(args.demo)} "
              f"speed={args.speed} alive={alive:.0f}s lastframe={frames} newips={len(ips)}")
        for l in bad[:8]:
            print("  BAD:", l)
        for p in ips:
            print("  IPS:", p)
        info = f"{wd}/infolog.txt"
        if os.path.exists(info):
            s = re.findall(r"RSOAK-\w+ f=\d+ fps=(\d+) maxdt=(\d+) speed=([\d.]+)",
                           open(info, errors="replace").read())
            if s:
                fps = sorted(int(a) for a, _, _ in s)
                dts = sorted(int(b) for _, b, _ in s)
                print(f"PERF samples={len(s)} fps_med={fps[len(fps)//2]} fps_min={fps[0]} "
                      f"maxdt_med={dts[len(dts)//2]}ms maxdt_p95={dts[int(len(dts)*0.95)]}ms "
                      f"maxdt_worst={dts[-1]}ms simrate={frames/max(alive,1):.1f}f/s")
        if verdict not in ("clean", "demo-end"):
            rc = 1
    return rc


sys.exit(main())
