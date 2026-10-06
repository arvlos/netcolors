#!/usr/bin/env python3
"""Capture App Store screenshots in English and Russian.

Builds the app (Debug), installs it on an iPhone 17 Pro Max simulator (6.9", 1320 × 2868),
sets a clean status bar and launches the screenshot demo mode (NetColors/App/ScreenshotDemo.swift)
for each screen. Output: AppStore/screenshots/<locale>/NN_name.png.

Run from the repository root after `xcodegen generate`:  python3 tools/capture_screenshots.py
"""
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "AppStore/screenshots"
DERIVED = ROOT / "build/screenshots"
BUNDLE_ID = "com.artemlosev.netcolors"
DEVICE = "iPhone 17 Pro Max"

SHOTS = [  # file name, demo mode, tab — in App Store order
    ("01_full_access", "unrestricted", "status"),
    ("02_selected_services", "whitelist", "status"),
    ("03_diagnostics", "whitelist", "diagnostics"),
    ("04_history", "restricted", "history"),
    ("05_how_it_works", "whitelist", "howitworks"),
]
LOCALES = {"en-US": ("en", "en_US"), "ru": ("ru", "ru_RU")}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs)


def simulator_udid():
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json").stdout)["devices"]
    ios = sorted((runtime for runtime in devices if "iOS" in runtime), reverse=True)
    for runtime in ios:
        for device in devices[runtime]:
            if device["name"] == DEVICE:
                return device["udid"]
    raise SystemExit(f"No available simulator named {DEVICE}")


def main():
    udid = simulator_udid()
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    run("xcrun", "simctl", "bootstatus", udid, "-b")
    run("xcodebuild", "build", "-project", str(ROOT / "NetColors.xcodeproj"), "-scheme", "NetColors",
        "-destination", f"id={udid}", "-derivedDataPath", str(DERIVED))
    app = next(DERIVED.glob("Build/Products/*-iphonesimulator/NetColors.app"))
    run("xcrun", "simctl", "install", udid, str(app))
    run("xcrun", "simctl", "ui", udid, "appearance", "light")
    run("xcrun", "simctl", "status_bar", udid, "override", "--time", "19:30", "--dataNetwork", "lte",
        "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100")

    for folder, (language, locale) in LOCALES.items():
        (OUT / folder).mkdir(parents=True, exist_ok=True)
        for name, mode, tab in SHOTS:
            subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], capture_output=True)
            run("xcrun", "simctl", "launch", udid, BUNDLE_ID, "-ScreenshotMode", mode, "-ScreenshotTab", tab,
                "-appLanguage", language, "-AppleLanguages", f"({language})", "-AppleLocale", locale)
            time.sleep(3)  # launch animation and first layout
            path = OUT / folder / f"{name}.png"
            run("xcrun", "simctl", "io", udid, "screenshot", str(path))
            print(path.relative_to(ROOT))
    run("xcrun", "simctl", "status_bar", udid, "clear")


if __name__ == "__main__":
    main()
