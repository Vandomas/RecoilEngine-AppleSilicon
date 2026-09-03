#!/usr/bin/env python3
"""Join a running BAR battle as spectator with a chosen MoltenVK dylib, watch for device loss."""
import socket, hashlib, base64, sys, time, re, os, subprocess, threading, secrets, argparse, glob, shutil

HOST, PORT = "server4.beyondallreason.info", 8200
DD = os.path.expanduser("~/Library/Application Support/Beyond-All-Reason-mac")
APP = os.environ.get("SPEC_APP", "/Applications/BAR Launcher.app")
BAD = re.compile(r"mvk-error|DEVICE LOST|Lost VkDevice", re.I)
# with MVK_CONFIG_RESUME_LOST_DEVICE=1 a fault is logged as a warning and the game goes on; count those, do not stop
RESUMED = re.compile(r"Resumed VkDevice", re.I)
CONNECTED = re.compile(r"GameData|Using map|Connection established|serverMessage|PlayerName", re.I)

def local_map(name):
    return bool(glob.glob(f"{DD}/maps/{glob.escape(name.lower().replace(' ', '_'))}.sd*"))

class Lobby:
    def __init__(self, logpath):
        pw = re.search(r'password = "([^"]+)"', open(f"{DD}/LuaMenu/Config/IGL_data.lua").read()).group(1)
        self.pwhash = base64.b64encode(hashlib.md5(pw.encode()).digest()).decode()
        self.sock = socket.create_connection((HOST, PORT), timeout=20)
        self.buf = b""
        self.alive = True
        self.log = open(logpath, "w", buffering=1)
        self.tail = []          # last lines, for reporting
        print("greeting:", self.readline())

    def send(self, line):
        try: self.sock.sendall((line + "\n").encode())
        except (OSError, ConnectionError): self.alive = False

    def readline(self, timeout=30):
        deadline = time.time() + timeout
        while b"\n" not in self.buf:
            left = deadline - time.time()
            if left <= 0: raise socket.timeout()
            self.sock.settimeout(left)
            chunk = self.sock.recv(65536)
            if not chunk: raise ConnectionError("lobby closed")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        s = line.decode(errors="replace").rstrip("\r")
        self.log.write(f"{time.strftime('%H:%M:%S')} {s}\n")
        self.tail.append(s)
        if len(self.tail) > 40: self.tail.pop(0)
        return s

    def login(self):
        self.send(f"LOGIN Vandomas {self.pwhash} 0 * LuaLobby Chobby\t3236263717\tsp cl p")
        t0 = time.time()
        while time.time() - t0 < 20:
            s = self.readline()
            if s.startswith("ACCEPTED"): return
            if s.startswith("DENIED"): raise RuntimeError(s)
        raise RuntimeError("no ACCEPTED")

    def collect_battles(self, seconds=15):
        if not hasattr(self, "battles"):
            self.battles, self.users, self.count = {}, {}, {}
        battles, users, count = self.battles, self.users, self.count
        t0 = time.time()
        while time.time() - t0 < seconds:
            try: s = self.readline(timeout=max(0.2, seconds - (time.time() - t0)))
            except (socket.timeout, TimeoutError): break
            w = s.split(" "); c = w[0]
            if c == "BATTLEOPENED":
                hw = s.split("\t")[0].split(" "); tabs = s.split("\t")
                battles[hw[1]] = dict(founder=hw[4], ip=hw[5], port=hw[6],
                    passworded=hw[8], map=tabs[2] if len(tabs)>2 else "?",
                    title=tabs[3] if len(tabs)>3 else "?", locked="0")
            elif c == "UPDATEBATTLEINFO" and len(w) > 3 and w[1] in battles:
                battles[w[1]]["locked"] = w[3]
            elif c == "JOINEDBATTLE": count[w[1]] = count.get(w[1], 0) + 1
            elif c == "LEFTBATTLE": count[w[1]] = max(0, count.get(w[1], 0) - 1)
            elif c == "CLIENTSTATUS": users[w[1]] = int(w[2])
        good = []
        for bid, b in battles.items():
            st = users.get(b["founder"], 0)
            if (st & 1) and b["passworded"] == "0" and b["locked"] == "0" and local_map(b["map"]):
                good.append((count.get(bid, 0), bid, b))
        good.sort(reverse=True)
        return good

    def pump(self):
        """Background: keep reading (into log) + ping."""
        def rloop():
            while self.alive:
                try: self.readline(timeout=5)
                except (socket.timeout, TimeoutError): pass
                except (OSError, ConnectionError): break
        def ploop():
            while self.alive:
                time.sleep(25)
                try: self.send("PING")
                except (OSError, ConnectionError): break
        threading.Thread(target=rloop, daemon=True).start()
        threading.Thread(target=ploop, daemon=True).start()

