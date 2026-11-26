import json, subprocess, sys
sys.path.insert(0, 'tools')
import importlib.util
spec = importlib.util.spec_from_file_location('mt', 'tools/merge_train.py')
mt = importlib.util.module_from_spec(spec); spec.loader.exec_module(mt)

def stage(n, path):
    p = subprocess.run(['git','show',f':{n}:{path}'], capture_output=True)
    if p.returncode != 0:
        return mt._ABSENT
    return json.loads(p.stdout)

path = sys.argv[1]
base = stage(1, path); ours = stage(2, path); theirs = stage(3, path)
merged = mt.merge_sets(base, ours, theirs)
indent = mt.json_indent(subprocess.run(['git','show',f':2:{path}'],capture_output=True,text=True).stdout, 1)
open(path,'w').write(json.dumps(merged, indent=indent) + '\n')
print(f'merged sets {path}')
