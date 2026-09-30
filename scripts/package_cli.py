#!/usr/bin/env python3
"""Build and smoke-check a native CLI archive; no authority keys or deployment."""
import argparse
from contextlib import contextmanager
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assemble(binary_dir, output, version, target, source_commit, capabilities, toolchain, runtime, notices=None):
    if output.exists():
        raise FileExistsError(output)
    binary = binary_dir / "feature-passport"
    resources = sorted([*binary_dir.glob("*.bundle"), *binary_dir.glob("*.resources")])
    if not binary.is_file() or binary.is_symlink() or not resources:
        raise ValueError("Executable and SwiftPM resource bundle are required")
    assets = [binary, *resources, *sorted(binary_dir.glob("*.dylib")), *sorted(binary_dir.glob("*.so")), *sorted(binary_dir.glob("*.so.*"))]
    for asset in assets:
        entries = [asset, *asset.rglob("*")] if asset.is_dir() else [asset]
        if any(path.is_symlink() for path in entries):
            raise ValueError("Release assets must not contain symlinks")
    output.mkdir(parents=True)
    name = f"feature-passport-{version}-{target}"
    with tempfile.TemporaryDirectory() as directory:
        stage = Path(directory) / name
        stage.mkdir()
        for asset in assets:
            if asset.is_dir():
                shutil.copytree(asset, stage / asset.name)
            else:
                shutil.copy2(asset, stage / asset.name)
        for notice_name, content in (notices or {}).items():
            notice = stage / "licenses" / notice_name
            notice.parent.mkdir(parents=True, exist_ok=True)
            notice.write_bytes(content)
        files = [{"path": path.relative_to(stage).as_posix(), "sha256": sha256(path), "size": path.stat().st_size}
                 for path in sorted(stage.rglob("*")) if path.is_file()]
        archive = output / f"{name}.tar.gz"
        with archive.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", mtime=0, filename="") as zipped:
            with tarfile.open(fileobj=zipped, mode="w") as tar:
                for path in [stage, *sorted(stage.rglob("*"))]:
                    info = tar.gettarinfo(str(path), arcname=path.relative_to(stage.parent).as_posix())
                    info.uid = info.gid = info.mtime = 0
                    info.uname = info.gname = ""
                    if path.is_file():
                        with path.open("rb") as content:
                            tar.addfile(info, content)
                    else:
                        tar.addfile(info)
    manifest = output / f"{name}.manifest.json"
    manifest.write_text(json.dumps({
        "artifact_kind": "feature_passport_cli_release", "schema_version": 1,
        "version": version, "source_commit": source_commit, "target_triple": target,
        "archive": archive.name, "archive_sha256": sha256(archive), "files": files,
        "capabilities": capabilities, "toolchain": toolchain,
        "runtime_requirements": runtime,
        "license_notice_files": sorted((notices or {}).keys()),
        "authority_configuration_included": False,
        "build_attestation": "not_issued_by_packager",
    }, indent=2, sort_keys=True) + "\n")
    (output / f"{name}.sha256").write_text(f"{sha256(archive)}  {archive.name}\n{sha256(manifest)}  {manifest.name}\n")
    return archive, manifest


@contextmanager
def original_resources_unavailable(binary_dir):
    """Prevent SwiftPM absolute build-path fallback from masking missing assets."""
    resources = sorted([*binary_dir.glob("*.bundle"), *binary_dir.glob("*.resources")])
    hidden = Path(tempfile.mkdtemp(prefix="fp-resource-smoke-", dir=binary_dir.parent))
    moved = []
    try:
        for resource in resources:
            destination = hidden / resource.name
            resource.rename(destination)
            moved.append((resource, destination))
        yield
    finally:
        # Preserve originals even if another writer unexpectedly appeared.
        for resource, destination in moved:
            if resource.exists():
                raise RuntimeError(f"Original resource restoration blocked; preserved in {hidden}")
            destination.rename(resource)
        hidden.rmdir()


