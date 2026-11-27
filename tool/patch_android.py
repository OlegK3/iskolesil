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
# Иконка: убираем стандартные ic_launcher.* и копируем наши ресурсы (adaptive + monochrome)
res_dst = app / "src/main/res"
for d in res_dst.glob("mipmap-*"):
    for f in d.glob("ic_launcher.*"):
        f.unlink()
for f in (root / "android_overlay/res").rglob("*"):
    if f.is_file():
        t = res_dst / f.relative_to(root / "android_overlay/res")
        t.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(f, t)

# Подпись release: ключ из переменных окружения (ANDROID_KEYSTORE_PATH, KEYSTORE_PASSWORD,
# KEY_ALIAS, KEY_PASSWORD). Без них — debug-подпись (обновление поверх не установится).
for g in (app / "build.gradle.kts", app / "build.gradle"):
    if not g.exists():
        continue
    s = g.read_text(encoding="utf-8")
    if "iskRelease" in s:
        break
    kts = g.suffix == ".kts"
    if kts:
        block = """
    signingConfigs {
        create("iskRelease") {
            val ksPath = System.getenv("ANDROID_KEYSTORE_PATH")
            if (ksPath != null && ksPath.isNotEmpty()) {
                storeFile = file(ksPath)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }
"""
        s, n1 = re.subn(r"(\nandroid\s*\{)", lambda m: m.group(1) + block, s, count=1)
        s, n2 = re.subn(
            r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
            'signingConfig = if (!System.getenv("ANDROID_KEYSTORE_PATH").isNullOrEmpty()) signingConfigs.getByName("iskRelease") else signingConfigs.getByName("debug")',
            s)
    else:
        block = """
    signingConfigs {
        iskRelease {
            def ksPath = System.getenv("ANDROID_KEYSTORE_PATH")
            if (ksPath) {
                storeFile file(ksPath)
                storePassword System.getenv("KEYSTORE_PASSWORD")
                keyAlias System.getenv("KEY_ALIAS")
                keyPassword System.getenv("KEY_PASSWORD")
            }
        }
    }
"""
        s, n1 = re.subn(r"(\nandroid\s*\{)", lambda m: m.group(1) + block, s, count=1)
        s, n2 = re.subn(
            r"signingConfig\s+signingConfigs\.debug",
            'signingConfig System.getenv("ANDROID_KEYSTORE_PATH") ? signingConfigs.iskRelease : signingConfigs.debug',
            s)
    if n1 == 0 or n2 == 0:
        print("::warning::Не удалось пропатчить подпись в", g, "(android-блок:", n1, ", signingConfig:", n2, "). Сборка пойдёт с debug-подписью.")
    else:
        g.write_text(s, encoding="utf-8")
    break
print("Android patched")
