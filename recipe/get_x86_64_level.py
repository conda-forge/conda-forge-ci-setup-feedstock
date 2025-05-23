import archspec.cpu
h = archspec.cpu.detect.host()
for i in range(4, 0, -1):
  check = f"x86_64_v{i}" if i > 1 else "x86_64"
  if h == check or check in h.ancestors:
    print(i)
    break
else:
  print(0)
