#!/usr/bin/env bash
# Enable FTEN (Feature Enable) at physical address 0x775C4018
# Requires: iomem=relaxed kernel param + root
set -euo pipefail

python3 -c "
import mmap, os
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
mm = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x775C4000)
print(f'FTEN before: {mm[0x18]}')
mm[0x18] = 1
print(f'FTEN after:  {mm[0x18]}')
mm.close()
os.close(fd)
"
