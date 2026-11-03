#!/usr/bin/env python3
"""Sign JP27 with a certificate (.p12) and a provisioning profile (.mobileprovision) you were given,
or with the free Personal Team of any Apple Account signed in to Xcode.

    python3 scripts/use-profile.py app.mobileprovision [widgets.mobileprovision] [--no-generate]
    python3 scripts/use-profile.py --personal-team [TEAMID] [--bundle-id com.you.jp27]

Reads what the profile allows, copies it where Xcode looks for profiles, checks that the
certificate it names is in your keychain (import the .p12 first: double-click it), and writes
Config/Signing.local.xcconfig with the entitlements files that profile grants: signing fails on any
entitlement the profile lacks, WeatherKit for one. Then runs xcodegen, without the widget extension
when there is no profile for it. Run from anywhere; the paths are resolved from this file.

A Personal Team signs with automatic signing, widget included, and allows App Groups but neither
WeatherKit nor Time Sensitive notifications; its builds expire after seven days.
"""

import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

IOS = Path(__file__).resolve().parent.parent
CONFIG = IOS / "Config"
DEFAULT_ID = "tech.delphyra.jp27"
DEFAULT_GROUP = "group.tech.delphyra.jp27"
GROUPS = "com.apple.security.application-groups"
WEATHERKIT = "com.apple.developer.weatherkit"
TIME_SENSITIVE = "com.apple.developer.usernotifications.time-sensitive"
MAC = sys.platform == "darwin"


def fail(message):
    print(f"\n✗ {message}", file=sys.stderr)
    sys.exit(1)


def decode(path):
    """The plist inside the profile's CMS envelope. It is stored as is, so it can be cut out
    without `security cms -D` (which is tried when that fails)."""
    data = Path(path).read_bytes()
    start, end = data.find(b"<?xml"), data.find(b"</plist>")
    if start >= 0 and end > start:
        try:
            return plistlib.loads(data[start : end + len(b"</plist>")])
        except Exception:
            pass
    if MAC:
        out = subprocess.run(["security", "cms", "-D", "-i", str(path)], capture_output=True)
        if out.returncode == 0:
            return plistlib.loads(out.stdout)
    fail(f"Không đọc được {path}: có đúng là file .mobileprovision không?")


class Profile:
    def __init__(self, path):
        self.path = Path(path)
        p = decode(path)
        e = p.get("Entitlements", {})
        self.name = p.get("Name", self.path.stem)
        self.uuid = p["UUID"]
        self.team = (p.get("TeamIdentifier") or [""])[0]
        prefix = (p.get("ApplicationIdentifierPrefix") or [self.team])[0]
        full = e.get("application-identifier", "")
        self.bundle = full[len(prefix) + 1 :] if full.startswith(prefix + ".") else full.split(".", 1)[-1]
        self.groups = list(e.get(GROUPS, []))
        self.weatherkit = bool(e.get(WEATHERKIT))
        self.time_sensitive = bool(e.get(TIME_SENSITIVE))
        self.debuggable = bool(e.get("get-task-allow"))
        self.devices = list(p.get("ProvisionedDevices", []))
        self.all_devices = bool(p.get("ProvisionsAllDevices"))
        self.expires = p.get("ExpirationDate")
        self.certs = [hashlib.sha1(der).hexdigest().upper() for der in p.get("DeveloperCertificates", [])]

    @property
    def kind(self):
        if self.all_devices:
            return "enterprise"
        if self.devices:
            return "development" if self.debuggable else "ad hoc"
        return "app store"

    @property
    def wildcard(self):
        return self.bundle.endswith("*")

    def check(self, role):
        now = datetime.datetime.now(datetime.timezone.utc)
        expires = self.expires.replace(tzinfo=datetime.timezone.utc) if self.expires and self.expires.tzinfo is None else self.expires
        if expires and expires < now:
            fail(f"Profile {role} \"{self.name}\" đã hết hạn ngày {expires:%d/%m/%Y}. Cần profile mới.")
        if self.kind == "app store":
            fail(f"Profile {role} \"{self.name}\" là loại App Store: không cài thẳng lên máy được. "
                 "Cần profile Development, Ad Hoc hoặc Enterprise.")
        if not self.certs:
            fail(f"Profile {role} \"{self.name}\" không chứa chứng chỉ nào.")

    def describe(self):
        lines = [
            f"  Tên:          {self.name}",
            f"  Loại:         {self.kind}",
            f"  Team:         {self.team}",
            f"  Bundle ID:    {self.bundle}",
            f"  App Group:    {', '.join(self.groups) or 'không có'}",
            f"  WeatherKit:   {'có' if self.weatherkit else 'không'}",
            f"  Time Sensitive: {'có' if self.time_sensitive else 'không'}",
        ]
        if self.expires:
            lines.append(f"  Hết hạn:      {self.expires:%d/%m/%Y}")
        if self.devices:
            lines.append(f"  Thiết bị:     {len(self.devices)} máy đăng ký")
        return "\n".join(lines)

    def install(self):
        """Xcode 16+ reads UserData/Provisioning Profiles; older Xcode, MobileDevice."""
        if not MAC:
            return
        home = Path.home()
        for folder in (home / "Library/Developer/Xcode/UserData/Provisioning Profiles",
                       home / "Library/MobileDevice/Provisioning Profiles"):
            folder.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.path, folder / f"{self.uuid}.mobileprovision")


