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
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/signals.h>
#include <caml/unixsupport.h>

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

/*
 * Taken from otherlibs/win32unix/winwait.c (sadly declared static)
 * Altered only for CAML_NAME_SPACE
 */
static value alloc_process_status(HANDLE pid, int status)
{
  value res, st;

  st = caml_alloc(1, 0);
  Field(st, 0) = Val_int(status);
  Begin_root (st);
    res = caml_alloc_small(2, 0);
    Field(res, 0) = Val_long((intnat) pid);
    Field(res, 1) = st;
  End_roots();
  return res;
}

static HKEY roots[] = {HKEY_CLASSES_ROOT, HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, HKEY_USERS};

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

/*
 * Adapted from otherlibs/win32unix/winwait.c win_waitpid
 */
CAMLprim value OPAMW_waitpids(value vpid_reqs, value vpid_len)
{
#ifdef _WIN32
  int i;
  DWORD status, retcode;
  HANDLE pid_req;
  DWORD err = 0;
  int len = Int_val(vpid_len);
  HANDLE *lpHandles = (HANDLE*)malloc(sizeof(HANDLE) * len);
  value ptr = vpid_reqs;

  if (lpHandles == NULL)
    caml_raise_out_of_memory();

  for (i = 0; i < len; i++) {
    lpHandles[i] = (HANDLE)Long_val(Field(ptr, 0));
    ptr = Field(ptr, 1);
  }

  caml_enter_blocking_section();
  retcode = WaitForMultipleObjects(len, lpHandles, FALSE, INFINITE);
  if (retcode == WAIT_FAILED) err = GetLastError();
  caml_leave_blocking_section();
  if (err) {
    win32_maperr(err);
    uerror("waitpids", Nothing);
  }
  pid_req = lpHandles[retcode - WAIT_OBJECT_0];
  free(lpHandles);
  if (! GetExitCodeProcess(pid_req, &status)) {
    win32_maperr(GetLastError());
    uerror("waitpids", Nothing);
  }

  /*
   * NB Unlike in win_waitpid, it's not possible to have status == STILL_ACTIVE
   */
  CloseHandle(pid_req);
  return alloc_process_status(pid_req, status);
#else
  return Val_unit
#endif
}

CAMLprim value OPAMW_WriteRegistry(value hKey, value lpSubKey, value lpValueName, value dwType, value lpData)
{
  CAMLparam5(hKey, lpSubKey, lpValueName, dwType, lpData);

#ifdef _WIN32
  HKEY key;
  void* buf = NULL;
  DWORD cbData = 0;
  DWORD type = 0;

  switch (RegOpenKeyEx(roots[Int_val(hKey)], String_val(lpSubKey), 0, KEY_WRITE, &key))
  {
    case ERROR_SUCCESS:
      {
        switch (Int_val(dwType))
        {
          case 0:
            {
              buf = String_val(lpData);
              cbData = strlen(buf) + 1;
              type = REG_SZ;
              break;
            }
          default:
            {
              caml_failwith("OPAMW_WriteRegistry: value not implemented");
              break;
            }
        }
        if (RegSetValueEx(key, String_val(lpValueName), 0, type, (LPBYTE)buf, cbData) != ERROR_SUCCESS)
        {
          RegCloseKey(key);
          caml_failwith("RegSetValueEx");
        }
        RegCloseKey(key);
        break;
      }
    case ERROR_FILE_NOT_FOUND:
      {
        caml_raise_not_found();
        break;
      }
    default:
      {
        caml_failwith("RegOpenKeyEx");
        break;
      }
  }
#endif

  OPAMreturn(Val_unit);
}

CAMLprim value OPAMW_GetConsoleOutputCP(value unit)
{
  CAMLparam1(unit);

  OPAMreturn(Val_int(GetConsoleOutputCP()));
}

CAMLprim value OPAMW_SetConsoleOutputCP(value wCodePageID)
{
  CAMLparam1(wCodePageID);

  OPAMreturn(Val_bool(SetConsoleOutputCP(Int_val(wCodePageID))));
}

CAMLprim value OPAMW_SetConsoleCP(value wCodePageID)
{
  CAMLparam1(wCodePageID);

  OPAMreturn(Val_bool(SetConsoleCP(Int_val(wCodePageID))));
}

CAMLprim value OPAMW_output(value hConsoleOutput, value str)
{
  CAMLparam2(hConsoleOutput, str);

#ifdef _WIN32
  /*
   * FIXME dwWritten is the number of *characters* written, not bytes, so UTF-8 needs handling.
   *
   * It's unlikely, given that long debugging messages go via printf anyway, that WriteConsole won't
   * actually write everything in one go, hence ignoring dwWritten. It looks like the correct way is
   * to convert the string to UTF-16 using MultiByteToWideChar and then write it using WriteConsoleW
   * (where dwWritten will match up correctly with the length of the WSTR)
   */
  DWORD dwWritten;
  WriteConsole(HANDLE_val(hConsoleOutput), String_val(str), caml_string_length(str), &dwWritten, NULL);
#endif

  OPAMreturn(Val_unit);
}

