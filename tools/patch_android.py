#!/usr/bin/env python3
"""Prilagođava generisani Android projekat:
- INTERNET dozvola (release build je nema)
- dozvoljen http (IPTV serveri su skoro uvijek http)
- Android TV: leanback launcher, touchscreen nije obavezan
- minSdk 21 (stari Android TV uređaji)
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]) / "android" / "app"
manifest = root / "src" / "main" / "AndroidManifest.xml"
t = manifest.read_text(encoding="utf-8")

if "android.permission.INTERNET" not in t:
    t = t.replace(
        "<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n'
        '    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>\n'
        '    <uses-feature android:name="android.software.leanback" android:required="false"/>\n'
        "    <application",
        1,
    )

if "usesCleartextTraffic" not in t:
    t = t.replace("<application", '<application android:usesCleartextTraffic="true"', 1)

if "LEANBACK_LAUNCHER" not in t:
    t = re.sub(
        r'(<category\s+android:name="android\.intent\.category\.LAUNCHER"\s*/>)',
        r'\1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
        t,
        count=1,
    )

manifest.write_text(t, encoding="utf-8")

ok = all(s in t for s in ("android.permission.INTERNET", "usesCleartextTraffic", "LEANBACK_LAUNCHER"))
print("manifest patch:", "OK" if ok else "NIJE KOMPLETAN")

changed = False
for g in root.glob("build.gradle*"):
    s = g.read_text(encoding="utf-8")
    n = re.sub(r"(minSdk(?:Version)?(?:\s*=\s*|\s+))(?:flutter\.minSdkVersion|\d+)", r"\g<1>21", s)
    if n != s:
        g.write_text(n, encoding="utf-8")
        changed = True
        print("minSdk=21 u", g.name)
if not changed:
    print("UPOZORENJE: minSdk nije pronađen/izmijenjen")

sys.exit(0 if ok else 1)
