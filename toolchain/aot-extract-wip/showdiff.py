import sys
w=sys.argv[1]; d=open(w+'/describer.txt').read().splitlines(); n=open(w+'/native.txt').read().splitlines()
diff=[(i,x,y) for i,(x,y) in enumerate(zip(d,n)) if x!=y]
print(len(diff),'differing lines of',len(d))
for i,x,y in diff[:int(sys.argv[2]) if len(sys.argv)>2 else 3]:
    j=next(k for k in range(min(len(x),len(y))) if x[k]!=y[k])
    print(i, j); print(' D', x[max(0,j-250):j+200]); print(' N', y[max(0,j-250):j+200])
