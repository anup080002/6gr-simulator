from __future__ import annotations

import subprocess
import sys
import textwrap
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def test_dashboard_imports_without_mysql_connector() -> None:
    code = textwrap.dedent(
        r"""
        import importlib.abc
        import sys

        class BlockMysql(importlib.abc.MetaPathFinder):
            def find_spec(self, fullname, path=None, target=None):
                if fullname == "mysql" or fullname.startswith("mysql."):
                    raise ImportError("blocked mysql import for regression test")
                return None

        sys.meta_path.insert(0, BlockMysql())
        sys.path.insert(0, r"apps")
        import lls_web_dashboard as dash

        ok, reason = dash.mysql_dependency_available()
        assert ok is False
        assert "blocked mysql import" in reason

        ok, reason = dash.dashboard_mysql_available()
        assert ok is False
        assert "MySQL persistence is unavailable" in reason
        """
    )

    proc = subprocess.run(
        [sys.executable, "-c", code],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr + proc.stdout
