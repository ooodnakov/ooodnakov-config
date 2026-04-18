import subprocess
try:
    result = subprocess.run(["pwsh", "-c", ". ./test.ps1"], capture_output=True, text=True, check=True)
    print("STDOUT:", result.stdout)
except subprocess.CalledProcessError as e:
    print("ERROR:", e)
    print("STDERR:", e.stderr)
except FileNotFoundError:
    print("pwsh not found. Try powershell")
    try:
        result = subprocess.run(["powershell", "-c", ". ./test.ps1"], capture_output=True, text=True, check=True)
        print("STDOUT:", result.stdout)
    except FileNotFoundError:
        print("neither pwsh nor powershell found")