def identities():
    """(valid, all) code signing identity hashes in the keychains."""
    def run(args):
        out = subprocess.run(["security", "find-identity", *args, "-p", "codesigning"], capture_output=True, text=True)
        return {line.split()[1].upper() for line in out.stdout.splitlines() if ")" in line and len(line.split()) > 1}
    return run(["-v"]), run([])


def pick_identity(profiles):
    """The certificate every profile names that is in the keychain with its private key."""
    shared = set(profiles[0].certs)
    for p in profiles[1:]:
        shared &= set(p.certs)
    if not shared:
        fail("Hai profile được ký cho hai chứng chỉ khác nhau; app và widget phải dùng chung một chứng chỉ.")
    if not MAC:
        return sorted(shared)[0]
    valid, every = identities()
    usable = [h for h in profiles[0].certs if h in shared and h in valid]
    if usable:
        return usable[0]
    if shared & every:
        fail("Chứng chỉ đã có trong Keychain nhưng macOS chưa tin nó: thiếu chứng chỉ trung gian của Apple.\n"
             "  Tải \"Worldwide Developer Relations - G3\" ở https://www.apple.com/certificateauthority/ ,\n"
             "  mở file .cer để thêm vào Keychain, rồi chạy lại.")
    fail("Không thấy chứng chỉ của profile trong Keychain.\n"
         "  Mở file .p12 (nhấp đúp, nhập mật khẩu của nó) để thêm vào Keychain \"login\", rồi chạy lại.\n"
         "  Nếu đã thêm rồi mà vẫn báo thế, file .p12 không phải chứng chỉ mà profile này được cấp cho.")


def connected_devices():
    """UDIDs of the iPhones plugged in or paired, best effort (Xcode 15+)."""
    if not MAC:
        return []
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "devices.json"
        try:
            subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output", str(out)],
                           capture_output=True, timeout=30)
            devices = json.loads(out.read_text()).get("result", {}).get("devices", [])
        except Exception:
            return []
    return [(d.get("deviceProperties", {}).get("name", "iPhone"), d.get("hardwareProperties", {}).get("udid"))
            for d in devices if d.get("hardwareProperties", {}).get("udid")]


def entitlements(path, group, profile):
    """Only what the profile grants: the build setting keeps the group in step with Info.plist."""
    e = {}
    if group and group in profile.groups:
        e[GROUPS] = ["$(JP27_APP_GROUP)"]
    if profile.weatherkit:
        e[WEATHERKIT] = True
    if profile.time_sensitive:
        e[TIME_SENSITIVE] = True
    path.write_bytes(plistlib.dumps(e))
    return e


def generate(spec, skip):
    command = ["xcodegen", "--spec", spec]
    if skip or not shutil.which("xcodegen"):
        print(f"\nTạo project: cd {IOS} && {' '.join(command)}")
    else:
        subprocess.run(command, cwd=IOS, check=True)
        print(f"\nMở {IOS / 'JP27.xcodeproj'}, chọn iPhone của bạn rồi Run.")


def keychain_teams():
    """(team id, holder) of the Apple Development certificates in the keychain: the team id is the
    certificate's OU, which Xcode does not show for a Personal Team."""
    if not MAC:
        return []
    out = subprocess.run(["security", "find-certificate", "-a", "-c", "Apple Development", "-p"], capture_output=True, text=True)
    teams = {}
    for pem in out.stdout.split("-----END CERTIFICATE-----")[:-1]:
        pem += "-----END CERTIFICATE-----\n"
        subject = subprocess.run(["openssl", "x509", "-noout", "-subject"], input=pem, capture_output=True, text=True).stdout
        ou = re.search(r"OU\s*=\s*([A-Z0-9]{10})", subject)
        org = re.search(r"\bO\s*=\s*([^,/\n]+)", subject)
        if ou:
            teams[ou.group(1)] = org.group(1).strip() if org else ""
    return sorted(teams.items())


