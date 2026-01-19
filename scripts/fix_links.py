import os
import sys

def fix_symlinks(root_dir):
    print(f"Scanning for absolute symlinks in {root_dir}...")
    count = 0
    for dirpath, dirnames, filenames in os.walk(root_dir):
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            if os.path.islink(filepath):
                target = os.readlink(filepath)
                # 如果是绝对路径，说明它指向了构建环境的根目录，需要修复
                if target.startswith('/'):
                    # 计算相对路径
                    rel_target = os.path.relpath(os.path.join(root_dir, target.lstrip('/')), dirpath)
                    
                    # 重新创建链接
                    try:
                        os.unlink(filepath)
                        os.symlink(rel_target, filepath)
                        count += 1
                    except OSError as e:
                        print(f"Error fixing {filepath}: {e}")
    
    print(f"Fixed {count} absolute symlinks.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 fix_links.py <sysroot_dir>")
        sys.exit(1)
    
    target_dir = sys.argv[1]
    fix_symlinks(target_dir)
