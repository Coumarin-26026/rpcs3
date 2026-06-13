#!/bin/bash

set +e

echo "=== LLVM19 AUTO FIX ==="

# 1. fmt::throw_exception -> thêm std::unreachable

find rpcs3 -type f ( -name "*.cpp" -o -name "*.h" ) | while read f
do
perl -0777 -i -pe '
s/fmt::throw_exception((.*?));/fmt::throw_exception($1);\n\tstd::unreachable();/gs
' "$f"
done

# 2. switch default không return

find rpcs3 -type f ( -name "*.cpp" -o -name "*.h" ) | while read f
do
perl -0777 -i -pe '
s/default:\s*fmt::throw_exception((.*?));/default:\n\tfmt::throw_exception($1);\n\tstd::unreachable();/gs
' "$f"
done

# 3. static_assert branch LLVM19

find rpcs3 -type f ( -name "*.cpp" -o -name "*.h" ) | while read f
do
perl -0777 -i -pe '
s/static_assert((.*?));\s*}/static_assert($1);\n\tstd::unreachable();\n}/gs
' "$f"
done

# 4. biến chưa khởi tạo

find rpcs3 -type f -name "*.cpp" | while read f
do
perl -0777 -i -pe '
s/u32\s+([a-zA-Z_0-9]+);/u32 $1 = 0;/g
' "$f"
done

echo "=== DONE ==="
