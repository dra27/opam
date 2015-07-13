AC_INIT(opam,2.0.0~beta3)
AC_COPYRIGHT(Copyright 2012-2017 OcamlPro SAS)

AC_CONFIG_MACRO_DIR([m4])

# If a bootstrap compiler has been built, always use it
PATH_PREPEND=
PRE_BOOTSTRAP_PATH="$PATH"
AS_IF([ test -x bootstrap/ocaml/bin/ocamlc -o -x bootstrap/ocaml/bin/ocamlopt ],[
  echo Bootstrap compiler found -- activating
  unset OCAMLLIB
  export PATH_PREPEND=`pwd`/bootstrap/ocaml/bin:
  export PATH="$PATH_PREPEND:$PATH"
])

AC_PROG_OCAML
if test "x$OCAMLC" = "xno"; then
   AC_MSG_ERROR([You must install the OCaml compiler])
fi
AC_CHECK_OCAML_OS_TYPE
if test "${OCAML_OS_TYPE}" = "Win32" ; then
  OCAMLLIB="$(echo "${OCAMLLIB}" | tr -d '\015' | sed -e 's|\\|/|g')"
fi

AC_PREFIX_DEFAULT([`echo "os_type: ${OCAML_OS_TYPE}" | sed -e "s;^os_type: Win32;C:/OPAM;" -e "s;^os_type:.*;/usr/local;"`])

AC_ARG_ENABLE([version_check],
  AS_HELP_STRING([--disable-version-check],
                 [Do not check OCaml version])
)

AC_ARG_ENABLE([checks],
  AS_HELP_STRING([--disable-checks],
                 [Assume OCaml dependencies are OK without checking])
)

AC_ARG_ENABLE([developer_mode],
  AC_HELP_STRING([--enable-developer-mode],
                 [Enable developer features])
)

# Check that OCaml version is greater or equal to 4.02.3
AS_IF([test "x${enable_version_check}" != "xno"], [
  AX_COMPARE_VERSION(
    [$OCAMLVERSION], [lt], [4.02.3],
    AC_MSG_ERROR([Your version of OCaml: $OCAMLVERSION is not supported]))
])

AC_MSG_CHECKING([for compiler type])
CCOMP_TYPE=`$OCAML shell/print_config.ml ccomp_type 2>/dev/null | fgrep -v "Cannot find" || $OCAMLC -config | tr -d '\r' | sed -n -e "s/ccomp_type: //p"`
AS_IF([ test "$?" -eq 0 ],,[AC_MSG_ERROR([failed])] )
AC_MSG_RESULT([$CCOMP_TYPE])
AC_MSG_CHECKING([for compiler architecture])
ARCH=`$OCAML shell/print_config.ml arch 2>/dev/null | fgrep -v "Cannot find" || $OCAMLC -config | tr -d '\r' | sed -n -e "s/architecture: //p"`
AS_IF([ test "$?" -eq 0 ],,[AC_MSG_ERROR([failed])] )
AC_MSG_RESULT([$ARCH])

LIB_PREPEND=
INC_PREPEND=
# Need the C compiler used for OCaml (important on Windows, as both x86 and x64 are used)
AS_IF([test "$OCAMLBEST" = "opt"],[OCAMLBESTCC=$OCAMLOPT],[OCAMLBESTCC=$OCAMLC])
OCAML_CC="$($OCAMLBESTCC -config | sed -n -e "s/native_c_compiler: \(.*\) .*/\1/p")"
set dummy ${OCAML_CC}; OCAML_TEST_CC=$2
AS_IF([test ! -x ${OCAML_TEST_CC}],[
  AS_IF([test "x${CCOMP_TYPE}" = "xmsvc"],[
    AS_IF([test "${ARCH}" = "i386"],[SDK_ARCH=x86],[SDK_ARCH=x64])
    AC_MSG_CHECKING([for an installed Microsoft C Compiler for ${SDK_ARCH}])
    eval `PATH="$PRE_BOOTSTRAP_PATH" ./shell/msvs-detect --arch=$SDK_ARCH`
    AS_IF([ test "x$MSVS_NAME" = "x" ], [
      AC_MSG_RESULT([no])
    ],[
      AC_MSG_RESULT([from $MSVS_NAME])
      export PATH_PREPEND="${MSVS_PATH}:${PATH_PREPEND}"
      # Note that we put ${MSVS_PATH} here NOT ${PATH_PREPEND} so that the bootstrap path isn't repeated
      export PATH="${MSVS_PATH}:$PATH"
      LIB_PREPEND="${MSVS_LIB};"
      INC_PREPEND="${MSVS_INC};"
      export Lib="${MSVS_LIB};$LIB"
      export Include="${MSVS_INC};$INCLUDE"
    ])
  ])
])
AC_PROG_CC(["${OCAML_CC}" gcc cc])

