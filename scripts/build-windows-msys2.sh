#!/usr/bin/env bash
set -euo pipefail

component="${1:?usage: $0 <elnemo|genesis|smog2|xmipp>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
work="${WORK_DIR:-$root/work/$component}"
prefix="${PREFIX:-$root/install/$component}"
jobs="${JOBS:-${NUMBER_OF_PROCESSORS:-2}}"

mkdir -p "$work" "$prefix"
export PATH="/mingw64/bin:/usr/bin:$PATH"
export CC=gcc CXX=g++ FC=gfortran F77=gfortran
export PKG_CONFIG_PATH="/mingw64/lib/pkgconfig:/mingw64/share/pkgconfig:${PKG_CONFIG_PATH:-}"

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
  make -j"$jobs" FC="$FC" F77="$F77" EXE=.exe
  install -d "$prefix/bin"
  for name in nma_diagrtb nma_check_modes nma_elnemo_pdbmat; do
    if [[ -f "$name.exe" ]]; then install -m 0755 "$name.exe" "$prefix/bin/"; else install -m 0755 "$name" "$prefix/bin/$name.exe"; fi
  done
  test -x "$prefix/bin/nma_diagrtb.exe"
}

build_genesis() {
  cd "$work"
  rm -rf mdspace-genesis-2.1.6.2 genesis.tar.gz
  download_extract https://github.com/MDSPACE-toolkit/mdspace-genesis/archive/refs/tags/2.1.6.2.tar.gz genesis.tar.gz
  cd mdspace-genesis-2.1.6.2
  autoreconf -fi
  ./configure --prefix="$prefix" --host=x86_64-w64-mingw32 FC="$FC" F77="$F77" CC="$CC"
  make -j"$jobs"
  make install
  find "$prefix/bin" -type f -name '*.exe' -print -quit | grep -q .
}

build_smog2() {
  cd "$work"
  rm -rf smog-2.5 smog-2.5.tgz Tree-DAG_Node-1.35 Tree-DAG_Node-1.35.tgz XML-Validator-Schema-1.10 XML-Validator-Schema-1.10.tar.gz
  download_extract https://smog-server.org/smog2/code/smog-2.5.tgz smog-2.5.tgz
  download_extract https://www.cpan.org/authors/id/R/RS/RSAVAGE/Tree-DAG_Node-1.35.tgz Tree-DAG_Node-1.35.tgz
  download_extract https://www.cpan.org/modules/by-module/XML/XML-Validator-Schema-1.10.tar.gz XML-Validator-Schema-1.10.tar.gz

  cd Tree-DAG_Node-1.35
  perl Makefile.PL INSTALL_BASE="$prefix"
  make -j"$jobs" && make install
  cd ../XML-Validator-Schema-1.10
  PERL5LIB="$prefix/lib/perl5" perl Makefile.PL INSTALL_BASE="$prefix"
  make -j"$jobs" && make install

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
exec perl "$prefix/share/smog2/smogv2" "\$@"
WRAPPER
  chmod +x "$prefix/bin/smog2"
  test -x "$prefix/bin/smog2"
}

build_xmipp() {
  cd "$work"
  rm -rf xmipp3-3.25.06.0-Rhea xmipp.tar.gz
  download_extract https://github.com/I2PC/xmipp3/archive/refs/tags/v3.25.06.0-Rhea.tar.gz xmipp.tar.gz
  cd xmipp3-3.25.06.0-Rhea
  ./xmipp getSources
  cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DXMIPP_LINK_TO_SCIPION=NO \
    -DXMIPP_USE_CUDA=OFF \
    -DXMIPP_USE_MATLAB=OFF \
    -DXMIPP_USE_MPI=OFF \
    -DPython3_EXECUTABLE=/mingw64/bin/python.exe \
    -DPython3_FIND_STRATEGY=LOCATION
  cmake --build build --parallel "$jobs"
  cmake --install build
  find "$prefix/bin" -type f -name '*.exe' -print -quit | grep -q .
}

case "$component" in
  elnemo) build_elnemo ;;
  genesis) build_genesis ;;
  smog2) build_smog2 ;;
  xmipp) build_xmipp ;;
  *) echo "unknown component: $component" >&2; exit 2 ;;
esac
