#!/usr/bin/env python3
import argparse
from collections import deque
import json
import math
import os
import queue
import re
import shutil
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
    parser.add_argument("--variant", type=str, default="")
    parser.add_argument(
        "--eta-mode",
        type=str,
        choices=("simple", "runtime-linear", "ml-lite", "auto"),
        default=os.environ.get("BH_ETA_MODE", "runtime-linear"),
        help="simple: elapsed*(1-progress)/progress, runtime-linear: current-run linear fit, ml-lite: +history correction, auto: alias of runtime-linear",
    )
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
        if e.get("stage") == stage
        and e.get("metric") == metric
        and bool(e.get("success", True))
        and float(e.get("duration", 0.0)) > 0.0
        and float(e.get("work", 0.0)) > 0.0
    ]

    if args.variant:
        vpool = [e for e in candidates if str(e.get("variant", "")) == args.variant]
        if len(vpool) >= 3:
            candidates = vpool

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

PROGRESS_RE = re.compile(r"^ETA_PROGRESS\s+(\d+)\s+(\d+)(?:\s+([A-Za-z0-9_.-]+))?(?:\s+(.*))?$")
TILE_RE = re.compile(r"^\s*(\d+)\s*/\s*(\d+)\s*$")


def fit_status_to_terminal(text: str) -> str:
    cols = 120
    try:
        if sys.stderr.isatty():
            cols = os.get_terminal_size(sys.stderr.fileno()).columns
        else:
            cols = shutil.get_terminal_size(fallback=(120, 24)).columns
    except OSError:
        cols = shutil.get_terminal_size(fallback=(120, 24)).columns
    max_len = max(4, cols - 1)
    if len(text) <= max_len:
        return text
    if max_len <= 3:
        return text[:max_len]
    return text[: max_len - 3] + "..."


def progress_group(stage: str, phase: str, task: str) -> str:
    stage = (stage or "").lower()
    phase = (phase or "").lower()
    task = (task or "").lower()
    if stage == "swift":
        if phase.startswith("swift_trace"):
            return "trace"
        if phase.startswith("swift_prepass"):
            return "light"
        if phase.startswith("swift_compose"):
            return "compose"
    if stage == "python":
        if phase.startswith("python_compose"):
            return "compose"
    if "hist" in task or "lum" in task or "cloud" in task:
        return "light"
    if "trace" in task:
        return "trace"
    if "compose" in task:
        return "compose"
    return stage or "stage"


def fit_linear_rate(samples: deque[tuple[float, float]]) -> float:
    if len(samples) < 3:
        return 0.0
    t0 = samples[0][0]
    sw = 0.0
    sx = 0.0
    sy = 0.0
    sxx = 0.0
    sxy = 0.0
    n = len(samples)
    for i, (t, y) in enumerate(samples):
        x = max(t - t0, 0.0)
        w = 0.35 + 0.65 * ((i + 1) / max(n, 1))
        sw += w
        sx += w * x
        sy += w * y
        sxx += w * x * x
        sxy += w * x * y
    denom = sw * sxx - sx * sx
    if denom <= 1e-9:
        return 0.0
    slope = (sw * sxy - sx * sy) / denom
    return max(slope, 0.0)


def phase_prior_seconds(args: argparse.Namespace, group_name: str, predicted_prior: float) -> float:
    metric = args.metric.lower()
    sub = max(int(args.kerr_substeps), 1) if metric == "kerr" else 1
    trace_weight = float(max(int(args.max_steps), 1) * sub)
    light_weight = 4.0
    compose_weight = 2.0
    total = trace_weight + light_weight + compose_weight
    if total <= 0.0:
        return max(predicted_prior, 0.2)
    if group_name == "trace":
        ratio = trace_weight / total
    elif group_name == "light":
        ratio = light_weight / total
    elif group_name == "compose":
        ratio = compose_weight / total
    else:
        ratio = 1.0 / total
    return max(predicted_prior * ratio, 0.08)


