import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("package_cli", Path(__file__).parents[2] / "scripts/package_cli.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

class PackageCLITests(unittest.TestCase):
    def test_package_includes_resources_and_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary_dir = root / "bin"
            binary_dir.mkdir()
            binary = binary_dir / "feature-passport"
            binary.write_bytes(b"executable")
            binary.chmod(0o755)
            resources = binary_dir / "FeaturePassport_FeaturePassport.bundle"
            resources.mkdir()
            (resources / "schema.json").write_text("{}")
            archive, manifest = module.assemble(binary_dir, root / "output", "0.1.0", "arm64-apple-macosx", "a" * 40, {"commands": ["issue-receipt"]}, "swift-test", "host-runtime")
            result = json.loads(manifest.read_text())
            self.assertEqual(result["source_commit"], "a" * 40)
            self.assertEqual(len(result["files"]), 2)
            self.assertIn("FeaturePassport_FeaturePassport.bundle/schema.json", {item["path"] for item in result["files"]})
            self.assertEqual(result["archive_sha256"], module.sha256(archive))
            with self.assertRaises(FileExistsError):
                module.assemble(binary_dir, root / "output", "0.1.0", "arm64-apple-macosx", "a" * 40, {}, "swift-test", "host-runtime")

    def test_missing_resource_bundle_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "feature-passport").write_bytes(b"binary")
            with self.assertRaises(ValueError):
                module.assemble(root, root / "output", "0.1.0", "x86_64-unknown-linux-gnu", "a" * 40, {}, "swift-test", "host-runtime")

    def test_build_resource_fallback_is_disabled_and_restored(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary_dir = root / "bin"
            binary_dir.mkdir()
            resource = binary_dir / "FP.resources"
            resource.mkdir()
            (resource / "schema.json").write_text("{}")
            with self.assertRaises(RuntimeError):
                with module.original_resources_unavailable(binary_dir):
                    self.assertFalse(resource.exists())
                    raise RuntimeError("smoke failed")
            self.assertEqual((resource / "schema.json").read_text(), "{}")

    def test_symlinked_resource_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "feature-passport").write_bytes(b"binary")
            resources = root / "FP.bundle"
            resources.mkdir()
            (resources / "link").symlink_to(root / "feature-passport")
            with self.assertRaises(ValueError):
                module.assemble(root, root / "output", "0.1.0", "arm64-apple-macosx", "a" * 40, {}, "swift-test", "host-runtime")

if __name__ == "__main__":
    unittest.main()
