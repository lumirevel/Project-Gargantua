#!/usr/bin/env python3
"""Fetch evolved 3D GRMHD snapshots from the Illinois public data products.

The downloaded files are real evolved primitive dumps, not synthetic perturbation
tests. Keep the generated provenance JSON with any images made from the data so
that render comparisons can be tied back to a concrete simulation dump.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urljoin
from urllib.request import Request, urlopen


DEFAULT_BASE_URL = "https://thz.astro.illinois.edu/"
API_PATH = "fetch_files_v3_grmhd.php"
CHUNK_SIZE = 1024 * 1024


def _read_url(url: str, *, timeout: float = 30.0) -> bytes:
    req = Request(url, headers={"User-Agent": "BlackholeRenderer/GRMHDFetcher"})
    try:
        with urlopen(req, timeout=timeout) as response:
            return response.read()
    except HTTPError as exc:
        raise SystemExit(f"HTTP {exc.code} while reading {url}") from exc
    except URLError as exc:
        raise SystemExit(f"Network error while reading {url}: {exc}") from exc


def _api_url(base_url: str, flux: str, spin: str) -> str:
    query = urlencode({"flux": flux, "spin": spin})
    return urljoin(base_url, API_PATH) + "?" + query


def fetch_catalog(base_url: str, flux: str, spin: str) -> List[Dict[str, Any]]:
    url = _api_url(base_url, flux, spin)
    payload = _read_url(url).decode("utf-8")
    try:
        data = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Catalog response was not JSON: {url}") from exc
    if not isinstance(data, list):
        raise SystemExit(f"Catalog response was not a list: {url}")
    return data


def _file_url(base_url: str, item: Dict[str, Any]) -> str:
    raw = str(item.get("path") or item.get("url") or item.get("href") or "")
    if not raw:
        raise SystemExit(f"Catalog item has no path/url field: {item}")
    return urljoin(base_url, raw.lstrip("/"))


def _item_name(item: Dict[str, Any], fallback_index: int) -> str:
    for key in ("name", "filename", "file"):
        if item.get(key):
            return Path(str(item[key])).name
    raw_path = str(item.get("path") or item.get("url") or "")
    if raw_path:
        return Path(raw_path).name
    return f"torus.out0.{fallback_index:05d}.h5"


def _select_item(
    catalog: List[Dict[str, Any]],
    *,
    index: Optional[int],
    dump: Optional[str],
) -> tuple[int, Dict[str, Any]]:
    if not catalog:
        raise SystemExit("Catalog is empty")
    if dump:
        for i, item in enumerate(catalog):
            name = _item_name(item, i)
            path = str(item.get("path") or "")
            if dump in name or dump in path:
                return i, item
        raise SystemExit(f"No catalog item matched dump substring: {dump}")
    selected = 0 if index is None else index
    if selected < 0 or selected >= len(catalog):
        raise SystemExit(f"--index {selected} out of range 0...{len(catalog) - 1}")
    return selected, catalog[selected]


def _select_items(
    catalog: List[Dict[str, Any]],
    *,
    index: Optional[int],
    start_index: Optional[int],
    dump: Optional[str],
    count: int,
) -> List[tuple[int, Dict[str, Any]]]:
    if count < 1:
        raise SystemExit("--count must be >= 1")
    first_index, _ = _select_item(
        catalog,
        index=start_index if start_index is not None else index,
        dump=dump,
    )
    end = first_index + count
    if end > len(catalog):
        raise SystemExit(f"requested range {first_index}...{end - 1} exceeds catalog size {len(catalog)}")
    return [(i, catalog[i]) for i in range(first_index, end)]


def download_file(url: str, out_path: Path, *, force: bool) -> int:
    if out_path.exists() and not force:
        return out_path.stat().st_size
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_suffix(out_path.suffix + ".part")
    req = Request(url, headers={"User-Agent": "BlackholeRenderer/GRMHDFetcher"})
    try:
        with urlopen(req, timeout=60.0) as response, tmp.open("wb") as fh:
            while True:
                chunk = response.read(CHUNK_SIZE)
                if not chunk:
                    break
                fh.write(chunk)
    except HTTPError as exc:
        raise SystemExit(f"HTTP {exc.code} while downloading {url}") from exc
    except URLError as exc:
        raise SystemExit(f"Network error while downloading {url}: {exc}") from exc
    tmp.replace(out_path)
    return out_path.stat().st_size


def write_provenance(
    out_path: Path,
    *,
    base_url: str,
    flux: str,
    spin: str,
    catalog_url: str,
    selected_index: int,
    selected_item: Dict[str, Any],
    file_url: str,
    size_bytes: int,
) -> Path:
    provenance = {
        "source": "Illinois Simulation Data Products v3 GRMHD",
        "sourceBaseURL": base_url,
        "catalogURL": catalog_url,
        "fileURL": file_url,
        "flux": flux,
        "spin": spin,
        "selectedIndex": selected_index,
        "selectedCatalogItem": selected_item,
        "localPath": str(out_path),
        "sizeBytes": size_bytes,
        "downloadedAtUnix": time.time(),
        "citationHint": "Use the citation requested by the Illinois v3 GRMHD data page for publications or public comparisons.",
    }
    provenance_path = out_path.with_suffix(out_path.suffix + ".provenance.json")
    provenance_path.write_text(json.dumps(provenance, indent=2, sort_keys=True), encoding="utf-8")
    return provenance_path


def write_sequence_manifest(
    manifest_path: Path,
    *,
    base_url: str,
    flux: str,
    spin: str,
    catalog_url: str,
    entries: List[Dict[str, Any]],
) -> Path:
    manifest = {
        "source": "Illinois Simulation Data Products v3 GRMHD",
        "sourceBaseURL": base_url,
        "catalogURL": catalog_url,
        "flux": flux,
        "spin": spin,
        "count": len(entries),
        "entries": entries,
        "createdAtUnix": time.time(),
        "citationHint": "Use the citation requested by the Illinois v3 GRMHD data page for publications or public comparisons.",
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
    return manifest_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--flux", choices=["SANE", "MAD"], default="SANE")
    parser.add_argument(
        "--spin",
        default="0",
        help="Spin selector used by the Illinois API, e.g. -0.94, -0.5, 0, +0.5, +0.94, or -0.94_new.",
    )
    parser.add_argument("--out-dir", type=Path, default=Path("/tmp/blackhole_real_grmhd"))
    parser.add_argument("--index", type=int, default=0, help="Catalog item index to download.")
    parser.add_argument("--start-index", type=int, default=None, help="First catalog item index for a consecutive download range.")
    parser.add_argument("--count", type=int, default=1, help="Number of consecutive catalog items to download.")
    parser.add_argument("--dump", default="", help="Substring match for a dump filename/path, e.g. 05000.")
    parser.add_argument("--list", action="store_true", help="List matching catalog entries instead of downloading.")
    parser.add_argument("--limit", type=int, default=12, help="Number of catalog rows to print with --list.")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    base_url = args.base_url.rstrip("/") + "/"
    catalog = fetch_catalog(base_url, args.flux, args.spin)
    catalog_url = _api_url(base_url, args.flux, args.spin)

    if args.list:
        print(f"catalog={catalog_url}")
        print(f"items={len(catalog)}")
        for i, item in enumerate(catalog[: max(args.limit, 0)]):
            name = _item_name(item, i)
            size = item.get("size") or item.get("filesize") or ""
            print(f"{i:04d} {name} {size} {_file_url(base_url, item)}")
        return 0

    selected_items = _select_items(
        catalog,
        index=args.index,
        start_index=args.start_index,
        dump=args.dump or None,
        count=args.count,
    )

    print(f"catalog={catalog_url}")
    print(f"items={len(catalog)}")
    for selected_index, selected_item in selected_items:
        url = _file_url(base_url, selected_item)
        name = _item_name(selected_item, selected_index)
        out_path = args.out_dir / f"{args.flux}_a{args.spin.replace('+', 'p').replace('-', 'm')}_{name}"
        print(f"selected={selected_index} {name}")
        print(f"url={url}")
        print(f"out={out_path}")
    if args.dry_run:
        return 0

    sequence_entries: List[Dict[str, Any]] = []
    for selected_index, selected_item in selected_items:
        url = _file_url(base_url, selected_item)
        name = _item_name(selected_item, selected_index)
        out_path = args.out_dir / f"{args.flux}_a{args.spin.replace('+', 'p').replace('-', 'm')}_{name}"
        size_bytes = download_file(url, out_path, force=args.force)
        provenance_path = write_provenance(
            out_path,
            base_url=base_url,
            flux=args.flux,
            spin=args.spin,
            catalog_url=catalog_url,
            selected_index=selected_index,
            selected_item=selected_item,
            file_url=url,
            size_bytes=size_bytes,
        )
        sequence_entries.append({
            "selectedIndex": selected_index,
            "name": name,
            "fileURL": url,
            "localPath": str(out_path),
            "provenancePath": str(provenance_path),
            "sizeBytes": size_bytes,
        })
        print(f"sizeBytes={size_bytes}")
        print(f"provenance={provenance_path}")

    if len(sequence_entries) > 1:
        first = sequence_entries[0]["selectedIndex"]
        last = sequence_entries[-1]["selectedIndex"]
        manifest_path = args.out_dir / f"{args.flux}_a{args.spin.replace('+', 'p').replace('-', 'm')}_sequence_{first:05d}_{last:05d}.manifest.json"
        write_sequence_manifest(
            manifest_path,
            base_url=base_url,
            flux=args.flux,
            spin=args.spin,
            catalog_url=catalog_url,
            entries=sequence_entries,
        )
        print(f"manifest={manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