def state_progress(state: dict) -> float:
    tile_total = float(state.get("tile_total", 0.0) or 0.0)
    if tile_total > 0.0:
        tile_done = float(state.get("tile_done", 0.0) or 0.0)
        return min(max(tile_done / max(tile_total, 1.0), 0.0), 0.999)
    op_done = float(state.get("op_done", 0.0) or 0.0)
    op_total = max(float(state.get("op_total", 1.0) or 1.0), 1.0)
    return min(max(op_done / op_total, 0.0), 0.999)


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
    if args.eta_mode == "auto":
        args.eta_mode = "runtime-linear"

    predicted_prior = baseline_duration(args.stage, args.metric.lower(), work)
    predicted_hist, spw, history_count = pick_prediction(history, args, work)
    use_history_signal = (args.eta_mode == "ml-lite" and history_count >= 3)
    predicted = predicted_prior
    if args.eta_mode == "simple":
        print("[eta] mode=simple", file=sys.stderr)
    elif args.eta_mode == "runtime-linear":
        print(f"[eta] mode=runtime-linear prior={fmt_duration(predicted_prior)}", file=sys.stderr)
    elif args.eta_mode == "ml-lite":
        print(
            f"[eta] mode=ml-lite prior={fmt_duration(predicted_prior)} hist={fmt_duration(predicted_hist)} n={history_count}",
            file=sys.stderr,
        )
    else:
        print(f"[eta] mode={args.eta_mode}", file=sys.stderr)

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
    needs_draw = False
    done_reader = False
    status_text = ""
    is_tty = sys.stderr.isatty()
    buffered_lines: deque[str] = deque(maxlen=max(args.buffer_lines, 20))
    current_progress_key = ""
    current_group = ""
    progress_phase = ""
    progress_task = ""
    progress_tile = ""
    progress_unit = "op"
    phase_states: dict[str, dict] = {}
    group_states: dict[str, dict] = {}

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

    def emit_group_done_line(group_name: str, now_t: float) -> None:
        if not group_name:
            return
        st = group_states.get(group_name)
        if not st:
            return
        if bool(st.get("done_printed", False)):
            return
        started = float(st.get("started_at", start))
        elapsed_grp = max(now_t - started, 0.0)
        task_text = str(st.get("task", "")).strip()
        tile_text = str(st.get("tile", "")).strip()
        done = float(st.get("done", 0.0))
        total = max(float(st.get("total", 1.0)), 1.0)
        tile_m = TILE_RE.match(tile_text) if tile_text else None
        if tile_m is not None:
            done_text = f"{int(tile_m.group(1))}/{max(int(tile_m.group(2)), 1)}"
            unit_name = "tiles"
        else:
            done_text = f"{int(done)}/{int(total)}"
            unit_name = "ops"
        suffix = ""
        if task_text:
            suffix += f" task={task_text}"
        if tile_text:
            suffix += f" tile={tile_text}"
        print(
            f"[eta-phase] group={group_name} done {done_text} ({unit_name}) elapsed={fmt_duration(elapsed_grp)}{suffix}",
            file=sys.stderr,
        )
        st["done_printed"] = True

    def ingest_progress(line: str, now: float) -> bool:
        nonlocal current_progress_key, current_group, progress_phase, progress_task, progress_tile, progress_unit, needs_draw
        m = PROGRESS_RE.match(line.strip())
        if not m:
            return False
        cur = float(m.group(1))
        tot = float(m.group(2))
        phase = m.group(3) or ""
        extra = m.group(4) or ""
        task = ""
        tile = ""
        if extra:
            for token in extra.split():
                if "=" not in token:
                    continue
                k, v = token.split("=", 1)
                if k == "task":
                    task = v.replace("_", " ")
                elif k == "tile":
                    tile = v
        if not task and phase:
            if phase.startswith("swift_trace"):
                task = "trace"
            elif phase.startswith("swift_prepass"):
                task = "prepass"
            elif phase.startswith("swift_compose"):
                task = "compose"
            elif phase.startswith("python_compose"):
                task = "compose"
        key = f"{phase}|{task}" if (phase or task) else "default"
        if key not in phase_states:
            phase_states[key] = {
                "phase": phase,
                "task": task,
                "group": progress_group(args.stage, phase, task),
                "tile": "",
                "unit": "op",
                "done": 0.0,
                "total": 1.0,
                "op_done": 0.0,
                "op_total": 1.0,
                "tile_done": 0.0,
                "tile_total": 0.0,
                "ema_rate": None,
                "samples": 0,
                "last_t": None,
                "last_done": None,
                "started_at": now,
                "predicted": max(predicted * 0.30, 0.25),
                "samples_td": deque(maxlen=96),
                "samples_tp": deque(maxlen=96),
            }

        state = phase_states[key]
        state["phase"] = phase
        state["task"] = task
        state["group"] = progress_group(args.stage, phase, task)
        state["tile"] = tile

        done_value = min(max(cur, 0.0), max(tot, 1.0))
        total_value = max(tot, 1.0)
        unit = "op"
        state["op_done"] = done_value
        state["op_total"] = total_value

        tile_m = TILE_RE.match(tile) if tile else None
        if tile_m is not None:
            state["tile_done"] = float(tile_m.group(1))
            state["tile_total"] = float(max(int(tile_m.group(2)), 1))

        done_value = min(max(done_value, 0.0), total_value)
        state["unit"] = unit
        state["done"] = done_value
        state["total"] = total_value
        group_name = str(state["group"])

        if group_name not in group_states:
            group_states[group_name] = {
                "started_at": now,
                "done": done_value,
                "total": total_value,
                "task": task,
                "tile": tile,
                "done_printed": False,
                "current_key": key,
            }
        else:
            gs = group_states[group_name]
            gs["done"] = done_value
            gs["total"] = total_value
            gs["task"] = task
            gs["tile"] = tile
            gs["current_key"] = key

        if current_group and group_name != current_group:
            clear_status()
            emit_group_done_line(current_group, now)
            if group_name in group_states:
                group_states[group_name]["done_printed"] = False

        current_group = group_name
        current_progress_key = key
        progress_phase = phase
        progress_task = task
        progress_tile = tile
        progress_unit = unit
        needs_draw = True

        last_t = state["last_t"]
        last_done = state["last_done"]
        if last_t is not None and last_done is not None:
            dt = now - float(last_t)
            dd = done_value - float(last_done)
            if dt > 1e-6 and dd >= 0.0:
                inst_rate = dd / dt
                if inst_rate > 0.0:
                    state["samples"] = int(state["samples"]) + 1
                    if state["ema_rate"] is None:
                        state["ema_rate"] = inst_rate
                    else:
                        state["ema_rate"] = 0.75 * float(state["ema_rate"]) + 0.25 * inst_rate
        state["last_t"] = now
        state["last_done"] = done_value
        state["samples_td"].append((now, done_value))
        state["samples_tp"].append((now, state_progress(state)))
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
        if is_tty and (needs_draw or (now - last_draw >= 0.25)):
            elapsed = now - start
            if current_progress_key and current_progress_key in phase_states:
                state = phase_states[current_progress_key]
                group_name = str(state.get("group", current_group or args.stage))
                phase_started = float(group_states.get(group_name, {}).get("started_at", state["started_at"]))
                phase_elapsed = max(now - phase_started, 1e-6)
                progress = state_progress(state)

                if progress > 1e-6:
                    remain_simple = phase_elapsed * (1.0 - progress) / progress
                else:
                    remain_simple = max(phase_prior_seconds(args, group_name, predicted_prior) - phase_elapsed, 0.0)

                samples_tp = state.get("samples_tp")
                slope = fit_linear_rate(samples_tp) if isinstance(samples_tp, deque) else 0.0
                if slope > 1e-9:
                    remain_linear = max(1.0 - progress, 0.0) / slope
                else:
                    remain_linear = remain_simple

                remain_prior = max(phase_prior_seconds(args, group_name, predicted_prior) - phase_elapsed, 0.0)

                if args.eta_mode == "simple":
                    remain = remain_simple
                elif args.eta_mode == "runtime-linear":
                    if isinstance(samples_tp, deque) and len(samples_tp) >= 4:
                        w_lin = min(0.82, 0.26 + 0.02 * len(samples_tp))
                    else:
                        w_lin = 0.0
                    if progress < 0.08:
                        w_prior = 0.35
                    elif progress < 0.20:
                        w_prior = 0.20
                    else:
                        w_prior = 0.08
                    w_simple = max(0.0, 1.0 - w_lin - w_prior)
                    remain = w_lin * remain_linear + w_simple * remain_simple + w_prior * remain_prior
                else:
                    if isinstance(samples_tp, deque) and len(samples_tp) >= 4:
                        w_lin = min(0.72, 0.18 + 0.02 * len(samples_tp))
                    else:
                        w_lin = 0.0
                    w_prior = 0.10 if progress >= 0.10 else 0.25
                    w_hist = 0.0
                    if use_history_signal:
                        w_hist = 0.18 if progress < 0.45 else 0.10
                    w_simple = max(0.0, 1.0 - w_lin - w_prior - w_hist)
                    remain_hist = max(predicted_hist - state_elapsed, 0.0)
                    if remain_simple > 1e-6:
                        remain_hist = min(max(remain_hist, 0.45 * remain_simple), 2.20 * remain_simple)
                    remain = (
                        w_lin * remain_linear
                        + w_simple * remain_simple
                        + w_prior * remain_prior
                        + w_hist * remain_hist
                    )

                remain = max(remain, 0.0)
                predicted_dynamic = max(phase_elapsed + remain, phase_elapsed)
            else:
                progress = 0.0
                if args.eta_mode == "ml-lite" and use_history_signal:
                    predicted_dynamic = max(predicted_hist, elapsed)
                    remain = max(predicted_dynamic - elapsed, 0.0)
                else:
                    predicted_dynamic = max(predicted_prior, elapsed)
                    remain = max(predicted_dynamic - elapsed, 0.0)

            status_text = (
                f"[eta] {current_group or args.stage} {progress * 100:5.1f}% "
                f"{fmt_duration(elapsed)}<{fmt_duration(remain)} "
                f"({fmt_duration(predicted_dynamic)})"
            )
            if progress_task or progress_tile:
                task_parts = []
                if progress_task:
                    task_parts.append(progress_task)
                if progress_tile:
                    task_parts.append(progress_tile)
                status_text += " [" + " ".join(task_parts) + "]"
            elif progress_phase:
                status_text += f" [{progress_phase}]"
            if progress_unit == "tile":
                status_text += " {tile}"
            render_text = fit_status_to_terminal(status_text)
            sys.stderr.write("\r\033[2K" + render_text)
            sys.stderr.flush()
            last_draw = now
            needs_draw = False

        rc = proc.poll()
        if rc is not None and done_reader and not drained:
            break
        time.sleep(0.03)

    end = time.time()
    actual = end - start
    if current_progress_key and current_progress_key in phase_states:
        st = phase_states[current_progress_key]
        progress_final = state_progress(st)
        if progress_final > 1e-6:
            pred_simple_total = actual / progress_final
        else:
            pred_simple_total = actual
    else:
        pred_simple_total = actual

    if args.eta_mode == "simple" or not use_history_signal:
        predicted_dynamic = max(pred_simple_total, actual)
    elif args.eta_mode == "ml-lite":
        hist_pred = predicted_hist
        if pred_simple_total > 1e-6:
            hist_pred = min(max(hist_pred, 0.45 * pred_simple_total), 2.40 * pred_simple_total)
        predicted_dynamic = max(0.62 * hist_pred + 0.38 * pred_simple_total, actual)
    else:
        hist_pred = predicted_hist
        if pred_simple_total > 1e-6:
            hist_pred = min(max(hist_pred, 0.50 * pred_simple_total), 2.00 * pred_simple_total)
        if history_count >= 12:
            w_hist = 0.70
        elif history_count >= 6:
            w_hist = 0.55
        else:
            w_hist = 0.40
        predicted_dynamic = max(w_hist * hist_pred + (1.0 - w_hist) * pred_simple_total, actual)
    error_pct = (abs(actual - predicted_dynamic) / max(actual, 1e-6)) * 100.0
    clear_status()
    if proc.returncode != 0 and args.relay_output != "none" and buffered_lines:
        print("[eta] command failed, recent output:", file=sys.stderr)
        for ln in buffered_lines:
            print(ln, file=sys.stderr)

    # Emit completion line for the last active group once, instead of replaying all groups.
    if current_group:
        emit_group_done_line(current_group, end)

    done_task = f" task={progress_task}" if progress_task else ""
    done_tile = f" tile={progress_tile}" if progress_tile else ""
    print(
        f"[eta] done elapsed {fmt_duration(actual)} "
        f"pred {fmt_duration(predicted_dynamic)} err {error_pct:4.1f}%"
        f"{done_task}{done_tile}",
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
            "variant": args.variant,
            "max_steps": args.max_steps,
            "kerr_substeps": args.kerr_substeps if args.metric.lower() == "kerr" else 1,
            "spectral_step": args.spectral_step,
            "work": work,
            "spw": spw,
            "predicted": predicted_dynamic,
            "duration": actual,
            "success": (proc.returncode == 0),
        }
    )
    save_history(history_path, history)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
