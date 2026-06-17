# Copyright (c) 2019-2024, see AUTHORS. Licensed under MIT License, see LICENSE.

{ pkgsCross
, fetchurl
, python3
, pkg-config
, wafHook
}:

pkgsCross.stdenv.mkDerivation rec {
  pname = "talloc";
  version = "2.4.4";

  src = fetchurl {
    url = "mirror://samba/talloc/${pname}-${version}.tar.gz";
    sha256 = "sha256-VeR5lAGME3Q0hVROcgZ4D/uzyElecEqZY2UD5ud6v1k=";
  };

  nativeBuildInputs = [ pkg-config python3 wafHook ];
  buildInputs = [ ];

  wafPath = "./buildtools/bin/waf";
  wafConfigureFlags = [
    "--disable-rpath"
    "--disable-python"
    "--cross-compile"
    "--cross-answers=cross-answers.txt"
  ];

  preConfigure = ''
    export PYTHONHASHSEED=1
    cat <<EOF > cross-answers.txt
    Checking uname sysname type: "Linux"
    Checking uname machine type: "dontcare"
    Checking uname release type: "dontcare"
    Checking uname version type: "dontcare"
    Checking simple C program: OK
    building library support: OK
    Checking for large file support: OK
    Checking for -D_FILE_OFFSET_BITS=64: OK
    Checking for WORDS_BIGENDIAN: OK
    Checking for C99 vsnprintf: OK
    Checking for HAVE_SECURE_MKSTEMP: OK
    rpath library support: OK
    -Wl,--version-script support: FAIL
    Checking correct behavior of strtoll: OK
    Checking correct behavior of strptime: OK
    Checking for HAVE_IFACE_GETIFADDRS: OK
    Checking for HAVE_IFACE_IFCONF: OK
    Checking for HAVE_IFACE_IFREQ: OK
    Checking getconf LFS_CFLAGS: OK
    Checking for large file support without additional flags: OK
    Checking for working strptime: OK
    Checking for HAVE_SHARED_MMAP: OK
    Checking for HAVE_MREMAP: OK
    Checking for HAVE_INCOHERENT_MMAP: OK
    Checking getconf large file support flags work: OK
    EOF
  '';

  # can't link unneeded .so, we'll link a static one by hand
  buildPhase = "python ./buildtools/bin/waf build || true";
  installPhase = ''
    mkdir -p $out/lib $out/include
    objs=$(find bin \( -name 'talloc.c.*.o' -o -path '*/lib/replace/*.o' \))
    test -n "$objs" || { echo "no talloc objects"; exit 1; }
    ${pkgsCross.stdenv.cc.targetPrefix}ar rcs $out/lib/libtalloc.a $objs
    cp talloc.h $out/include/
  '';
}
