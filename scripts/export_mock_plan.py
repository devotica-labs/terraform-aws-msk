"""Export the secure_defaults Terraform mock plan for policy checks; never call real plan/apply."""
import json
import os
from pathlib import Path
import subprocess

result = subprocess.run(
    ["terraform", "test", "-filter=" + os.path.normpath("tests/unit.tftest.hcl"), "-json", "-verbose", "-no-color"],
    capture_output=True, text=True, encoding="utf-8", errors="replace",
)
if result.returncode:
    print(result.stdout)
    print(result.stderr)
    raise SystemExit(result.returncode)
plans = []
for line in result.stdout.splitlines():
    event = json.loads(line)
    if event.get("type") == "test_plan" and event.get("@testrun") == "secure_defaults":
        plans.append(event["test_plan"])
if len(plans) != 1 or not plans[0].get("resource_changes"):
    raise SystemExit("Expected one non-empty secure_defaults plan; refusing a vacuous policy pass.")
Path("reports").mkdir(exist_ok=True)
Path("reports/mock-plan.json").write_text(json.dumps(plans[0], indent=2), encoding="utf-8")
print("Exported mock resource changes; no AWS credentials or resources used.")
