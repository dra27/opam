/**************************************************************************/
/*                                                                        */
/*    Copyright 2015, 2016, 2017 MetaStack Solutions Ltd.                 */
/*                                                                        */
/*  All rights reserved. This file is distributed under the terms of the  */
/*  GNU Lesser General Public License version 2.1, with the special       */
/*  exception on linking described in the file LICENSE.                   */
/*                                                                        */
/**************************************************************************/

#define CAML_NAME_SPACE
#include <stdio.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/alloc.h>
#include <caml/custom.h>

#ifdef _WIN32

#include <Windows.h>

static struct custom_operations HandleOps =
{
  "org.ocaml.opam.Win32.Handle/1",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

#define HANDLE_val(v) (*((HANDLE*)Data_custom_val(v)))

typedef BOOL (WINAPI *LPFN_ISWOW64PROCESS) (HANDLE, PBOOL);

static LPFN_ISWOW64PROCESS IsWoW64Process = NULL;

static BOOL CurrentProcessIsWoW64(void)
{
  /*
   * 32-bit versions may or may not have IsWow64Process (depends on age). Recommended way is to use
   * GetProcAddress to obtain IsWow64Process, rather than relying on Windows.h.
   * See http://msdn.microsoft.com/en-gb/library/windows/desktop/ms684139.aspx
   */
  if (IsWoW64Process || (IsWoW64Process = (LPFN_ISWOW64PROCESS)GetProcAddress(GetModuleHandle("kernel32"), "IsWow64Process")))
  {
    BOOL output;
    if (IsWoW64Process(GetCurrentProcess(), &output))
      return output;
  }

  return FALSE;
}

#define OPAMreturn CAMLreturn

#else

#define OPAMreturn(v) CAMLreturn(Val_unit)

#endif

/* Actual primitives from here */
CAMLprim value OPAMW_GetCurrentProcessID(value unit)
{
  CAMLparam1(unit);

  OPAMreturn(Val_int(GetCurrentProcessId()));
}

CAMLprim value OPAMW_GetStdHandle(value nStdHandle)
{
  CAMLparam1(nStdHandle);
#ifdef _WIN32
  CAMLlocal1(result);

  HANDLE hResult;

  if ((hResult = GetStdHandle(Int_val(nStdHandle))) == NULL)
    caml_raise_not_found();

  result = caml_alloc_custom(&HandleOps, sizeof(HANDLE), 0, 1);
  HANDLE_val(result) = hResult;
#endif

  OPAMreturn(result);
}

CAMLprim value OPAMW_GetConsoleScreenBufferInfo(value hConsoleOutput)
{
  CAMLparam1(hConsoleOutput);
#ifdef _WIN32
  CAMLlocal2(result, coord);

  CONSOLE_SCREEN_BUFFER_INFO buffer;

  if (!GetConsoleScreenBufferInfo(HANDLE_val(hConsoleOutput), &buffer))
    caml_raise_not_found();

  result = caml_alloc(5, 0);
  coord = caml_alloc(2, 0);
  Store_field(coord, 0, Val_int(buffer.dwSize.X));
  Store_field(coord, 1, Val_int(buffer.dwSize.Y));
  Store_field(result, 0, coord);
  coord = caml_alloc(2, 0);
  Store_field(coord, 0, Val_int(buffer.dwCursorPosition.X));
  Store_field(coord, 1, Val_int(buffer.dwCursorPosition.Y));
  Store_field(result, 1, coord);
  Store_field(result, 2, Val_int(buffer.wAttributes));
  coord = caml_alloc(4, 0);
  Store_field(coord, 0, Val_int(buffer.srWindow.Left));
  Store_field(coord, 1, Val_int(buffer.srWindow.Top));
  Store_field(coord, 2, Val_int(buffer.srWindow.Right));
  Store_field(coord, 3, Val_int(buffer.srWindow.Bottom));
  Store_field(result, 3, coord);
  coord = caml_alloc(2, 0);
  Store_field(coord, 0, Val_int(buffer.dwMaximumWindowSize.X));
  Store_field(coord, 1, Val_int(buffer.dwMaximumWindowSize.Y));
  Store_field(result, 4, coord);
#endif

  OPAMreturn(result);
}

CAMLprim value OPAMW_SetConsoleTextAttribute(value hConsoleOutput, value wAttributes)
{
  CAMLparam2(hConsoleOutput, wAttributes);

#ifdef _WIN32
  if (!SetConsoleTextAttribute(HANDLE_val(hConsoleOutput), Int_val(wAttributes)))
    caml_failwith("setConsoleTextAttribute");
#endif

  OPAMreturn(Val_unit);
}

CAMLprim value OPAMW_IsWoW64(value unit)
{
  CAMLparam1(unit);

  OPAMreturn(Val_bool(CurrentProcessIsWoW64()));
}