AS_IF([test "x${enable_developer_mode}" = "xyes"], [AC_SUBST(DEVELOPER,true)], [AC_SUBST(DEVELOPER,false)])

AC_ARG_VAR(DEVELOPER_CACHE, [Developer file cache location])

AS_IF([test "x${DEVELOPER_CACHE}" != "x"], [
  AS_IF([test "${enable_developer_mode+set}" = "set"], [
    AS_IF([test "x${enable_developer_mode}" = "xno"], [
      AC_MSG_WARN([--disable-developer-mode given; DEVELOPER_CACHE ignored])]
    )], [
    AC_MSG_WARN([============================================================================])
    AC_MSG_WARN([DEVELOPER_CACHE specified: developer mode has been automatically enabled])
    AC_MSG_WARN([============================================================================])
    AC_SUBST(DEVELOPER,true)])], [AC_SUBST(DEVELOPER_CACHE,"~/.opam-cache")])
DEVELOPER_CACHE=$(echo ${DEVELOPER_CACHE} | sed -e "s/\\\\/\\\\\\\\/g")
AC_SUBST(DEVELOPER_CACHE)

AS_IF([test "x${CI}" != "x" -o "x${enable_developer_mode}" = "xyes"], [
  CONF_OCAMLFLAGS="-warn-error A"
  AS_IF([test "x${CCOMP_TYPE}" = "xmsvc"],[CONF_CFLAGS=/WX],[CONF_CFLAGS=-Werror])
],[
  CONF_OCAMLFLAGS=
  CONF_CFLAGS=
])
AC_SUBST(CONF_OCAMLFLAGS)
AC_SUBST(CONF_CFLAGS)

AX_COMPARE_VERSION([$OCAMLVERSION], [ge], [4.02.0])
AC_SUBST(ocaml_4_02,"$ax_compare_version")
AX_COMPARE_VERSION([$OCAMLVERSION], [ge], [4.03.0])
AC_SUBST(ocaml_4_03,"$ax_compare_version")

AS_IF([ test "${OCAML_OS_TYPE}" = "Win32"],[
  WIN32=1
  EXE=.exe
],[
  EXE=
  WIN32=0
])

AC_SUBST(WIN32)
AC_SUBST(EXE)

AS_IF([ test ${WIN32} -eq 1 -a "$GCC" = "yes"],[
  CC="$CC -D inline=__inline__ -std=c89"
  AC_SUBST(CC)
])

AS_IF([ test ${WIN32} -eq 1 ],[
  AS_IF([ test "$GCC" = "yes"], [
    AS_IF([ test "x${CC64}" = "x" ], [
      AS_IF([ test "$ARCH" = "i386" ],[T_CC64=x86_64-w64-mingw32-gcc],[T_CC64=i686-w64-mingw32-gcc])])
    AC_CHECK_TOOL(CC64,[${T_CC64}],[no])
    AS_IF([ test "x${CC64}" != "xno" ],[
      CC64_JBUILD="(run ${CC64} -o \${@} -I ../core -D inline=__inline__ -std=c89 \${<})"
    ])
  ],[
    AC_MSG_CHECKING([whether Microsoft Linker needs a PATH shim])
    PREV_PREPEND="$PATH_PREPEND"
    PATH_PREPEND=$(bash ./shell/check_linker)
    AS_IF([test "x${PATH_PREPEND}" = "x${PREV_PREPEND}" ],[PATH_PREPEND_RESULT=no],[PATH_PREPEND_RESULT=yes])
    AC_SUBST(PATH_PREPEND)
    AC_SUBST(LIB_PREPEND)
    AC_SUBST(INC_PREPEND)
    AC_MSG_RESULT([$PATH_PREPEND_RESULT])
    AS_IF([ test "$ARCH" = "i386" ],[COMP_ARCH=x64],[COMP_ARCH=x86])
    AC_MSG_CHECKING([for a way to invoke an $COMP_ARCH C compiler])
    eval `PATH="$PRE_BOOTSTRAP_PATH" ./shell/msvs-detect --arch=$COMP_ARCH`
    AS_IF([ test "x$MSVS_NAME" = "x" ], [
      AC_MSG_RESULT([no])
      CC64=no
    ],[
      AC_MSG_RESULT([from $MSVS_NAME])
      CL_FULL="`PATH="${MSVS_PATH}:${PATH}" which cl | cygpath -f - -w`"
      MSVS_PATH="`echo "${MSVS_PATH}" | cygpath -f - -wp`"
      CC64_JBUILD="(setenv PATH \"${MSVS_PATH}\" (setenv LIB \"${MSVS_LIB};${LIB}\" (setenv INCLUDE \"${MSVS_INC};${INCLUDE}\" (run \"${CL_FULL}\" /nologo /Fe\${@} /I../core \${<}))))"
    ])
  ])
  AS_IF([ test "x${CC64}" = "xno" ],[
    AC_MSG_WARN([Complementary C compiler not found - opam-putenv will not be built])
    BUILD_PUTENV=0
    CC64_JBUILD=
  ],[
    BUILD_PUTENV=1
  ])
],[
  BUILD_PUTENV=0
  CC64_JBUILD=
])
AC_SUBST(BUILD_PUTENV)
AC_SUBST(CC64_JBUILD)

