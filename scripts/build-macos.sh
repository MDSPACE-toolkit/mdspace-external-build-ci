#!/usr/bin/env bash
set -euo pipefail

component="${1:?usage: $0 <elnemo|genesis|smog2|xmipp>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
work="${WORK_DIR:-$root/work/$component}"
prefix="${PREFIX:-$root/install/$component}"
jobs="${JOBS:-$(sysctl -n hw.logicalcpu)}"

mkdir -p "$work" "$prefix"

brew_prefix="$(brew --prefix)"
export PATH="$brew_prefix/bin:$PATH"
export CPPFLAGS="-I$brew_prefix/include ${CPPFLAGS:-}"
export LDFLAGS="-L$brew_prefix/lib ${LDFLAGS:-}"
export PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:$brew_prefix/share/pkgconfig:${PKG_CONFIG_PATH:-}"

# Homebrew's versioned GCC binaries are named gcc-<major> and gfortran-<major>.
gfortran_bin="$(command -v gfortran || true)"
if [[ -z "$gfortran_bin" ]]; then
  gfortran_bin="$(find "$brew_prefix/bin" -maxdepth 1 -type l -name 'gfortran-*' | sort -V | tail -n1)"
fi
[[ -x "$gfortran_bin" ]] || { echo 'gfortran was not found'; exit 1; }
export FC="$gfortran_bin"
export F77="$gfortran_bin"

download_extract() {
  local url="$1" archive="$2"
  curl --fail --location --retry 3 "$url" -o "$archive"
  tar -xf "$archive"
}

build_elnemo() {
  cd "$work"
  rm -rf nma-master master.tar.gz
  download_extract https://github.com/MDSPACE-toolkit/nma/archive/refs/heads/master.tar.gz master.tar.gz
  cd nma-master/ElNemo
  make clean
  make -j"$jobs" FC="$FC" F77="$F77"
  install -d "$prefix/bin"
  install -m 0755 nma_diagrtb nma_check_modes nma_elnemo_pdbmat "$prefix/bin/"
}

build_genesis() {
cd "$work"
rm -rf mdspace-genesis-2.1.6.2 genesis.tar.gz

download_extract \
  https://github.com/MDSPACE-toolkit/mdspace-genesis/archive/refs/tags/2.1.6.2.tar.gz \
  genesis.tar.gz

genesis_dir="$work/mdspace-genesis-2.1.6.2"

[[ -f "$genesis_dir/configure.ac" ]] || {
  echo "configure.ac not found in $genesis_dir" >&2
  find "$work" -maxdepth 3 -name configure.ac -print
  exit 1
}

cd "$genesis_dir"

gcc_major="$(brew list --versions gcc | awk '{print $2}' | cut -d. -f1)"

gcc_bin="$(brew --prefix gcc)/bin/gcc-$gcc_major"
gxx_bin="$(brew --prefix gcc)/bin/g++-$gcc_major"
gfortran_bin="$(brew --prefix gcc)/bin/gfortran-$gcc_major"

export OMPI_CC="$gcc_bin"
export OMPI_CXX="$gxx_bin"
export OMPI_FC="$gfortran_bin"

export CC=mpicc
export CXX=mpicxx
export FC=mpifort
export F77=mpifort

fortran_flags="-O3 -ffast-math -ffree-line-length-none \
-fopenmp -fallow-argument-mismatch"

autoreconf -fi

./configure \
  --prefix="$prefix" \
  CC="$CC" \
  CXX="$CXX" \
  FC="$FC" \
  F77="$F77" \
  FCFLAGS="$fortran_flags" \
  FFLAGS="$fortran_flags"

make -j 1
make install
}

