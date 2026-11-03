"""Check that deep inductive signatures decline instead of overflowing the stack.

Run after scripts/build.sh: python3 tests/infer_depth.py ./lean_checker
Inputs are generated so the regression does not add large NDJSON fixtures.
"""

import json
from pathlib import Path
import resource
import subprocess
import sys
import tempfile


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (8 * 1024**3, 8 * 1024**3))
    resource.setrlimit(resource.RLIMIT_STACK, (8 * 1024**2, 8 * 1024**2))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def signature(constructor):
    count = 30000
    records = [
        {"in": 1, "str": {"pre": 0, "str": "A"}},
        {"in": 2, "str": {"pre": 0, "str": "x"}},
        {"in": 3, "str": {"pre": 1, "str": "mk"}},
        {"ie": 0, "sort": 0},
    ]
    tail = 0
    if constructor:
        records.append({"ie": 1, "const": {"name": 1, "us": []}})
        tail = 1
    for _ in range(count):
        records.append({"ie": tail + 1, "forallE": {
            "binderInfo": "default", "name": 2, "type": 0, "body": tail,
        }})
        tail += 1
    types = [{
        "all": [1], "ctors": [3] if constructor else [], "isRec": False,
        "isReflexive": False, "isUnsafe": False, "levelParams": [], "name": 1,
        "numIndices": 0 if constructor else count, "numNested": 0,
        "numParams": 0, "type": 0 if constructor else tail,
    }]
    ctors = [{
        "cidx": 0, "induct": 1, "isUnsafe": False, "levelParams": [],
        "name": 3, "numFields": count, "numParams": 0, "type": tail,
    }] if constructor else []
    records.append({"inductive": {"types": types, "ctors": ctors, "recs": []}})
    return "".join(json.dumps(record, separators=(",", ":")) + "\n" for record in records)


def main():
    checker = str(Path(sys.argv[1] if len(sys.argv) > 1 else "./lean_checker").resolve())
    with tempfile.TemporaryDirectory(prefix="infer-depth-") as tmp:
        for constructor in [False, True]:
            data = signature(constructor)
            path = Path(tmp) / "input.ndjson"
            path.write_text(data)
            label = "constructor" if constructor else "inductive"
            for mode in ["file", "stdin"]:
                result = subprocess.run(
                    [checker, str(path)] if mode == "file" else [checker],
                    input=data if mode == "stdin" else None,
                    text=True, capture_output=True, preexec_fn=limits, timeout=30,
                )
                if result.returncode != 2:
                    raise AssertionError(
                        f"{label}/{mode}: expected decline/2, got {result.returncode}\n"
                        f"{result.stdout}\n{result.stderr}"
                    )
                print(f"PASS {label}/{mode}: graceful decline")


if __name__ == "__main__":
    main()
