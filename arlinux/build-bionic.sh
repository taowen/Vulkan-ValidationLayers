#!/usr/bin/env bash
# Optional Bionic diagnostics; dispatched by Wine's canonical component graph.
set -euo pipefail
[[ $# == 3 ]] || { echo 'Usage: build-bionic.sh NDK BUILD OUTPUT' >&2; exit 2; }
repo="$(cd "$(dirname "$0")/.." && pwd)"
ndk="$(realpath "$1")"; build="$(realpath -m "$2")"; output="$(realpath -m "$3")"
cmake -S "$repo" -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 -DANDROID_STL=c++_static \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DARLINUX_WAYLAND=ON \
    -DUPDATE_DEPS=ON -DUPDATE_DEPS_DIR="$build/dependencies" \
    -DBUILD_TESTS=OFF -DBUILD_WERROR=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS='-Wl,-z,max-page-size=16384'
cmake --build "$build" --parallel "${JOBS:-2}" --target VkLayer_khronos_validation
mkdir -p "$output/lib" "$output/layer" "$output/licenses"
cp "$build/layers/libVkLayer_khronos_validation.so" "$output/lib/"
cp "$repo/LICENSE.txt" "$output/licenses/Vulkan-ValidationLayers.txt"
cp "$repo/scripts/known_good.json" "$output/"
python3 - "$repo" "$build" "$output" <<'PACKAGE'
import hashlib,json,subprocess,sys
from pathlib import Path
repo,build,out=map(Path,sys.argv[1:])
manifest=json.loads((build/'layers/VkLayer_khronos_validation.json').read_text())
manifest['layer']['library_path']='../lib/libVkLayer_khronos_validation.so'
(out/'layer/validation.json').write_text(json.dumps(manifest,indent=2)+'\n')
for name in ('Vulkan-Headers','Vulkan-Utility-Libraries','SPIRV-Headers','SPIRV-Tools'):
    source=build/'dependencies'/name
    for license in sorted(source.glob('LICENSE*')):
        if license.is_file():
            (out/'licenses'/(name+'-'+license.name)).write_bytes(license.read_bytes())
files={p.relative_to(out).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
       for p in out.rglob('*') if p.is_file()}
(out/'provenance.json').write_text(json.dumps(dict(format=1,abi='aarch64-bionic',
    repository='taowen/Vulkan-ValidationLayers',commit=subprocess.check_output(
    ['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),files=files),indent=2)+'\n')
PACKAGE