def personal_team(team, bundle, skip):
    """Automatic signing with a free Apple Account: Xcode registers the ids and the group itself."""
    if team == "AUTO":
        found = keychain_teams()
        if len(found) != 1:
            listed = "".join(f"\n  {t}  {holder}" for t, holder in found)
            fail(("Có nhiều team trong Keychain, chọn một: --personal-team TEAMID" + listed) if found else
                 "Chưa có chứng chỉ Apple Development nào. Trong Xcode: Settings → Accounts → thêm Apple Account,\n"
                 "  chọn Personal Team → Manage Certificates… → + → Apple Development, rồi chạy lại.")
        team = found[0][0]
    if len(team) != 10 or not team.isalnum():
        fail(f"\"{team}\" không giống Team ID (10 ký tự chữ và số). Xem trong Xcode → Settings → Accounts.")
    # bundle ids are unique across all teams: the team id keeps this one free
    bundle = bundle or f"{DEFAULT_ID}.{team.lower()}"
    group = f"group.{bundle}"
    CONFIG.mkdir(exist_ok=True)
    for name in ("JP27.local.entitlements", "JP27Widgets.local.entitlements"):
        (CONFIG / name).write_bytes(plistlib.dumps({GROUPS: ["$(JP27_APP_GROUP)"]}))
    lines = [
        f"// Written by scripts/use-profile.py on {datetime.date.today():%Y-%m-%d}: free Personal Team {team}.",
        "",
        f"JP27_TEAM = {team}",
        "JP27_SIGN_STYLE = Automatic",
        "JP27_SIGN_IDENTITY = Apple Development",
        f"JP27_APP_ID = {bundle}",
        "JP27_APP_ENTITLEMENTS = Config/JP27.local.entitlements",
        "JP27_WIDGET_ENTITLEMENTS = Config/JP27Widgets.local.entitlements",
        f"JP27_APP_GROUP = {group}",
        "// a Personal Team gets neither WeatherKit nor Time Sensitive notifications",
        "JP27_WEATHERKIT = NO",
    ]
    (CONFIG / "Signing.local.xcconfig").write_text("\n".join(lines) + "\n")
    print(f"✓ Personal Team {team} · bundle ID {bundle} · App Group {group}")
    print("  · Dự báo mây lấy từ Open-Meteo; nhắc giờ tàu là thông báo thường.")
    print("  · Bản cài hết hạn sau 7 ngày: cắm máy và Run lại từ Xcode.")
    print("  · Lần đầu mở app: Cài đặt → Cài đặt chung → Quản lý VPN & thiết bị → tin cậy Apple ID của bạn.")
    generate("project.yml", skip)


