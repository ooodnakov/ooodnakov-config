import urllib.request
import tarfile
import os
import subprocess

def download_pwsh():
    if os.path.exists("/tmp/pwsh_dir/pwsh"):
        return
    url = "https://github.com/PowerShell/PowerShell/releases/download/v7.4.1/powershell-7.4.1-linux-x64.tar.gz"
    print("Downloading powershell...")
    urllib.request.urlretrieve(url, "/tmp/pwsh.tar.gz")
    os.makedirs("/tmp/pwsh_dir", exist_ok=True)
    with tarfile.open("/tmp/pwsh.tar.gz") as tar:
        tar.extractall(path="/tmp/pwsh_dir")
    os.chmod("/tmp/pwsh_dir/pwsh", 0o755)
    print("Done")

if __name__ == "__main__":
    download_pwsh()
    result = subprocess.run(["/tmp/pwsh_dir/pwsh", "test2.ps1"], capture_output=True, text=True)
    print("STDOUT:", result.stdout)
    print("STDERR:", result.stderr)
    print("RETURN CODE:", result.returncode)
