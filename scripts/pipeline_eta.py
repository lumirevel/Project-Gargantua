#!/usr/bin/env python3
import argparse
from collections import deque
import json
import math
import queue
import re
import subprocess
import sys
import threading
import time
from pathlib import Path


def fmt_duration(seconds: float) -> str:
    seconds = max(float(seconds), 0.0)
    if seconds < 60.0:
        return f"{seconds:04.1f}s"
    total = int(round(seconds))
    hours, rem = divmod(total, 3600)
    minutes, secs = divmod(rem, 60)
    if hours > 0:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a command with ETA display and history calibration")
    parser.add_argument("--history", type=str, required=True)
    parser.add_argument("--stage", type=str, choices=("swift", "python"), required=True)
    parser.add_argument("--metric", type=str, default="schwarzschild")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--max-steps", type=int, default=1600)
    parser.add_argument("--kerr-substeps", type=int, default=4)
    parser.add_argument("--spectral-step", type=float, default=5.0)
    parser.add_argument("--ssaa", type=int, default=1)
    parser.add_argument("--relay-output", type=str, choices=("always", "errors", "none"), default="errors")
    parser.add_argument("--buffer-lines", type=int, default=120)
    parser.add_argument("--cmd", nargs=argparse.REMAINDER, required=True)
    return parser.parse_args()


def load_history(path: Path) -> list[dict]:
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return [x for x in data if isinstance(x, dict)]
    except FileNotFoundError:
        return []
    except Exception:
        return []
    return []


