import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)
src = open("block_params.py", encoding="utf8").read().split("for BUF,CELL,MIN,COV in")[0]
exec(src)
r, n = make(14, 32, 800, 0.4)
json.dump([[round(v) for v in x] for x in r], open("blocks_final.json", "w"))
print(len(r), "final blocks from", n, "blobs")