AC_PROG_FINDLIB

AC_ARG_ENABLE([certificate_check],
  AS_HELP_STRING([--disable-certificate-check],
                 [Do not check the certificate of opam's dependency archives])
)

AS_IF([test "x${enable_certificate_check}" = "xno"], [
  curl_certificate_check=--insecure
  wget_certificate_check=--no-check-certificate
])

AC_CHECK_PROGS(FETCH,[curl wget],no)

AC_CHECK_TOOL(JBUILDER,jbuilder)

if test x"$FETCH" = x"curl" ; then
  AC_SUBST(fetch, "curl $curl_certificate_check -L -o \$(2) \$(1)")
elif test x"$FETCH" = x"wget" ; then
  AC_SUBST(fetch, "wget $wget_certificate_check -O \$(2) \$(1)")
elif test x"${enable_checks}" != x"no" ; then
  AC_MSG_ERROR([You must have either curl or wget installed.])
fi

echo

AC_CHECK_OCAML_PKG([unix])
AC_CHECK_OCAML_PKG([bigarray])
AC_CHECK_OCAML_PKG([extlib])
AC_CHECK_OCAML_PKG([re])
AC_CHECK_OCAML_PKG([re.glob])
AC_CHECK_OCAML_PKG([re.posix])
AC_CHECK_OCAML_PKG([cmdliner])
AC_CHECK_OCAML_PKG([ocamlgraph])
AC_CHECK_OCAML_PKG([cudf])
AC_CHECK_OCAML_PKG(dose3.common,dose.common)
AC_CHECK_OCAML_PKG(dose3.algo,dose.algo)
AC_CHECK_OCAML_PKG([opam-file-format])

dnl echo
dnl echo "extlib........................ ${OCAML_PKG_extlib}"
dnl echo "re............................ ${OCAML_PKG_re}"
dnl echo "cmdliner...................... ${OCAML_PKG_cmdliner}"
dnl echo "graph......................... ${OCAML_PKG_ocamlgraph}"
dnl echo "cudf.......................... ${OCAML_PKG_cudf}"
dnl echo "dose3......................... ${OCAML_PKG_dose3}"
echo


AS_IF([test "x${enable_checks}" != "xno" && {
       test "x$OCAML_PKG_extlib" = "xno" ||
       test "x$OCAML_PKG_re" = "xno" ||
       test "x$OCAML_PKG_cmdliner" = "xno" ||
       test "x$OCAML_PKG_ocamlgraph" = "xno" ||
       test "x$OCAML_PKG_cudf" = "xno" ||
       test "x$OCAML_PKG_dose3_common" = "xno" ||
       test "x$OCAML_PKG_opam_file_format" = "xno"; }],[
  echo "============================================================================"
  echo "Some dependencies are missing. If you are just interested in the stand-alone"
  echo "'opam' binary, run 'make lib-ext' to download and include them."
  echo "============================================================================"
  echo
  AC_SUBST(hasalldeps,"")
],[
  AC_SUBST(hasalldeps,"true")
])

if test "x$prefix" = "xNONE"; then
  prefix=$ac_default_prefix
fi

AC_CONFIG_FILES(
  Makefile.config
  src/cc64.sexp
)
AC_OUTPUT

echo

bindir="`eval echo ${bindir}`"
bindir="`eval echo ${bindir}`"
mandir="`eval echo ${mandir}`"
mandir="`eval echo ${mandir}`"

echo Executables will be installed in ${bindir}
echo Manual pages will be installed in ${mandir}
