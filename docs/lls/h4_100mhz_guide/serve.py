"""Read-only, loopback-only guide and allow-listed source viewer. No MATLAB launch."""
from __future__ import annotations
import argparse
import hashlib
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import yaml

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
STATIC = {"/": ("index.html", "text/html"), "/index.html": ("index.html", "text/html"),
          "/guide.css": ("guide.css", "text/css"), "/guide.js": ("guide.js", "text/javascript"),
          "/chapters.js": ("chapters.js", "text/javascript")}
ALLOWED = {"+sixgr", "simulator", "tests", "docs"}
TOP = {"run_6g_phy_lls_single.m", "run_6g_phy_lls_matrix.m", "run_sixgr.m",
       "setup6GRSimToolkit.m", "README.md"}


def source_path(value: str) -> Path:
    relative = Path(value.replace("\\", "/"))
    if relative.is_absolute() or not relative.parts or ":" in value or ".." in relative.parts:
        raise ValueError("Only relative repository source paths are allowed")
    path = (ROOT / relative).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError("Path outside the repository")
    resolved = path.relative_to(ROOT)
    if resolved.parts[0] not in ALLOWED and resolved.as_posix() not in TOP:
        raise ValueError("Path outside the source allow-list")
    if path.suffix.lower() not in {".m", ".yaml", ".yml", ".md", ".py", ".csv"}:
        raise ValueError("Not a permitted source type")
    if not path.is_file():
        raise FileNotFoundError(value)
    if path.stat().st_size > 15 * 1024 * 1024:
        raise ValueError("Source file exceeds the viewer limit")
    return path


def source_payload(value: str) -> dict:
    path = source_path(value)
    data = path.read_bytes()
    return {"path": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(data).hexdigest(),
            "text": data.decode("utf-8-sig"), "scope": "current_main_working_tree_not_executed_result"}


def reference_payload() -> dict:
    # Generated with the repository's actual MATLAB ScenarioConfig builder.
    # It is documentation data, not a second YAML resolver or launch config.
    path = HERE / "reference.json"
    if not path.is_file():
        return {"available": False, "reason": "Run the documented snapshot command; no defaults substituted."}
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    changed = []
    for item in value.get("sources", []):
        try:
            actual = hashlib.sha256(source_path(item["path"]).read_bytes()).hexdigest()
        except (ValueError, FileNotFoundError):
            actual = None
        if actual != item["sha256"]:
            changed.append(item["path"])
    value["available"] = True
    value["source_changes_since_snapshot"] = changed
    value["snapshot_matches_yaml"] = not changed
    return value


def catalog_payload(kind: str) -> dict:
    if kind == "core":
        # This is the single file read by loadCoreCatalog.m, not an alternative
        # native config resolver. Expose declared rules; do not apply defaults,
        # inheritance, normalization or cross-field validation in the guide.
        path = "simulator/configs/schema/core_parameter_catalog.yaml"
        raw = source_path(path).read_bytes()
        catalog = yaml.safe_load(raw)
        if not isinstance(catalog, dict) or not isinstance(catalog.get("parameters"), dict):
            raise ValueError("Native core catalog has no parameter mapping")
        sources = [path, "+sixgr/+config/loadCoreCatalog.m"]
        return {"catalog": catalog, "metadata": {
                    "scope": "live_native_catalog_declared_options_not_runtime_qualification",
                    "sources": [{"path": p, "sha256": hashlib.sha256(source_path(p).read_bytes()).hexdigest()}
                                for p in sources]},
                "changed_sources": [], "snapshot_matches_sources": True,
                "read_mode": "live_source_not_resolved_config"}
    if kind not in {"scenario", "matrix"}:
        raise ValueError("Catalog must be scenario, matrix or core")
    filename = "parameter-catalog.json" if kind == "scenario" else "matrix-catalog.json"
    value = json.loads((HERE / filename).read_text(encoding="utf-8-sig"))
    metadata_path = HERE / "catalog-provenance.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8-sig")) if metadata_path.exists() else {}
    changed = []
    for item in metadata.get("sources", []):
        try:
            digest = hashlib.sha256(source_path(item["path"]).read_bytes()).hexdigest()
        except (FileNotFoundError, ValueError):
            digest = None
        if digest != item["sha256"]:
            changed.append(item["path"])
    return {"catalog": value, "metadata": metadata, "changed_sources": changed,
            "snapshot_matches_sources": bool(metadata) and not changed}


def scenario_payload() -> dict:
    """Inventory only. Never implement a competing inheritance/validation engine."""
    entries = []
    for path in sorted((ROOT / "simulator" / "configs").rglob("*")):
        if path.suffix.lower() not in {".yaml", ".yml"} or not path.is_file():
            continue
        relative = path.relative_to(ROOT).as_posix()
        item = {"path": relative, "category": path.relative_to(ROOT / "simulator" / "configs").parts[0],
                "acceptance": "not_assessed_by_this_inventory"}
        try:
            # Apply the same source allow-list, including symlink resolution.
            data = source_path(relative).read_bytes()
            obj = yaml.safe_load(data) or {}
            item.update(sha256=hashlib.sha256(data).hexdigest())
            if isinstance(obj, dict):
                item.update(meta=obj.get("meta", {}), inherits=obj.get("inherits", []),
                            leaf_sections=list(map(str, obj.keys())))
            else:
                item["note"] = "Non-mapping YAML; inspect source before choosing a launcher."
        except (ValueError, OSError, yaml.YAMLError) as exc:
            item["error"] = str(exc)
        entries.append(item)
    return {"scope": "current_yaml_inventory_not_execution_qualification", "entries": entries}


class Handler(BaseHTTPRequestHandler):
    def send_bytes(self, status: int, data: bytes, kind: str):
        self.send_response(status)
        self.send_header("Content-Type", kind + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        host = self.headers.get("Host", "").split(":")[0].lower()
        if host not in {"127.0.0.1", "localhost"}:
            return self.send_bytes(403, b"Loopback host required", "text/plain")
        parsed = urlparse(self.path)
        try:
            if parsed.path in STATIC:
                name, kind = STATIC[parsed.path]
                return self.send_bytes(200, (HERE / name).read_bytes(), kind)
            if parsed.path in {"/api/source", "/raw"}:
                value = parse_qs(parsed.query).get("path", [""])[0]
                if parsed.path == "/raw":
                    return self.send_bytes(200, source_path(value).read_bytes(), "text/plain")
                payload = source_payload(value)
            elif parsed.path == "/api/reference":
                payload = reference_payload()
            elif parsed.path == "/api/catalog":
                payload = catalog_payload(parse_qs(parsed.query).get("kind", ["scenario"])[0])
            elif parsed.path == "/api/scenarios":
                payload = scenario_payload()
            else:
                return self.send_bytes(404, b"Not found", "text/plain")
            self.send_bytes(200, json.dumps(payload, ensure_ascii=False).encode(), "application/json")
        except (ValueError, UnicodeError) as exc:
            self.send_bytes(400, str(exc).encode(), "text/plain")
        except FileNotFoundError:
            self.send_bytes(404, b"Source not present in this checkout", "text/plain")

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=62907)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"SixGR documentation: http://127.0.0.1:{server.server_port}/", flush=True)
    print(f"Read-only source root: {ROOT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