def make_wd(tag):
    wd = f"/tmp/specjoin-{tag}"
    shutil.rmtree(wd, ignore_errors=True)
    os.makedirs(wd)
    for d in ("pool", "packages", "maps", "games", "rapid"):
        os.symlink(f"{DD}/{d}", f"{wd}/{d}")
    if os.path.isdir(f"{DD}/cache"): subprocess.run(["cp", "-R", f"{DD}/cache", f"{wd}/cache"])
    if os.path.exists(f"{DD}/springsettings.cfg"): shutil.copy(f"{DD}/springsettings.cfg", wd)
    extra = os.environ.get("SPEC_EXTRA_CFG", "")
    if extra:
        with open(f"{wd}/springsettings.cfg", "a") as fh:
            for line in extra.split(";"):
                if line.strip(): fh.write(line.strip() + "\n")
    os.makedirs(f"{wd}/LuaUI/Widgets", exist_ok=True)
    job = os.path.dirname(os.path.abspath(__file__))
    shutil.copy(f"{job}/speclog.lua", f"{wd}/LuaUI/Widgets/speclog.lua")
    shutil.copy(f"{job}/pauseprobe.lua", f"{wd}/LuaUI/Widgets/pauseprobe.lua")
    shutil.copy(f"{job}/camsweep.lua", f"{wd}/LuaUI/Widgets/camsweep.lua")
    if os.environ.get("SPEC_HOVER"):
        shutil.copy(f"{job}/hoverhunt.lua", f"{wd}/LuaUI/Widgets/hoverhunt.lua")
    return wd

