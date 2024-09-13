/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           */
/*                                                                        */
/*   Copyright 1996 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/signals.h>
#define CAML_INTERNALS
#include <caml/osdeps.h>
#include <caml/unixsupport.h>
#include <fcntl.h>

#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

#if OCAML_VERSION < 50000
#define caml_uerror uerror
#endif

CAMLprim value opam_check_executable(value path)
{
  CAMLparam1(path);
  char_os * p;
  int ret;

  caml_unix_check_path(path, "faccessat");
  p = caml_stat_strdup_to_os(String_val(path));
  caml_enter_blocking_section();
#ifdef _WIN32
  ret = _waccess(p, 04);
#else
  ret = faccessat(AT_FDCWD, p, R_OK | X_OK, AT_EACCESS);
#endif
  caml_leave_blocking_section();
  caml_stat_free(p);
  if (ret == -1)
    caml_uerror("faccessat", path);
  CAMLreturn(Val_unit);
}

/* This is done here as it simplifies the dune file */
#ifdef _WIN32
#include "opamInject.c"
#include "opamWindows.c"
#endif