def run(*arguments, cwd=None):
    return subprocess.check_output(arguments, cwd=cwd, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scratch-path", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?", args.version):
        parser.error("version must be a bounded SemVer-shaped release identifier")
    if len(args.version) > 64:
        parser.error("version is too long")
    root = Path(__file__).resolve().parents[1]
    source = run("git", "rev-parse", "HEAD", cwd=root)
    dirty = run("git", "status", "--porcelain", "--untracked-files=all", cwd=root)
    if dirty:
        parser.error("release capture requires a clean committed checkout: " + dirty)
    options = ["--configuration", "release", "--disable-automatic-resolution"]
    if args.scratch_path:
        options += ["--scratch-path", str(args.scratch_path.resolve())]
    subprocess.run(["swift", "build", *options, "--product", "feature-passport"], cwd=root, check=True)
    binary_dir = Path(run("swift", "build", *options, "--show-bin-path", cwd=root))
    capabilities = json.loads(run(str(binary_dir / "feature-passport"), "capabilities"))
    if capabilities.get("receipt_issuance_profile") != "exact_contract_match_v1" or "issue-receipt" not in capabilities.get("commands", []):
        raise ValueError("Selected CLI lacks required issuer capability")
    host = platform.system()
    machine = platform.machine()
    targets = {("Darwin", "arm64"): "arm64-apple-macosx", ("Darwin", "x86_64"): "x86_64-apple-macosx",
               ("Linux", "x86_64"): "x86_64-unknown-linux-gnu", ("Linux", "aarch64"): "aarch64-unknown-linux-gnu"}
    target = targets.get((host, machine))
    if target is None:
        raise ValueError("Unsupported native release target")
    scratch = args.scratch_path.resolve() if args.scratch_path else root / ".build"
    notices = {}
    for checkout in sorted((scratch / "checkouts").glob("*")):
        for pattern in ("LICENSE*", "NOTICE*", "COPYING*"):
            for notice in sorted(checkout.rglob(pattern)):
                if notice.is_file() and not notice.is_symlink() and ".git" not in notice.parts:
                    notices[f"{checkout.name}/{notice.relative_to(checkout).as_posix()}"] = notice.read_bytes()
    for pattern in ("LICENSE*", "NOTICE*", "COPYING*"):
        for notice in root.glob(pattern):
            if notice.is_file() and not notice.is_symlink():
                notices[f"FeaturePassport/{notice.name}"] = notice.read_bytes()
    if not notices:
        raise ValueError("Dependency license notices unavailable")
    archive, manifest = assemble(binary_dir, args.output.resolve(), args.version, target, source, capabilities,
                                 run("swift", "--version"), {"host_os": host, "host_release": platform.release(),
                                 "swift_runtime": "matching build toolchain runtime required; no portable/static runtime claim",
                                 "system_dependencies": "native host-compatible libraries required; Platform must validate its runner"}, notices)
    # Exercise only archived bytes, including schema loading, from a fresh layout.
    with original_resources_unavailable(binary_dir), tempfile.TemporaryDirectory() as directory:
        with tarfile.open(archive) as tar:
            for member in tar.getmembers():
                path = Path(member.name)
                if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                    raise ValueError("Unsafe archive entry")
            tar.extractall(directory)
        extracted = Path(directory) / archive.name.removesuffix(".tar.gz")
        cli = extracted / "feature-passport"
        run(str(cli), "--help")
        if json.loads(run(str(cli), "capabilities")) != capabilities:
            raise ValueError("Archived CLI capabilities differ")
        run(str(cli), "validate", str(root / "examples/local-passport.json"))
        declared = json.loads(manifest.read_text())
        for item in declared["files"]:
            if sha256(extracted / item["path"]) != item["sha256"]:
                raise ValueError("Archived asset digest mismatch")
    if source != run("git", "rev-parse", "HEAD", cwd=root) or run("git", "status", "--porcelain", "--untracked-files=all", cwd=root):
        raise ValueError("Source changed during release capture")
    print(manifest)


if __name__ == "__main__":
    main()