def run_engine(wd, icd, pooling, script, minutes):
    env = dict(os.environ,
        EGL_PLATFORM="surfaceless", GALLIUM_DRIVER="zink",
        MESA_LOADER_DRIVER_OVERRIDE="zink", MESA_GL_VERSION_OVERRIDE="4.6",
        VK_ICD_FILENAMES=icd, VK_DRIVER_FILES=icd,
        MVK_CONFIG_LOG_LEVEL=os.environ.get("MVK_CONFIG_LOG_LEVEL", "1"),
        DYLD_FALLBACK_LIBRARY_PATH=f"{APP}/Contents/Frameworks",
        SPRING_DATADIR=f"{APP}/Contents/Resources",
        MVK_CONFIG_USE_COMMAND_POOLING=pooling,
        # the launcher turns argument buffers off, run the same configuration the user plays
        MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=os.environ.get("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "0"))
    errlog = open(f"{wd}/stderr.log", "wb")
    proc = subprocess.Popen([f"{APP}/Contents/MacOS/spring", "--write-dir", wd, "-window", script],
                            env=env, stdout=errlog, stderr=subprocess.STDOUT)
    infolog = f"{wd}/infolog.txt"
    t0 = time.time(); connected = False; verdict = None; bad = []
    lastSimFrame, lastSimMove = 0, time.time()
    deadline = t0 + minutes * 60
    while time.time() < deadline:
        time.sleep(5)
        if proc.poll() is not None:
            verdict = f"engine-exited({proc.returncode})"; break
        txt = ""
        for p in (infolog, f"{wd}/stderr.log"):
            if os.path.exists(p): txt += open(p, errors="replace").read()
        if not connected and ("GameDataReceived" in txt or re.search(r"\[f=0*\d", txt)):
            connected = True
            print(f"  connected at t+{time.time()-t0:.0f}s")
        # a spectator whose sim stops advancing renders a frozen scene and stresses
        # nothing, so stop counting that as exposure
        if connected:
            fr = re.findall(r"\[f=(\d+)\]", txt)
            cur = int(fr[-1]) if fr else 0
            if cur > lastSimFrame:
                lastSimFrame, lastSimMove = cur, time.time()
            elif time.time() - lastSimMove > 90:
                verdict = "sim-stalled"; break
        hits = [l for l in txt.splitlines() if BAD.search(l)]
        if hits:
            bad = hits; verdict = "DEVICE-LOSS"; time.sleep(10); break
        if not connected and time.time() - t0 > 100:
            subprocess.run(["sample", str(proc.pid), "3", "-file", f"{wd}/sample.txt"],
                           capture_output=True)
            verdict = "no-connect"; break
    if verdict is None:
        verdict = "clean" if connected else "no-connect"
    frames = 0
    if os.path.exists(infolog):
        m = re.findall(r"\[f=(\d+)\]", open(infolog, errors="replace").read())
        if m: frames = int(m[-1])
    proc.kill()
    return verdict, bad, frames, time.time() - t0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--dylib", required=True)
    ap.add_argument("--minutes", type=float, default=8)
    ap.add_argument("--pooling", default="0")
    ap.add_argument("--attempts", type=int, default=3)
    ap.add_argument("--mvkdebug", action="store_true")
    ap.add_argument("--userlua", action="store_true")
    ap.add_argument("--shaderval", action="store_true")
    ap.add_argument("--minage", type=int, default=0)
    ap.add_argument("--maxage", type=int, default=0, help="skip games older than this many minutes, so the run is not cut short by the game ending")
    ap.add_argument("--mappref", default="")
    args = ap.parse_args()

    job = os.path.dirname(os.path.abspath(__file__))
    icd_dir = f"{job}/icd-{args.tag}"; os.makedirs(icd_dir, exist_ok=True)
    icd = f"{icd_dir}/moltenvk_icd.json"
    open(icd, "w").write('{"ICD":{"api_version":"1.3.0","library_path":"%s","is_portability_driver":true},"file_format_version":"1.0.1"}' % args.dylib)

    wd = make_wd(args.tag)
    if args.userlua and os.path.isdir(f"{DD}/LuaUI"):
        shutil.rmtree(f"{wd}/LuaUI", ignore_errors=True)
        subprocess.run(["cp", "-R", f"{DD}/LuaUI", f"{wd}/LuaUI"])
        job = os.path.dirname(os.path.abspath(__file__))
        shutil.copy(f"{job}/speclog.lua", f"{wd}/LuaUI/Widgets/speclog.lua")
        if os.environ.get("SPEC_HOVER"):
            shutil.copy(f"{job}/hoverhunt.lua", f"{wd}/LuaUI/Widgets/hoverhunt.lua")
        shutil.copy(f"{job}/pauseprobe.lua", f"{wd}/LuaUI/Widgets/pauseprobe.lua")
        shutil.copy(f"{job}/camsweep.lua", f"{wd}/LuaUI/Widgets/camsweep.lua")
        if os.environ.get("SPEC_NO_OVERRIDES"):
            for f in ("gui_healthbars_gl4.lua", "gfx_unit_stencil_gl4.lua", "gui_unit_firestate_icons.lua"):
                p = f"{wd}/LuaUI/Widgets/{f}"
                if os.path.exists(p): os.remove(p)
            print("issue5 overrides removed")
        print("user LuaUI copied in")
    lob = Lobby(f"{wd}/lobby.log")
    lob.login()
    print("logged in")
    tried = set()
    for attempt in range(args.attempts):
        good = [g for g in lob.collect_battles() if g[1] not in tried]
        if not good:
            print("VERDICT no-battle"); return 2
        if args.mappref:
            pref = [g for g in good if args.mappref.lower() in g[2]["map"].lower()]
            if pref: good = pref
        n, bid, b = good[0]; tried.add(bid)
        sp = secrets.token_hex(12)
        lob.send(f"JOINBATTLE {bid} empty {sp}")
        t0 = time.time(); ok = False
        while time.time() - t0 < 15:
            try: s = lob.readline()
            except (socket.timeout, TimeoutError): break
            if s.startswith("JOINBATTLEFAILED"): break
            if s.startswith("JOINBATTLE "): ok = True; break
        if not ok:
            print(f"attempt {attempt}: join failed for battle {bid}"); continue
        print(f"attempt {attempt}: joined battle {bid} players={n} map={b['map']!r} host={b['ip']}:{b['port']}")
        lob.send("MYBATTLESTATUS 4194304 0")
        lob.send("SAYBATTLE !joinas spec")
        t0 = time.time(); authed = False; age = None
        while time.time() - t0 < 25:
            try: s = lob.readline(timeout=max(0.3, 25 - (time.time() - t0)))
            except (socket.timeout, TimeoutError): break
            low = s.lower()
            m = re.search(r"in progress since (?:(\d+) hours? )?(?:and )?(\d+) minutes", low)
            if m: age = int(m.group(1) or 0) * 60 + int(m.group(2))
            if "adding user vandomas as spectator" in low or "already been added" in low:
                authed = True
                if age is not None: break
        if authed and args.maxage and age is not None and age > args.maxage:
            print(f"attempt {attempt}: game age {age}min > {args.maxage}min, skipping")
            lob.send("LEAVEBATTLE"); continue
        if authed and args.minage and age is not None and age < args.minage:
            print(f"attempt {attempt}: game age {age}min < {args.minage}min, skipping")
            lob.send("LEAVEBATTLE"); continue
        if age is not None: print(f"  game age: {age} min")
        if not authed:
            print(f"attempt {attempt}: no joinas confirmation; recent lobby traffic:")
            for l in lob.tail[-12:]: print("   |", l)
            lob.send("LEAVEBATTLE"); continue
        print("  spads confirmed spectator add")
        lob.pump()
        script = f"{wd}/script.txt"
        open(script, "w").write("[GAME]\n{\n" f"HostIP={b['ip']};\nHostPort={b['port']};\n"
            "MyPlayerName=Vandomas;\n" f"MyPasswd={sp};\n" "IsHost=0;\n}\n")
        if args.mvkdebug:
            os.environ["MVK_CONFIG_DEBUG"] = "1"
            os.environ["MVK_CONFIG_LOG_LEVEL"] = "3"
        if args.shaderval:
            os.environ["MTL_SHADER_VALIDATION"] = "1"
            os.environ["MTL_SHADER_VALIDATION_REPORT_TO_STDERR"] = "1"
        verdict, bad, frames, alive = run_engine(wd, icd, args.pooling, script, args.minutes)
        lob.alive = False; time.sleep(6)  # stop pump before sync reads
        lob.alive = True
        if verdict == "sim-stalled":
            print(f"attempt {attempt}: the sim stopped advancing, run does not count, rejoining")
            lob.send("LEAVEBATTLE")
            for pth in (f"{wd}/infolog.txt",):
                if os.path.exists(pth): os.rename(pth, f"{wd}/infolog-attempt{attempt}.txt")
            continue
        if verdict.startswith("engine-exited") and frames == 0 and not bad:
            print(f"attempt {attempt}: {verdict} before first frame (connection timeout), retrying elsewhere")
            lob.send("LEAVEBATTLE")
            for pth in (f"{wd}/infolog.txt",):
                if os.path.exists(pth): os.rename(pth, f"{wd}/infolog-attempt{attempt}.txt")
            continue
        if verdict == "no-connect":
            print(f"attempt {attempt}: no-connect; recent lobby traffic:")
            for l in lob.tail[-15:]: print("   |", l)
            lob.send("LEAVEBATTLE")
            for p in (f"{wd}/infolog.txt",):
                if os.path.exists(p): os.rename(p, f"{wd}/infolog-attempt{attempt}.txt")
            continue
        try:
            resumed = len(RESUMED.findall(open(f"{wd}/stderr.log", errors="replace").read()))
        except OSError:
            resumed = 0
        print(f"VERDICT {verdict} tag={args.tag} battle={bid} map={b['map']!r} alive={alive:.0f}s lastframe={frames} resumed={resumed}")
        for l in bad[:8]: print("  BAD:", l)
        info = f"/tmp/specjoin-{args.tag}/infolog.txt"
        if os.path.exists(info):
            samples = re.findall(r"SPECPERF-\w+ f=\d+ fps=(\d+) maxdt=(\d+)", open(info, errors="replace").read())
            if samples:
                fps = [int(a) for a, _ in samples]; dts = [int(b) for _, b in samples]
                fps_s = sorted(fps); dts_s = sorted(dts)
                print(f"PERF samples={len(fps)} fps_med={fps_s[len(fps_s)//2]} fps_min={fps_s[0]} "
                      f"maxdt_med={dts_s[len(dts_s)//2]}ms maxdt_p95={dts_s[int(len(dts_s)*0.95)]}ms maxdt_worst={dts_s[-1]}ms")
        lob.send("LEAVEBATTLE"); time.sleep(1); lob.send("EXIT bye")
        return 0 if verdict == "clean" else 1
    print("VERDICT no-connect-all-attempts")
    return 2

sys.exit(main())
