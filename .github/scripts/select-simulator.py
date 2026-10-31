import json
import os
import subprocess

def simctl(*args):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", *args, "--json"]))

runtimes = simctl("runtimes")["runtimes"]
eligible = {r["identifier"] for r in runtimes if r.get("isAvailable") and r["name"].startswith("iOS") and tuple(map(int, r["version"].split("."))) >= (26, 5)}
devices = simctl("devices", "available")["devices"]
for runtime in sorted(eligible, reverse=True):
    phones = [d for d in devices.get(runtime, []) if d["name"].startswith("iPhone")]
    if phones:
        with open(os.environ["GITHUB_ENV"], "a") as f:
            f.write("SIMULATOR_ID=" + phones[0]["udid"] + "\n")
        print("Using", runtime, phones[0]["name"])
        break
else:
    raise SystemExit("No available iOS >=26.5 iPhone simulator")
