## 2026-05-11 - [Command Injection & Path Traversal Fix]
**Vulnerability:** Found `subprocess.run(..., shell=True)` and `tarfile.extractall()` without filters.
**Learning:** Python scripts were using `shell=True` to run dynamically constructed strings from config files. `tarfile.extractall()` was used directly, which is vulnerable to zip slip if paths exist outside the current directory.
**Prevention:** Use list forms for subprocess execution or prepend shell execution safely via `["sh", "-c", line]`. Always use `filter="data"` (or safe explicit filtering) with `tarfile.extractall()` introduced in Python 3.12.
