"""يُعدّل مشروع Android المولَّد بواسطة `flutter create` ليتوافق مع ميزات Zomedica Radar.

- صلاحيات: INTERNET، POST_NOTIFICATIONS، RECEIVE_BOOT_COMPLETED.
- اسم التطبيق: Zomedica Radar.
- minSdk = 23 (مطلوب لـ flutter_secure_storage / workmanager).
- Core library desugaring (مطلوب لـ flutter_local_notifications 17.x).

يدعم قوالب Gradle بصيغة Kotlin DSL (build.gradle.kts) وGroovy (build.gradle).
"""
import re
import sys
from pathlib import Path

PERMISSIONS = [
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />',
]
DESUGAR_VERSION = "2.1.4"


def patch_manifest(path: Path) -> None:
    s = path.read_text(encoding="utf-8")
    for perm in PERMISSIONS:
        if perm not in s:
            s = s.replace("<application", f"    {perm}\n    <application", 1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="Zomedica Radar"', s, count=1)
    path.write_text(s, encoding="utf-8")


def patch_gradle(path: Path) -> None:
    s = path.read_text(encoding="utf-8")
    kts = path.name.endswith(".kts")

    if kts:
        s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", s)
    else:
        s = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", s)

    # Core library desugaring داخل compileOptions (إن لم يكن موجوداً).
    if "coreLibraryDesugaring" not in s:
        flag = "isCoreLibraryDesugaringEnabled = true" if kts else "coreLibraryDesugaringEnabled true"
        if re.search(r"compileOptions\s*\{", s):
            s = re.sub(r"(compileOptions\s*\{)", r"\1\n        " + flag, s, count=1)
        else:
            raise SystemExit(f"compileOptions block not found in {path}")
        dep = (
            f'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:{DESUGAR_VERSION}")'
            if kts
            else f"coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:{DESUGAR_VERSION}'"
        )
        s += f"\n\ndependencies {{\n    {dep}\n}}\n"

    path.write_text(s, encoding="utf-8")


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "android")
    manifest = root / "app" / "src" / "main" / "AndroidManifest.xml"
    if manifest.exists():
        patch_manifest(manifest)
        print(f"patched {manifest}")
    for name in ("build.gradle.kts", "build.gradle"):
        gradle = root / "app" / name
        if gradle.exists():
            patch_gradle(gradle)
            print(f"patched {gradle}")
            break
    else:
        raise SystemExit("no app build.gradle(.kts) found")


if __name__ == "__main__":
    main()
