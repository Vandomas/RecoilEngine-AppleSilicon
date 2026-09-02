#!/usr/bin/env python3
"""Pick a public BAR replay that this machine can actually replay, and download it.

Filters on the three things that make a replay unusable offline:
  * engineVersion must equal the engine binary's version (the demo stream is
    version-locked; replay-check.sh refuses a mismatch outright)
  * gameVersion must be an installed rapid tag (packages/<hash>.sdp present)
  * the map must be installed under maps/
and on the two that make it worth running: real team game, long enough.
"""
import argparse, glob, gzip, json, os, re, subprocess, sys, urllib.parse, urllib.request

API = "https://api.bar-rts.com/replays"
CDN = "https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/"
DD = os.path.expanduser("~/Library/Application Support/Beyond-All-Reason-mac")


def installed_game_versions():
    sdps = {f[:-4] for f in os.listdir(f"{DD}/packages") if f.endswith(".sdp")}
    names = set()
    for v in glob.glob(f"{DD}/rapid/*/*/versions.gz"):
        with gzip.open(v, "rt", errors="replace") as fh:
            for line in fh:
                p = line.strip().split(",")
                if len(p) >= 4 and p[1] in sdps:
                    names.add(p[3])
    return names


def local_map(script_name):
    return bool(glob.glob(f"{DD}/maps/{glob.escape(script_name.lower().replace(' ', '_'))}.sd*"))


def get(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, help="engine version the binary reports, e.g. 2026.07.04")
    ap.add_argument("--minplayers", type=int, default=14)
    ap.add_argument("--minminutes", type=float, default=18)
    ap.add_argument("--pages", type=int, default=8)
    ap.add_argument("--out", default=f"{DD}/demos")
    ap.add_argument("--count", type=int, default=1)
    args = ap.parse_args()

    games = installed_game_versions()
    print(f"installed game versions: {len(games)}", file=sys.stderr)
    got = []
    for page in range(1, args.pages + 1):
        page_data = get(f"{API}?limit=50&page={page}&preset=team&hasBots=false")["data"]
        if not page_data:
            break
        for r in page_data:
            nplayers = sum(len(at["Players"]) for at in r["AllyTeams"])
            if nplayers < args.minplayers:
                continue
            if r["durationMs"] < args.minminutes * 60000:
                continue
            if not local_map(r["Map"]["scriptName"]):
                continue
            d = get(f"{API}/{r['id']}")
            if d["engineVersion"] != args.engine or d["gameVersion"] not in games:
                continue
            dest = os.path.join(args.out, d["fileName"])
            if not os.path.exists(dest):
                url = CDN + urllib.parse.quote(d["fileName"])
                subprocess.run(["curl", "-sSfL", "-o", dest, url], check=True)
            print(f"{dest}\t{nplayers}p\t{d['durationMs']//1000}s\t{r['Map']['scriptName']}\t{d['gameVersion']}")
            got.append(dest)
            if len(got) >= args.count:
                return 0
    if not got:
        print("no replay matched", file=sys.stderr)
        return 1
    return 0


sys.exit(main())