build_smog2() {
  cd "$work"
  rm -rf smog-2.5 smog-2.5.tgz Tree-DAG_Node-1.35 Tree-DAG_Node-1.35.tgz XML-Validator-Schema-1.10 XML-Validator-Schema-1.10.tar.gz
  download_extract https://smog-server.org/smog2/code/smog-2.5.tgz smog-2.5.tgz
  download_extract https://www.cpan.org/authors/id/R/RS/RSAVAGE/Tree-DAG_Node-1.35.tgz Tree-DAG_Node-1.35.tgz
  download_extract https://www.cpan.org/modules/by-module/XML/XML-Validator-Schema-1.10.tar.gz XML-Validator-Schema-1.10.tar.gz

  cd Tree-DAG_Node-1.35
  perl Makefile.PL INSTALL_BASE="$prefix"
  make -j"$jobs"
  make install
  cd ../XML-Validator-Schema-1.10
  PERL5LIB="$prefix/lib/perl5" perl Makefile.PL INSTALL_BASE="$prefix"
  make -j"$jobs"
  make install

  cd ../smog-2.5
  { echo '#!/usr/bin/env bash'; cat configure.smog2; } > configure
  chmod +x configure
  PERL5LIB="$prefix/lib/perl5" ./configure

  install -d "$prefix/share/smog2" "$prefix/bin"
  install -m 0644 src/*.pm "$prefix/share/smog2/"
  install -m 0755 src/smogv2 "$prefix/share/smog2/"
  cp -R SBM* "$prefix/share/smog2/"
  mkdir -p "$prefix/share/smog2/src/tools" "$prefix/share/smog2/share"
  cp -R src/tools/. "$prefix/share/smog2/src/tools/"
  cp -R share/. "$prefix/share/smog2/share/"

  cat > "$prefix/bin/smog2" <<WRAPPER
#!/usr/bin/env bash
export SMOG_PATH="$prefix/share/smog2"
export PERL5LIB="$prefix/lib/perl5:$prefix/share/smog2:\${PERL5LIB:-}"
exec "$(command -v perl)" "$prefix/share/smog2/smogv2" "\$@"
WRAPPER
  chmod +x "$prefix/bin/smog2"
  "$prefix/bin/smog2" -h >/dev/null 2>&1 || true
  test -x "$prefix/bin/smog2"
}

build_xmipp() {
cd "$work"

xmipp_version="5.0.0-Beta-gal"
xmipp_archive="$work/xmipp.tar.gz"
venv="$work/xmipp-installer-venv"

rm -rf "$work"/xmipp3-* "$xmipp_archive" "$venv"

curl --fail --location \
  "https://github.com/I2PC/xmipp3/archive/refs/tags/v${xmipp_version}.tar.gz" \
  --output "$xmipp_archive"

xmipp_dir="$(
  tar -tzf "$xmipp_archive" |
    awk -F/ 'NF { print $1; exit }'
)"

if [[ -z "$xmipp_dir" ]]; then
  echo "Could not determine the Xmipp source directory" >&2
  exit 1
fi

tar -xzf "$xmipp_archive" -C "$work"

xmipp_source="$work/$xmipp_dir"

if [[ ! -d "$xmipp_source" ]]; then
  echo "Xmipp source directory was not created: $xmipp_source" >&2
  exit 1
fi

python3 -m venv "$venv"
"$venv/bin/python" -m pip install --upgrade pip
"$venv/bin/python" -m pip install xmipp3-installer numpy

export PATH="$venv/bin:$PATH"
export XMIPP3_SEND_INSTALLATION_STATISTICS=OFF

cd "$xmipp_source"

# Download the Xmipp component source repositories.
./xmipp getSources

sqlite_prefix="$(brew --prefix sqlite)"
hdf5_prefix="$(brew --prefix hdf5)"
fftw_prefix="$(brew --prefix fftw)"

rm -rf build
numpy_include="$(
  "$venv/bin/python" -c 'import numpy; print(numpy.get_include())'
)"

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_CXX_STANDARD_REQUIRED=ON \
  -DXMIPP_LINK_TO_SCIPION=OFF \
  -DXMIPP_USE_CUDA=OFF \
  -DXMIPP_USE_MATLAB=OFF \
  -DXMIPP_USE_MPI=OFF \
  -DBUILD_TESTING=OFF \
  -DCMAKE_PREFIX_PATH="$sqlite_prefix;$hdf5_prefix;$fftw_prefix" \
  -DSQLite_ROOT="$sqlite_prefix" \
  -DSQLite3_INCLUDE_DIR="$sqlite_prefix/include" \
  -DSQLite3_LIBRARY="$sqlite_prefix/lib/libsqlite3.dylib" \
  -DHDF5_ROOT="$hdf5_prefix" \
  -DFFTW_ROOT="$fftw_prefix" \
  -DPython3_EXECUTABLE="$venv/bin/python" \
  -DPython3_NumPy_INCLUDE_DIR="$numpy_include" \
  -DPython3_FIND_STRATEGY=LOCATION

cmake --build build --parallel "$jobs"
cmake --install build

find "$prefix/bin" -type f -perm -111 -print -quit | grep -q .
}

case "$component" in
  elnemo) build_elnemo ;;
  genesis) build_genesis ;;
  smog2) build_smog2 ;;
  xmipp) build_xmipp ;;
  *) echo "unknown component: $component" >&2; exit 2 ;;
esac
