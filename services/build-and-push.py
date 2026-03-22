#!/usr/bin/env python3
"""Build and push Docker images to ECR, skipping services whose files haven't changed."""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

SCRIPT_DIR = Path(__file__).parent.resolve()
STATE_FILE = SCRIPT_DIR / ".build-state"
VALUES_FILE = SCRIPT_DIR.parent / "k8s" / "microservices" / "values.yaml"
SEP = "=" * 50


def load_config() -> dict:
    config_file = SCRIPT_DIR / ".env"
    if not config_file.exists():
        print(f"Error: config file not found at {config_file}")
        print("Please create it with: AWS_ACCOUNT_ID, AWS_REGION, ENVIRONMENT")
        print("Optional: AWS_PROFILE, HF_TOKEN")
        sys.exit(1)

    cfg = {}
    for line in config_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, val = line.partition("=")
            cfg[key.strip()] = val.strip()

    for required in ("AWS_ACCOUNT_ID", "AWS_REGION", "ENVIRONMENT"):
        if not cfg.get(required):
            print(f"Error: {required} is missing from .env")
            sys.exit(1)

    return cfg


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def save_state(state: dict) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2))


def dir_hash(path: Path) -> str:
    """SHA-256 of every file under path, stable across runs."""
    h = hashlib.sha256()
    for file in sorted(path.rglob("*")):
        if file.is_file():
            h.update(str(file.relative_to(path)).encode())
            h.update(file.read_bytes())
    return h.hexdigest()


def run(cmd: List[str], env: Optional[Dict] = None, check: bool = True) -> int:
    merged = {**os.environ, **(env or {})}
    result = subprocess.run(cmd, env=merged)
    if check and result.returncode != 0:
        print(f"Error: command failed: {' '.join(cmd)}")
        sys.exit(result.returncode)
    return result.returncode


def run_output(cmd: List[str], env: Optional[Dict] = None) -> str:
    merged = {**os.environ, **(env or {})}
    return subprocess.check_output(cmd, env=merged).decode().strip()


def update_tag(service: str, tag: str) -> None:
    lines = VALUES_FILE.read_text().splitlines(keepends=True)
    in_service = False
    updated = []
    replaced = False
    for line in lines:
        if re.match(rf"^  {re.escape(service)}\s*:", line):
            in_service = True
        elif in_service and re.match(r"^  \S", line):
            in_service = False
        if in_service and re.match(r"^\s+tag:\s+'[^']*'", line):
            line = re.sub(r"(tag:\s+')[^']*(')", rf"\g<1>{tag}\g<2>", line)
            replaced = True
            in_service = False
        updated.append(line)
    if replaced:
        VALUES_FILE.write_text("".join(updated))
        print(f"  ✓ Updated {service} tag → {tag}")
    else:
        print(f"  ⚠  Could not find tag entry for {service} in values.yaml")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="Rebuild all services regardless of changes")
    parser.add_argument("services", nargs="*", help="Only build these services (default: all)")
    args = parser.parse_args()

    cfg = load_config()
    state = load_state()

    aws_profile = cfg.get("AWS_PROFILE")
    hf_token = cfg.get("HF_TOKEN", "")
    ecr_registry = f"{cfg['AWS_ACCOUNT_ID']}.dkr.ecr.{cfg['AWS_REGION']}.amazonaws.com"
    tag = datetime.utcnow().strftime("%Y%m%d%H%M%S")

    aws_base = ["aws", "--region", cfg["AWS_REGION"]]
    if aws_profile:
        aws_base += ["--profile", aws_profile]
        print(f"Using AWS profile: {aws_profile}")

    print("Logging in to ECR...")
    password = run_output(aws_base + ["ecr", "get-login-password"])
    proc = subprocess.run(
        ["docker", "login", "--username", "AWS", "--password-stdin", ecr_registry],
        input=password.encode(), capture_output=True,
    )
    if proc.returncode == 0:
        print("✓ Logged in to ECR")
    else:
        print("⚠  ECR login may have failed — proceeding anyway")

    print("Setting up Docker buildx...")
    subprocess.run(
        ["docker", "buildx", "create", "--use", "--name", "multiarch-builder", "--driver", "docker-container"],
        capture_output=True,
    )
    subprocess.run(["docker", "buildx", "use", "multiarch-builder"], capture_output=True)
    run(["docker", "buildx", "inspect", "--bootstrap"])

    print(f"\n{SEP}")
    print(f"Registry : {ecr_registry}")
    print(f"Tag      : {tag}")
    print(f"{SEP}\n")

    service_dirs = sorted(
        d for d in SCRIPT_DIR.iterdir()
        if d.is_dir() and (d / "Dockerfile").exists()
    )

    if args.services:
        service_dirs = [d for d in service_dirs if d.name in args.services]

    built = []
    skipped = []

    for service_dir in service_dirs:
        name = service_dir.name
        print(f"{SEP}")
        print(f"Service: {name}")

        current_hash = dir_hash(service_dir)
        stored_hash = state.get(name)

        if not args.force and current_hash == stored_hash:
            print(f"  ⏭  No changes detected — skipping")
            skipped.append(name)
            continue

        image = f"{ecr_registry}/{cfg['ENVIRONMENT']}/{name}"

        build_cmd = [
            "docker", "buildx", "build",
            "--platform", "linux/amd64",
            "--tag", f"{image}:{tag}",
            "--push",
        ]

        if name == "personaplex" and hf_token:
            build_cmd += ["--secret", "id=hf_token,env=HF_TOKEN"]

        build_cmd.append(str(service_dir))

        run(build_cmd, env={"HF_TOKEN": hf_token} if hf_token else None)
        print(f"  ✓ Built and pushed {image}:{tag}")

        update_tag(name, tag)

        state[name] = current_hash
        save_state(state)

        built.append(name)

    print(f"\n{SEP}")
    if built:
        print(f"Built    ({len(built)}): {', '.join(built)}")
    if skipped:
        print(f"Skipped  ({len(skipped)}): {', '.join(skipped)}")
    if not built:
        print("Nothing to build — all services up to date. Use --force to rebuild.")
    print(f"{SEP}")


if __name__ == "__main__":
    main()