def save_history(path: Path, history: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(history[-600:], f, ensure_ascii=False, indent=2)


def compute_work(stage: str, metric: str, width: int, height: int, max_steps: int, kerr_substeps: int, spectral_step: float) -> float:
    rays = float(max(width, 1) * max(height, 1))
    if stage == "swift":
        sub = max(kerr_substeps, 1) if metric == "kerr" else 1
        return rays * float(max(max_steps, 1)) * float(sub)
    lam_samples = max(1.0, 371.0 / max(spectral_step, 0.25))
    return rays * lam_samples


def baseline_spw(stage: str, metric: str) -> float:
    if stage == "swift":
        return 2.7e-9 if metric == "kerr" else 7.0e-10
    return 1.8e-9


def baseline_duration(stage: str, metric: str, work: float) -> float:
    base = baseline_spw(stage, metric) * work
    overhead = 0.35 if stage == "swift" else 0.18
    return overhead + base


def pick_prediction(history: list[dict], args: argparse.Namespace, work: float) -> tuple[float, float, int]:
    stage = args.stage
    metric = args.metric.lower()
    candidates = [
        e
        for e in history
        if e.get("stage") == stage and e.get("metric") == metric and float(e.get("duration", 0.0)) > 0.0 and float(e.get("work", 0.0)) > 0.0
    ]

    if stage == "swift":
        near = [
            e
            for e in candidates
            if int(e.get("max_steps", -1)) == int(args.max_steps)
            and int(e.get("kerr_substeps", -1)) == (int(args.kerr_substeps) if metric == "kerr" else 1)
        ]
    else:
        near = [
            e
            for e in candidates
            if abs(float(e.get("spectral_step", 5.0)) - float(args.spectral_step)) < 1e-6
        ]

    pool = near if len(near) >= 2 else candidates
    if not pool:
        spw = baseline_spw(stage, metric)
        return baseline_duration(stage, metric, work), spw, 0

    now_ts = time.time()
    ratios: list[tuple[float, float]] = []
    xs: list[tuple[float, float, float]] = []
    for e in pool[-160:]:
        hist_work = float(e["work"])
        hist_dur = float(e["duration"])
        ratio = hist_dur / hist_work
        age = max(now_ts - float(e.get("ts", now_ts)), 0.0)
        weight = math.exp(-age / (14.0 * 24.0 * 3600.0))
        ratios.append((ratio, weight))
        xs.append((hist_work, hist_dur, weight))

    sorted_ratio = sorted(r for r, _ in ratios)
    lo_idx = int(0.1 * (len(sorted_ratio) - 1))
    hi_idx = int(0.9 * (len(sorted_ratio) - 1))
    lo = sorted_ratio[lo_idx]
    hi = sorted_ratio[hi_idx]

    num = 0.0
    den = 0.0
    for ratio, weight in ratios:
        clipped = min(max(ratio, lo), hi)
        num += clipped * weight
        den += weight
    spw = num / max(den, 1e-12)

    pred_ratio = spw * work
    pred_base = baseline_duration(stage, metric, work)

    sw = sum(w for _, _, w in xs)
    sx = sum(w * x for x, _, w in xs)
    sy = sum(w * y for _, y, w in xs)
    sxx = sum(w * x * x for x, _, w in xs)
    sxy = sum(w * x * y for x, y, w in xs)
    denom = sw * sxx - sx * sx
    if denom > 1e-9 and sw > 0.0:
        slope = (sw * sxy - sx * sy) / denom
        intercept = (sy - slope * sx) / sw
        slope = max(slope, 0.0)
        intercept = max(intercept, 0.0)
        pred_linear = intercept + slope * work
    else:
        pred_linear = pred_ratio

    if len(pool) >= 8:
        blend = 0.70
    elif len(pool) >= 4:
        blend = 0.55
    else:
        blend = 0.35
    pred_hist = blend * pred_linear + (1.0 - blend) * pred_ratio

    if len(pool) <= 2:
        pred = 0.45 * pred_hist + 0.55 * pred_base
    else:
        pred = 0.8 * pred_hist + 0.2 * pred_base
    return max(pred, 0.05), spw, len(pool)


def reader_thread(pipe, out_q: "queue.Queue[str]") -> None:
    try:
        for line in pipe:
            out_q.put(line)
    finally:
        out_q.put("")

PROGRESS_RE = re.compile(r"^ETA_PROGRESS\s+(\d+)\s+(\d+)(?:\s+([A-Za-z0-9_.-]+))?$")


def main() -> int:
    args = parse_args()
    cmd = args.cmd
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        print("pipeline_eta.py: missing command after --cmd", file=sys.stderr)
        return 2

    history_path = Path(args.history)
    history = load_history(history_path)
    work = compute_work(
        stage=args.stage,
        metric=args.metric.lower(),
        width=args.width,
        height=args.height,
        max_steps=args.max_steps,
        kerr_substeps=args.kerr_substeps,
        spectral_step=args.spectral_step,
    )
    predicted, spw, _history_count = pick_prediction(history, args, work)

    print(
        f"[eta] stage={args.stage} metric={args.metric} size={args.width}x{args.height} "
        f"pred={fmt_duration(predicted)}",
        file=sys.stderr,
    )

    start = time.time()
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        universal_newlines=True,
    )

    out_q: "queue.Queue[str]" = queue.Queue()
    t = threading.Thread(target=reader_thread, args=(proc.stdout, out_q), daemon=True)
    t.start()

    last_draw = 0.0
    done_reader = False
    status_text = ""
    is_tty = sys.stderr.isatty()
    buffered_lines: deque[str] = deque(maxlen=max(args.buffer_lines, 20))
    op_done = 0.0
    op_total = 0.0
    progress_phase = ""
    ema_rate = None
    last_prog_time = None
    last_prog_done = None

    def clear_status() -> None:
        nonlocal status_text
        if is_tty and status_text:
            sys.stderr.write("\r\033[2K")
            sys.stderr.flush()
            status_text = ""

    def buffer_line(line: str) -> None:
        clean = line.rstrip("\n")
        if clean:
            buffered_lines.append(f"[{args.stage}] {clean}")

    def ingest_progress(line: str, now: float) -> bool:
        nonlocal op_done, op_total, progress_phase, ema_rate, last_prog_time, last_prog_done
        m = PROGRESS_RE.match(line.strip())
        if not m:
            return False
        cur = float(m.group(1))
        tot = float(m.group(2))
        phase = m.group(3) or ""
        if tot > 0.0:
            cur = min(max(cur, 0.0), tot)
            op_done = cur
            op_total = tot
            progress_phase = phase
            if last_prog_time is not None and last_prog_done is not None:
                dt = now - last_prog_time
                dd = cur - last_prog_done
                if dt > 1e-6 and dd >= 0.0:
                    inst_rate = dd / dt
                    if inst_rate > 0.0:
                        if ema_rate is None:
                            ema_rate = inst_rate
                        else:
                            ema_rate = 0.75 * ema_rate + 0.25 * inst_rate
            last_prog_time = now
            last_prog_done = cur
        return True

    while True:
        drained = False
        while True:
            try:
                line = out_q.get_nowait()
            except queue.Empty:
                break
            drained = True
            if line == "":
                done_reader = True
                continue
            now_line = time.time()
            if ingest_progress(line, now_line):
                continue
            buffer_line(line)
            if args.relay_output == "always":
                clear_status()
                sys.stdout.write(f"[{args.stage}] {line}")
                if not line.endswith("\n"):
                    sys.stdout.write("\n")
                sys.stdout.flush()

        now = time.time()
        if is_tty and (now - last_draw >= 1.5):
            elapsed = now - start
            if op_total > 0.0:
                progress = min(max(op_done / op_total, 0.0), 0.999)
                remain_ops = max(op_total - op_done, 0.0)
                if ema_rate is not None and ema_rate > 1e-9:
                    remain = remain_ops / ema_rate
                elif progress > 1e-6:
                    rate = op_done / max(elapsed, 1e-6)
                    remain = remain_ops / max(rate, 1e-9)
                else:
                    remain = max(predicted - elapsed, 0.0)
            else:
                remain = max(predicted - elapsed, 0.0)
                progress = min(elapsed / predicted, 0.999) if predicted > 0.0 else 0.0
            mode = "ops" if op_total > 0.0 else "pred"
            phase_txt = f" {progress_phase}" if progress_phase else ""
            status_text = (
                f"[eta][{args.stage}] {progress * 100:5.1f}% "
                f"elapsed {fmt_duration(elapsed)} "
                f"remaining {fmt_duration(remain)} "
                f"pred {fmt_duration(predicted)} "
                f"[{mode}{phase_txt}]"
            )
            sys.stderr.write("\r\033[2K" + status_text)
            sys.stderr.flush()
            last_draw = now

        rc = proc.poll()
        if rc is not None and done_reader and not drained:
            break
        time.sleep(0.05)

    end = time.time()
    actual = end - start
    error_pct = (abs(actual - predicted) / max(actual, 1e-6)) * 100.0
    clear_status()
    if proc.returncode != 0 and args.relay_output != "none" and buffered_lines:
        print(f"[eta][{args.stage}] command failed, recent output:", file=sys.stderr)
        for ln in buffered_lines:
            print(ln, file=sys.stderr)
    print(
        f"[eta][{args.stage}] done elapsed {fmt_duration(actual)} "
        f"pred {fmt_duration(predicted)} err {error_pct:4.1f}%",
        file=sys.stderr,
    )

    history.append(
        {
            "ts": end,
            "stage": args.stage,
            "metric": args.metric.lower(),
            "width": args.width,
            "height": args.height,
            "ssaa": args.ssaa,
            "max_steps": args.max_steps,
            "kerr_substeps": args.kerr_substeps if args.metric.lower() == "kerr" else 1,
            "spectral_step": args.spectral_step,
            "work": work,
            "spw": spw,
            "predicted": predicted,
            "duration": actual,
            "success": (proc.returncode == 0),
        }
    )
    save_history(history_path, history)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
