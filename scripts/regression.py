import sys
import subprocess
import os
from pathlib import Path

def compile_image(cpp_file: str) -> bool:
    result = subprocess.run(["make", "image", cpp_file,
                             f"IMAGE_TARGET={Path(cpp_file).stem}_image.mem"])
    return result.returncode == 0

def run_test(image_name: str) -> bool:
    mem_file = f"./csrc/image/{image_name}"
    log_file = f"./log/{image_name.replace('.mem', '.log')}"
    result = subprocess.run([
        "make", "run",
        f"TEST=mem_image_test",
        f"MEM_FILE={mem_file}",
        f"LOG={log_file}",
    ])
    return result.returncode == 0

def parse_log(log_file: Path) -> dict:
    status = {}
    with log_file.open() as f:
        for line_no, line in enumerate(f, start=1):
            if "Report counts by severity" in line:
                break
            if "ERROR" in line or "UVM_ERROR" in line or "UVM_FATAL" in line:
                status[0] = { line_no: line.strip() }
                break
    with log_file.open() as f:
        for line_no, line in enumerate(f, start=1):
            if "PASS" in line:
                status[1] = { line_no: line.strip() }
    return status

def main():

    subprocess.run(["make", "clean"])

    if len(sys.argv) != 1:
        for file in sys.argv[1:]:
            path = Path(file)
            if path.suffix == ".cpp":
                compile_image(file)
    else:
        for cpp_file in Path("csrc").glob("*.cpp"):
            compile_image(str(cpp_file))

    image_path = "./csrc/image"
    image_files = [f for f in os.listdir(image_path) if f.endswith(".mem")]
    for image_file in image_files:
        if not run_test(image_file):
            print(f"Failed to run test for {image_file}")
        
    log_path = "./log"
    log_files = [f for f in os.listdir(log_path) if f.endswith(".log")]
    pass_test_count = 0
    fail_test_count = 0
    for log_file in log_files:
        status = parse_log(Path(log_path) / log_file)
        print(f"\n")
        if 1 in status:
            print(f"  {log_file}: {list(status[1].values())[0]}")
            if 0 in status:
                print(f"  FirstError at line {list(status[0].keys())[0]}: {list(status[0].values())[0]}")
                fail_test_count += 1
            else:
                pass_test_count += 1
        else:
            print(f"  {log_file}: No PASS found, likely failed.")
            fail_test_count += 1

    print(f"\nSummary:")
    print(f"  Passed Tests Count: {pass_test_count}")
    print(f"  Failed Tests Count: {fail_test_count}")

if __name__ == "__main__":
    main()
