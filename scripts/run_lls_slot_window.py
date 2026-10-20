"""Run the unchanged production scenario on the server, then audit its window.

No new physical state is manufactured at first_slot. The normal runner executes
initial access and all earlier slots. Use the existing reviewed checkpoint
workflow for continuation; this fresh-launch wrapper never rewinds a run.
"""
import argparse
import hashlib
import json
import sys

from audit_lls_slot_window import audit, load_plan
import run_server_lls as server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--matlab", required=True)
    parser.add_argument("--results", default="results")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--plan", action="store_true", help="No MATLAB execution or output writes")
    args = parser.parse_args()
    config = (server.ROOT / args.config).resolve(strict=True)
    config.relative_to(server.ROOT)
    plan = load_plan(config)
    plan_hash = hashlib.sha256(config.read_bytes()).hexdigest()
    # Keep all existing frozen-source, environment and no-overwrite guards.
    launch = argparse.Namespace(matlab=args.matlab, scenario=plan["scenario_config"],
                                results=args.results, tag=args.tag, plan=args.plan)
    code = server.execute(launch)
    if hashlib.sha256(config.read_bytes()).hexdigest() != plan_hash:
        raise ValueError("Validation policy changed during execution; do not audit with different gates")
    if args.plan:
        print(json.dumps(dict(Window=[plan["first_slot"], plan["last_slot"]],
                              AdaptationLastSlot=plan["adaptation_last_slot"],
                              PhysicalHorizon=plan["expected_horizon"],
                              FreshInitialAccess=True, NoForcedRankOrFeedback=True)))
        return code
    root = (server.ROOT / args.results / "lls" / plan["scenario_id"] / args.tag).resolve()
    if not root.is_dir():
        print("No run folder; no physical window evidence exists.", file=sys.stderr)
        return 1
    # Audit even when scenario acceptance failed. Keep the original error;
    # a passing sub-window cannot turn a failed scenario into a pass.
    receipt = audit(config, root)
    print(json.dumps(receipt, indent=2))
    return 0 if code == 0 and receipt["AllChecksPassed"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as error:
        print(f"Slot-window validation not accepted: {error}", file=sys.stderr)
        raise SystemExit(2)
