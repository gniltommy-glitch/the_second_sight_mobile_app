import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[0]

boot = ROOT / 'scripts/bootstrap.py'
if boot.exists():
    boot_text = boot.read_text()
    # Remove the bad compilerOptions regex from bootstrap.py to prevent syntax errors
    boot_text = re.sub(r'if \'kotlin \{\' in text:\n.*?gradle.write_text\(text\)', 'gradle.write_text(text)', boot_text, flags=re.DOTALL)
    boot.write_text(boot_text)
