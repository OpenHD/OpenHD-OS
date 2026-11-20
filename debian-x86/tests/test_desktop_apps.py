import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("desktop_apps", pathlib.Path(__file__).parents[1] / "desktop-apps.py")
apps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apps)


class DesktopReleases(unittest.TestCase):
    def release(self, **changes):
        release = {"draft": False, "prerelease": False, "tag_name": "v2.0", "html_url": "https://github.com/example/project/releases/tag/v2.0",
                   "assets": [{"name": "app-amd64.deb", "browser_download_url": "https://github.com/example/project/releases/download/v2.0/app-amd64.deb", "size": 3, "digest": None}]}
        release.update(changes)
        return io.BytesIO(json.dumps(release).encode())

    def catalog(self):
        return [{"id": "test", "repo": "example/project", "asset": r"^app-amd64\.deb$", "format": "deb"}]

    def test_ambiguous_or_missing_architecture_asset_fails(self):
        with patch.object(apps.urllib.request, "urlopen", return_value=self.release(assets=[])):
            with self.assertRaisesRegex(RuntimeError, "Expected one amd64"):
                apps.resolve(self.catalog())

    def test_prerelease_is_not_a_stable_update(self):
        with patch.object(apps.urllib.request, "urlopen", return_value=self.release(prerelease=True)):
            with self.assertRaisesRegex(RuntimeError, "stable release"):
                apps.resolve(self.catalog())

    def test_foreign_download_location_is_rejected(self):
        release = json.loads(self.release().read())
        release["assets"][0]["browser_download_url"] = "https://example.org/app-amd64.deb"
        with patch.object(apps.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(release).encode())):
            with self.assertRaisesRegex(RuntimeError, "Unexpected release download"):
                apps.resolve(self.catalog())

    def test_checksum_failure_does_not_promote_cache_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            entry = {"id": "test", "url": "https://github.com/example/project/releases/download/v2.0/app-amd64.deb", "format": "deb", "size": 3, "upstream_digest": "sha256:" + "0" * 64}
            with patch.object(apps.urllib.request, "urlopen", side_effect=lambda *a, **k: io.BytesIO(b"bad")), patch.object(apps.time, "sleep"):
                with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                    apps.download(entry, pathlib.Path(directory))
            self.assertEqual(list(pathlib.Path(directory).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