CAMLprim value OPAMW_GetCurrentConsoleFontEx(value hConsoleOutput, value bMaximumWindow)
{
  CAMLparam2(hConsoleOutput, bMaximumWindow);
#ifdef _WIN32
  CAMLlocal3(result, coord, name);

  int len;
  CONSOLE_FONT_INFOEX fontInfo;
  fontInfo.cbSize = sizeof(fontInfo);

  if (GetCurrentConsoleFontEx(HANDLE_val(hConsoleOutput), Bool_val(bMaximumWindow), &fontInfo))
  {
    result = caml_alloc(5, 0);
    Store_field(result, 0, Val_int(fontInfo.nFont));
    coord = caml_alloc(2, 0);
    Store_field(coord, 0, Val_int(fontInfo.dwFontSize.X));
    Store_field(coord, 0, Val_int(fontInfo.dwFontSize.Y));
    Store_field(result, 1, coord);
    Store_field(result, 2, Val_int(fontInfo.FontFamily));
    Store_field(result, 3, Val_int(fontInfo.FontWeight));
    len = wcslen(fontInfo.FaceName) * 2;
    name = caml_alloc_string(len);
    memcpy(String_val(name), fontInfo.FaceName, len);
    Store_field(result, 4, name);
  }
  else
  {
    caml_raise_not_found();
  }
#endif

  OPAMreturn(result);
}

CAMLprim value OPAMW_WideCharToMultiByte(value codePage, value flags, value str)
{
  CAMLparam3(codePage, flags, str);
#ifdef _WIN32
  CAMLlocal1(result);

  UINT CodePage = Int_val(codePage);
  DWORD dwFlags = Int_val(flags);
  LPCWSTR lpWideCharStr = (LPCWSTR)String_val(str);
  int cbMultiByte = caml_string_length(str) / 2;

  int len = WideCharToMultiByte(CodePage, dwFlags, lpWideCharStr, cbMultiByte, NULL, 0, NULL, NULL);
  result = caml_alloc_string(len);
  WideCharToMultiByte(CodePage, dwFlags, lpWideCharStr, cbMultiByte, String_val(result), len, NULL, NULL);
#endif

  OPAMreturn(result);
}

CAMLprim value OPAMW_CheckGlyphs(value fontName, value glyphList, value length)
{
  CAMLparam3(fontName, glyphList, length);
#ifdef _WIN32
  CAMLlocal3(result, tail, cell);

  int l = Int_val(length);
  HDC hDC;
  char* failed = NULL;

  if (l <= 0)
    caml_invalid_argument("OPAMW_CheckGlyphs: bad length");

  /*
   * We just need any device context in which to load the font, so use the Screen DC
   */
  hDC = GetDC(NULL);

  if (hDC)
  {
    HFONT hFont = CreateFontW(0, 0, 0, 0, FW_DONTCARE, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH, (LPCWSTR)String_val(fontName));

    if (hFont)
    {
      if (SelectObject(hDC, hFont))
      {
        LPWSTR testString = (LPWSTR)malloc(l * 2);
        LPWORD indices = (LPWORD)malloc(l * sizeof(WORD));
        LPWSTR cur = testString;
        DWORD converted;

        cell = glyphList;
        do
        {
          *cur++ = (WCHAR)Int_val(Field(cell, 0));
          cell = Field(cell, 1);
        }
        while (Is_block(cell));

        converted = GetGlyphIndicesW(hDC, testString, l, indices, GGI_MARK_NONEXISTING_GLYPHS);
        if (converted == l)
        {
          int i = 0;
          LPWORD ptr = indices;
          tail = result = caml_alloc(2, 0);
          while (i++ < l)
          {
            cell = caml_alloc(2, 0);
            Store_field(cell, 0, Val_bool(*ptr++ != 0xffff));
            Store_field(tail, 1, cell);
            tail = cell;
          }
          Store_field(cell, 1, Val_int(0));
          result = Field(result, 1);
        }
        else
        {
          if (converted == GDI_ERROR)
          {
            failed = "OPAMW_CheckGlyphs: GetGlyphIndicesW";
          }
          else
          {
            failed = "OPAMW_CheckGlyphs: GetGlyphIndicesW (unexpected return)";
          }
        }

        free(indices);
        free(testString);
      }
      else
      {
        failed = "OPAMW_CheckGlyphs: SelectObject";
      }

      DeleteObject(hFont);
    }
    else
    {
      failed = "OPAMW_CheckGlyphs: CreateFontW";
    }

    ReleaseDC(NULL, hDC);
  }
  else
  {
    failed = "OPAMW_CheckGlyphs: GetDC";
  }

  if (failed)
    caml_failwith(failed);
#endif

  OPAMreturn(result);
}
