"""Integrity of the review agent's reusable reference package, not PHY qualification."""
from __future__ import annotations

import csv
import re
import tomllib
from pathlib import Path
from urllib.parse import urlparse

import yaml


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / ".agents/skills/threegpp-lls-review"


def test_agent_and_skill_are_loadable_without_session_overrides():
    agent = tomllib.loads((ROOT / ".codex/agents/threegpp_lls.toml").read_text())
    assert agent["name"] == "threegpp_lls"
    assert agent["description"] and agent["developer_instructions"]
    assert not {"model", "sandbox_mode", "approval_policy", "mcp_servers"} & agent.keys()
    text = (SKILL / "SKILL.md").read_text(encoding="utf-8")
    frontmatter = yaml.safe_load(text.split("---", 2)[1])
    assert frontmatter["name"] == SKILL.name and frontmatter["description"]
    ui = yaml.safe_load((SKILL / "agents/openai.yaml").read_text())
    assert "$" + SKILL.name in ui["interface"]["default_prompt"]
    assert 25 <= len(ui["interface"]["short_description"]) <= 64


def test_reference_links_and_repository_flow_owners_exist():
    text = (SKILL / "SKILL.md").read_text(encoding="utf-8")
    links = re.findall(r"\]\((references/[^)]+)\)", text)
    assert links
    for link in links:
        assert (SKILL / link).is_file(), link
    flow = (SKILL / "references/execution-review.md").read_text(encoding="utf-8")
    # Fully qualified repository paths, including directories. Local shorthand
    # function names in a row inherit that row's directory and aren't paths.
    paths = re.findall(r"`((?:\+sixgr/|apps/|simulator/)[^`]+)`", flow)
    assert len(paths) >= 30
    for path in paths:
        if "*" in path:
            assert list(ROOT.glob(path)), path
        else:
            assert (ROOT / path).exists(), path
    assert (ROOT / "docs/lls/ran1_126_100mhz_output_requirements.csv").is_file()
    assert (ROOT / "docs/lls/ran1_126_100mhz_output_requirements_source.json").is_file()


def test_standard_index_has_source_version_rules_and_no_final_6g_claim():
    with (SKILL / "references/standards.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    assert rows and len({r["Reference"] for r in rows}) == len(rows)
    required = {"TS 38.211", "TS 38.212", "TS 38.213", "TS 38.214", "TS 38.215",
                "TS 38.306", "TS 38.321", "TS 38.322", "TS 38.323", "TS 38.331", "TR 38.901"}
    assert required <= {r["Reference"] for r in rows}
    for row in rows:
        assert None not in row and all(row.values()), row
        url = urlparse(row["LookupURL"])
        assert url.scheme == "https" and url.hostname in {"www.etsi.org", "portal.3gpp.org"}
        assert row["Classification"] in {"NR_NORMATIVE", "3GPP_MODEL_OR_METHOD", "STUDY_CANDIDATE"}
        assert row["VersionPolicy"].strip()
        if row["Domain"].startswith("6G"):
            assert row["Classification"] != "NR_NORMATIVE"
