#!/usr/bin/env python3
"""Патчит сгенерированный flutter create Android-проект. Идемпотентен."""
import pathlib, re, shutil, sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
app = root / "android" / "app"
manifest = app / "src/main/AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")

PERMS = [
    "android.permission.INTERNET",  # нужен для loopback-сервера тайлов и загрузки карт
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
]
add = "".join(
    f'\n    <uses-permission android:name="{p}" />'
    for p in PERMS if p not in text
)
if add:
    text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + add, text, count=1)

text = re.sub(r'android:label="[^"]*"', 'android:label="ИСКОЛЕСИЛ"', text, count=1)
extra = ""
if "networkSecurityConfig" not in text:
    extra += ' android:networkSecurityConfig="@xml/network_security_config"'
if "allowBackup" not in text:
    extra += ' android:allowBackup="false"'  # без автобэкапа в облако Google
if extra:
    text = text.replace("<application", "<application" + extra, 1)
manifest.write_text(text, encoding="utf-8")

xml_dir = app / "src/main/res/xml"
xml_dir.mkdir(parents=True, exist_ok=True)
shutil.copy(root / "android_overlay/network_security_config.xml",
            xml_dir / "network_security_config.xml")

# MainActivity с каналом свободного места / метрической сети
for f in (app / "src/main").rglob("MainActivity.*"):
    if f.suffix in (".kt", ".java"):
        pkg = re.search(r"package\s+([\w.]+)", f.read_text(encoding="utf-8")).group(1)
        f.unlink()
        tpl = (root / "android_overlay/MainActivity.kt.tpl").read_text(encoding="utf-8")
        out = f.with_suffix(".kt")
        out.write_text(tpl.replace("__PACKAGE__", pkg), encoding="utf-8")
        break

# minSdk 24
for g in (app / "build.gradle", app / "build.gradle.kts"):
    if g.exists():
        s = g.read_text(encoding="utf-8")
        s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", s)
        s = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", s)
        g.write_text(s, encoding="utf-8")
print("Android patched")