def main():
    parser = argparse.ArgumentParser(description="Ký JP27 bằng .p12 và .mobileprovision có sẵn, hoặc bằng Personal Team.")
    parser.add_argument("app", nargs="?", help=".mobileprovision của app")
    parser.add_argument("widgets", nargs="?", help=".mobileprovision của widget extension (bundle id <app>.xxx)")
    parser.add_argument("--personal-team", metavar="TEAMID", nargs="?", const="auto",
                        help="ký tự động bằng Personal Team của một Apple Account miễn phí (bỏ TEAMID để tự tìm)")
    parser.add_argument("--bundle-id", help="bundle ID cho Personal Team (mặc định tech.delphyra.jp27.<teamid>)")
    parser.add_argument("--no-generate", action="store_true", help="không chạy xcodegen")
    args = parser.parse_args()

    if args.personal_team:
        return personal_team(args.personal_team.strip().upper(), args.bundle_id, args.no_generate)
    if not args.app:
        parser.error("cần file .mobileprovision của app, hoặc --personal-team TEAMID")

    app = Profile(args.app)
    app.check("của app")
    print("Profile của app:\n" + app.describe())
    widget = None
    if args.widgets:
        widget = Profile(args.widgets)
        widget.check("của widget")
        print("\nProfile của widget:\n" + widget.describe())
        if widget.team != app.team:
            fail("Hai profile thuộc hai team khác nhau.")
        if app.wildcard or not widget.bundle.startswith(app.bundle + "."):
            fail(f"Bundle ID của widget ({widget.bundle}) phải bắt đầu bằng bundle ID của app ({app.bundle}).")

    bundle = app.bundle
    if app.wildcard:
        stem = app.bundle.rstrip("*").rstrip(".")
        bundle = f"{stem}.jp27" if stem else DEFAULT_ID
        print(f"\n· Profile wildcard: dùng bundle ID {bundle}. Wildcard không có App Group.")
    group = DEFAULT_GROUP if DEFAULT_GROUP in app.groups else (app.groups[0] if app.groups else "")
    if widget and group and group not in widget.groups:
        print(f"\n! Profile của widget không có App Group {group}: widget sẽ không đọc được dữ liệu của app.")

    identity = pick_identity([p for p in (app, widget) if p])
    for p in (app, widget):
        if p:
            p.install()

    if app.kind in ("development", "ad hoc"):
        listed = set(app.devices) & (set(widget.devices) if widget else set(app.devices))
        plugged = connected_devices()
        for name, udid in plugged:
            mark = "có" if udid in listed else "KHÔNG có"
            print(f"\n· {name} ({udid}) {mark} trong danh sách máy của profile.")
        if plugged and not any(udid in listed for _, udid in plugged):
            print("  Máy không có trong profile thì không cài được: nhờ người cấp profile thêm UDID này rồi tạo lại profile.")

    CONFIG.mkdir(exist_ok=True)
    app_ent = entitlements(CONFIG / "JP27.local.entitlements", group, app)
    lines = [
        f"// Written by scripts/use-profile.py on {datetime.date.today():%Y-%m-%d}; run it again for a new profile.",
        f"// app: \"{app.name}\" ({app.kind}, {app.uuid})",
    ]
    if widget:
        lines.append(f"// widgets: \"{widget.name}\" ({widget.kind}, {widget.uuid})")
    lines += [
        "",
        f"JP27_TEAM = {app.team}",
        "JP27_SIGN_STYLE = Manual",
        f"JP27_SIGN_IDENTITY = {identity}",
        "",
        f"JP27_APP_ID = {bundle}",
        f"JP27_APP_PROFILE = {app.uuid}",
        "JP27_APP_ENTITLEMENTS = Config/JP27.local.entitlements",
        f"JP27_APP_GROUP = {group or DEFAULT_GROUP}",
        f"JP27_WEATHERKIT = {'YES' if app.weatherkit else 'NO'}",
    ]
    if widget:
        entitlements(CONFIG / "JP27Widgets.local.entitlements", group, widget)
        lines += [
            "",
            f"JP27_WIDGET_ID = {widget.bundle}",
            f"JP27_WIDGET_PROFILE = {widget.uuid}",
            "JP27_WIDGET_ENTITLEMENTS = Config/JP27Widgets.local.entitlements",
        ]
    if not app.debuggable:
        lines += [
            "",
            "// an ad hoc or enterprise profile has no get-task-allow: do not add it, or the install is refused",
            "CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO",
        ]
    (CONFIG / "Signing.local.xcconfig").write_text("\n".join(lines) + "\n")

    spec = "project.yml" if widget else "project.app-only.yml"
    print("\n✓ Đã viết Config/Signing.local.xcconfig và Config/JP27.local.entitlements"
          + (" + JP27Widgets.local.entitlements" if widget else ""))
    print(f"  Bundle ID {bundle} · team {app.team} · chứng chỉ {identity[:8]}…")
    print("\nSo với bản đầy đủ:")
    if not app_ent.get(GROUPS):
        print("  · Không có App Group: dữ liệu nằm trong app, widget không đọc được.")
    if not app.weatherkit:
        print("  · Không có WeatherKit: dự báo mây lấy từ Open-Meteo.")
    if not app.time_sensitive:
        print("  · Không có Time Sensitive: nhắc giờ tàu là thông báo thường, Focus có thể chặn.")
    if not widget:
        print("  · Không có profile cho widget: build không kèm widget và Live Activity.")
    if not app.debuggable:
        print("  · Profile không cho gắn debugger: Edit Scheme → Run → Info → bỏ chọn \"Debug executable\".")
    if app.kind == "enterprise":
        print("  · Profile enterprise: lần đầu mở app, vào Cài đặt → Cài đặt chung → Quản lý VPN & thiết bị để tin cậy.")

    generate(spec, args.no_generate)


if __name__ == "__main__":
    main()
