import subprocess, os

os.chdir(os.path.dirname(os.path.abspath(__file__)))

GIT = r"C:\Program Files\Git\bin\git.exe"

def run(args):
    print(f">>> git {' '.join(args)}")
    result = subprocess.run([GIT] + args, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print("STDERR:", result.stderr)
    print(f"Exit code: {result.returncode}")
    return result.returncode

# Config
run(['config', 'user.name', 'Xjrxjr'])
run(['config', 'user.email', 'deploy@gitee.com'])
run(['config', 'credential.helper', 'manager'])

# Add files
run(['add', 'index.html', 'data.json'])

# Commit
run(['commit', '-m', 'init website'])

# Add remote
run(['remote', 'remove', 'origin'])
run(['remote', 'add', 'origin', 'https://gitee.com/Xjrxjr/people.git'])

print("\n=== Ready to push ===")
print("Now run push...")

# Push - this might trigger credential prompt
push_result = subprocess.run(
    [GIT, 'push', '-u', 'origin', 'master'],
    capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120
)
if push_result.stdout:
    print(push_result.stdout)
if push_result.stderr:
    print("STDERR:", push_result.stderr)
print(f"Push exit code: {push_result.returncode}")

# Write result
with open('deploy_result.txt', 'w') as f:
    f.write(f"push_exit_code={push_result.returncode}\n")
    if push_result.stderr:
        f.write(f"stderr={push_result.stderr[:500]}\n")
    if push_result.stdout:
        f.write(f"stdout={push_result.stdout[:500]}\n")

print("\nDone! Check deploy_result.txt")
