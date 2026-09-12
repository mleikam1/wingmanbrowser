#!/usr/bin/env python3
"""Create a dedicated, ignored consumer-project copy; never modifies the main adapter."""
from pathlib import Path
import json, shutil, subprocess, hashlib, argparse, tempfile
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--destination', type=Path, default=Path(tempfile.gettempdir()) / 'wingman-geckoview-prototype')
DEST = parser.parse_args().destination.expanduser().resolve()
if DEST == ROOT or ROOT in DEST.parents or DEST in ROOT.parents:
    parser.error('Use a separate destination outside the source checkout so root analysis remains clean.')
if DEST.exists():
    if not DEST.is_dir():
        parser.error('The destination must be a directory.')
    if any(DEST.iterdir()):
        try:
            marker = json.loads((DEST / 'prototype-build.json').read_text())
            owned = isinstance(marker, dict) and marker.get('applicationId') == 'com.wingmanbrowser.wingman_browser.gecko_prototype'
        except (OSError, ValueError):
            owned = False
        if not owned:
            parser.error('A nonempty destination must have a valid Wingman Gecko prototype-build.json ownership marker.')
OVERLAY = Path(__file__).resolve().parent / 'overlay'
EXCLUDED = {'.git', '.dart_tool', '.gradle', '.idea', 'build', 'work', 'prototypes', 'Pods', '.symlinks', 'ephemeral', 'node_modules'}
# Overlay refresh preserves build caches and the isolated installed application's data.
shutil.copytree(ROOT, DEST, dirs_exist_ok=True, ignore=lambda path,names: [n for n in names if n in EXCLUDED])
shutil.copytree(OVERLAY, DEST, dirs_exist_ok=True)
app = DEST / 'android/app/build.gradle.kts'
s = app.read_text().replace('applicationId = "com.wingmanbrowser.wingman_browser"', 'applicationId = "com.wingmanbrowser.wingman_browser.gecko_prototype"')
s = s.replace('minSdk = 24', 'minSdk = 26')
s = s.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 37\n    useLibrary("android.test.runner")\n    useLibrary("android.test.base")')
s = s.replace('defaultConfig {', 'defaultConfig {\n        testInstrumentationRunner = "android.test.InstrumentationTestRunner"\n        ndk { abiFilters.clear(); abiFilters.add("arm64-v8a") }')
s = s.replace('dependencies {', 'dependencies {\n    implementation("org.mozilla.geckoview:geckoview:155.0.20260903215306")')
app.write_text(s)
build = DEST / 'android/build.gradle.kts'
s = build.read_text().replace('mavenCentral()', 'mavenCentral()\n        maven { url = uri("https://maven.mozilla.org/maven2/") }')
build.write_text(s)
settings = DEST / 'android/settings.gradle.kts'
settings.write_text(settings.read_text().replace('version "2.3.20"', 'version "2.4.10"').replace('version "9.0.1"', 'version "9.1.1"'))
wrapper = DEST / 'android/gradle/wrapper/gradle-wrapper.properties'
wrapper.write_text(wrapper.read_text().replace('gradle-9.1.0-all.zip','gradle-9.3.1-all.zip'))
properties = DEST / 'android/gradle.properties'
lines = [line for line in properties.read_text().splitlines() if not line.startswith(('org.gradle.jvmargs=', 'org.gradle.workers.max=', 'kotlin.compiler.execution.strategy='))]
properties.write_text('\n'.join(lines) + '\norg.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m\norg.gradle.workers.max=2\nkotlin.compiler.execution.strategy=in-process\n')
manifest = DEST / 'android/app/src/main/AndroidManifest.xml'
manifest.write_text(manifest.read_text().replace('android:label="Wingman Browser"','android:label="Wingman Gecko Prototype"'))
extension = DEST / 'android/app/src/main/assets/wingman-policy'
extension.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT/'assets/policy/consumer_protection.json', extension/'baseline.json')
overlay_hash = hashlib.sha256()
for p in sorted(OVERLAY.rglob('*')):
    if p.is_file(): overlay_hash.update(str(p.relative_to(OVERLAY)).encode()); overlay_hash.update(p.read_bytes())
receipt = {'overlaySha256':overlay_hash.hexdigest(), 'sourceStatus':subprocess.check_output(['git','status','--short'],cwd=ROOT,text=True), 'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(), 'entryPoint':'lib/main.dart','applicationId':'com.wingmanbrowser.wingman_browser.gecko_prototype','engine':'org.mozilla.geckoview:geckoview:155.0.20260903215306','productionDefault':'Android System WebView'}
(DEST/'prototype-build.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(DEST)
