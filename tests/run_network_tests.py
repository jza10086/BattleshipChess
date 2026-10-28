#!/usr/bin/env python3
"""Bounded, genuine localhost ENet integration using separate Godot processes.

The test harness automates player intentions. It never edits the authoritative
referee, invents snapshots, or adds test AI to the production game.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def choose_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def run_case(binary: str, scenario: str, output: Path) -> bool:
    case = output / scenario
    case.mkdir(parents=True)
    port = choose_port()
    env = os.environ.copy()
    for kind in ("CACHE", "DATA", "CONFIG"):
        path = case / kind.lower()
        path.mkdir()
        env[f"XDG_{kind}_HOME"] = str(path)
    env["LP_NUM_THREADS"] = "2"
    processes: list[tuple[str, subprocess.Popen, object, Path]] = []

    def affinity() -> None:
        if hasattr(os, "sched_getaffinity"):
            os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:2])

    def launch(role: str) -> None:
        path = case / f"{role}.log"
        handle = path.open("w")
        cmd = [binary, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
               "--script", "res://tests/network_peer.gd", "--", f"role={role}",
               f"scenario={scenario}", f"port={port}", f"out={case}"]
        process = subprocess.Popen(cmd, stdout=handle, stderr=subprocess.STDOUT,
                                   env=env, preexec_fn=affinity)
        processes.append((role, process, handle, path))

    launch("host")
    time.sleep(0.45)
    launch("client")
    spawned: set[str] = set()
    deadline = time.monotonic() + 32
    while time.monotonic() < deadline:
        stage_file = case / "stage.txt"
        stage = stage_file.read_text() if stage_file.exists() else ""
        if scenario == "match":
            for stage_name, role in (("full_lobby", "reject_full"), ("late_join", "reject_late")):
                if stage == stage_name and role not in spawned:
                    launch(role)
                    spawned.add(role)
        if all(proc.poll() is not None for _, proc, _, _ in processes):
            break
        time.sleep(0.035)
    success = True
    for role, proc, handle, path in processes:
        if proc.poll() is None:
            proc.kill()
        proc.wait(timeout=3)
        handle.close()
        log = path.read_text(errors="replace")
        result = re.search(r"NETWORK_PEER_RESULT[^\n]*failures=(\d+)[^\n]*", log)
        good = proc.returncode == 0 and result is not None and result[1] == "0" and not re.search(r"SCRIPT ERROR|^ERROR:|FAIL:", log, re.M)
        if good:
            print(f"PASS {scenario}/{role}: {result[0]}")
        else:
            success = False
            print(f"FAIL {scenario}/{role} exit={proc.returncode}\n{log[-15000:]}")
    if scenario == "match":
        if spawned != {"reject_full", "reject_late"}:
            print("FAIL: full and midgame rejection probes were not both launched")
            success = False
        public: dict[str, dict[tuple[int, str, int], dict]] = {}
        for role in ("host", "client"):
            records = {}
            log = (case / f"{role}.log").read_text(errors="replace")
            for line in log.splitlines():
                if not line.startswith("PUBLIC_SNAPSHOT "):
                    continue
                state = json.loads(line.removeprefix("PUBLIC_SNAPSHOT "))
                key = (state["round"], state["phase"], len(state["shots"]))
                records[key] = state
            public[role] = records
        matching = set(public["host"]) & set(public["client"])
        mismatch = [key for key in matching if public["host"][key] != public["client"][key]]
        battle_count = len([key for key in matching if key[1] in ("battle", "finished")])
        if mismatch or battle_count != 34:
            print(f"FAIL authoritative public state equality: battle states={battle_count}, mismatches={mismatch}")
            success = False
        else:
            print("PASS authoritative public state equality: all34 battle/finished snapshots identical across actual peers")
    print(f"NETWORK_CASE scenario={scenario} result={'PASS' if success else 'FAIL'} logs={case}")
    return success


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix="battleship-enet-"))
    output.mkdir(parents=True, exist_ok=True)
    results = [run_case(args.godot, scenario, output) for scenario in ("match", "disconnect")]
    print(f"NETWORK_TESTS: {sum(results)}/{len(results)} cases passed; logs={output}")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
