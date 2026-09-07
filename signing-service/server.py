import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import zipfile
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

app = FastAPI(title="Dual IPA Authorized Signing Service")
ROOT = Path(os.environ.get("CERTS_ROOT", "./certs")).resolve()
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "").rstrip("/")
API_TOKEN = os.environ.get("SIGNING_API_TOKEN", "")

# Map exact certificate display names to administrator-created local aliases.
# Private keys and provisioning profiles remain on the signing server.
CERTIFICATE_MAP = json.loads(os.environ.get("CERTIFICATE_MAP", "{}"))


def run(*args: str) -> str:
    result = subprocess.run(args, check=False, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Signing command failed")
    return result.stdout


def require_token(token: str | None) -> None:
    if not API_TOKEN or token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")


def find_app(payload: Path) -> Path:
    candidates = list((payload / "Payload").glob("*.app"))
    if len(candidates) != 1:
        raise RuntimeError("IPA must contain exactly one Payload/*.app")
    return candidates[0]


def profile_entitlements(profile: Path, output: Path) -> None:
    decoded = subprocess.check_output(["security", "cms", "-D", "-i", str(profile)])
    plist = plistlib.loads(decoded)
    entitlements = plist.get("Entitlements", {})
    output.write_bytes(plistlib.dumps(entitlements, fmt=plistlib.FMT_XML, sort_keys=False))


def install_identity(p12: Path, password: str, keychain: Path) -> str:
    run("security", "create-keychain", "-p", password, str(keychain))
    run("security", "set-keychain-settings", str(keychain))
    run("security", "unlock-keychain", "-p", password, str(keychain))
    run("security", "import", str(p12), "-k", str(keychain), "-P", password, "-T", "/usr/bin/codesign")
    run("security", "list-keychains", "-d", "user", "-s", str(keychain))
    identities = run("security", "find-identity", "-v", "-p", "codesigning", str(keychain))
    for line in identities.splitlines():
        if '"' in line:
            return line.split('"', 2)[1]
    raise RuntimeError("No code-signing identity was found in the configured P12")


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/certificates")
def certificates(authorization: str | None = None):
    """Return only certificate display names configured by the service operator."""
    require_token(authorization or None)
    return {"certificates": list(CERTIFICATE_MAP.keys())}


@app.post("/sign")
async def sign(
    ipa: UploadFile = File(...),
    certificate: str = Form(...),
    authorization: str | None = None,
):
    require_token(authorization or None)
    alias = CERTIFICATE_MAP.get(certificate)
    if not alias:
        raise HTTPException(status_code=403, detail="Certificate is not configured for this signing service")

    cert_dir = ROOT / alias
    p12 = cert_dir / "signing.p12"
    profile = cert_dir / "profile.mobileprovision"
    password = os.environ.get(f"P12_PASSWORD_{alias}")
    if not p12.is_file() or not profile.is_file() or password is None:
        raise HTTPException(status_code=503, detail="Certificate configuration is incomplete")

    job_id = uuid.uuid4().hex
    work = Path(tempfile.mkdtemp(prefix=f"dualipa-{job_id}-"))
    keychain = work / "signing.keychain-db"
    try:
        incoming = work / "input.ipa"
        incoming.write_bytes(await ipa.read())
        payload = work / "payload"
        payload.mkdir()
        with zipfile.ZipFile(incoming) as z:
            z.extractall(payload)
        app_bundle = find_app(payload)
        entitlements = work / "entitlements.plist"
        profile_entitlements(profile, entitlements)
        shutil.copy2(profile, app_bundle / "embedded.mobileprovision")

        identity = install_identity(p12, password, keychain)
        run("codesign", "--force", "--deep", "--sign", identity, "--entitlements", str(entitlements), str(app_bundle))
        run("codesign", "--verify", "--deep", "--strict", str(app_bundle))

        out_dir = Path(os.environ.get("OUTPUT_DIR", "./public")).resolve()
        out_dir.mkdir(parents=True, exist_ok=True)
        out_ipa = out_dir / f"{job_id}.ipa"
        with zipfile.ZipFile(out_ipa, "w", zipfile.ZIP_DEFLATED) as z:
            for path in payload.rglob("*"):
                if path.is_file():
                    z.write(path, path.relative_to(payload))

        manifest = {
            "items": [{
                "assets": [{"kind": "software-package", "url": f"{PUBLIC_BASE_URL}/{out_ipa.name}"}],
                "metadata": {"bundle-identifier": "", "kind": "software", "title": ipa.filename or "Signed IPA", "version": "1.0"}
            }]
        }
        info = plistlib.loads((app_bundle / "Info.plist").read_bytes())
        manifest["items"][0]["metadata"]["bundle-identifier"] = info.get("CFBundleIdentifier", "")
        manifest["items"][0]["metadata"]["version"] = info.get("CFBundleShortVersionString", info.get("CFBundleVersion", "1.0"))
        manifest_path = out_dir / f"{job_id}.plist"
        manifest_path.write_bytes(plistlib.dumps(manifest, fmt=plistlib.FMT_XML, sort_keys=False))
        return {"installManifestURL": f"{PUBLIC_BASE_URL}/{manifest_path.name}"}
    except (zipfile.BadZipFile, RuntimeError, subprocess.CalledProcessError) as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        try:
            run("security", "delete-keychain", str(keychain))
        except Exception:
            pass
        shutil.rmtree(work, ignore_errors=True)


@app.get("/{filename}")
def public_file(filename: str):
    public = Path(os.environ.get("OUTPUT_DIR", "./public")).resolve()
    path = (public / filename).resolve()
    if public not in path.parents or not path.is_file():
        raise HTTPException(status_code=404)
    media = "application/octet-stream" if path.suffix == ".ipa" else "application/xml"
    return FileResponse(path, media_type=media)
