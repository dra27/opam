/**************************************************************************/
/*                                                                        */
/*    Copyright 2015, 2016 MetaStack Solutions Ltd.                       */
/*                                                                        */
/*  This file is distributed under the terms of the GNU General Public    */
/*  License version 3.0                                                   */
/*                                                                        */
/*  OPAM is distributed in the hope that it will be useful, but WITHOUT   */
/*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    */
/*  or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public       */
/*  License for more details.                                             */
/*                                                                        */
/**************************************************************************/

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

static HKEY roots[] = {HKEY_CLASSES_ROOT, HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, HKEY_USERS};

CAMLprim value OPAMW_GetCurrentProcessID(value unit)
{
  CAMLparam1(unit);

  CAMLreturn(Val_int(GetCurrentProcessId()));
}

CAMLprim value OPAMW_GetStdHandle(value nStdHandle)
{
  CAMLparam1(nStdHandle);
  CAMLlocal1(result);

  HANDLE hResult;

  if ((hResult = GetStdHandle(Int_val(nStdHandle))) == NULL)
    caml_raise_not_found();

  result = caml_alloc_custom(&HandleOps, sizeof(HANDLE), 0, 1);
  HANDLE_val(result) = hResult;

  CAMLreturn(result);
}

CAMLprim value OPAMW_GetConsoleScreenBufferInfo(value hConsoleOutput)
{
  CAMLparam1(hConsoleOutput);
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

  CAMLreturn(result);
}

CAMLprim value OPAMW_SetConsoleTextAttribute(value hConsoleOutput, value wAttributes)
{
  CAMLparam2(hConsoleOutput, wAttributes);

  if (!SetConsoleTextAttribute(HANDLE_val(hConsoleOutput), Int_val(wAttributes)))
    caml_failwith("setConsoleTextAttribute");

  CAMLreturn(Val_unit);
}

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

CAMLprim value OPAMW_IsWoW64(value unit)
{
  CAMLparam1(unit);

  CAMLreturn(Val_bool(CurrentProcessIsWoW64()));
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

/*
 * Adapted from otherlibs/win32unix/winwait.c win_waitpid
 */
CAMLprim value OPAMW_waitpids(value vpid_reqs, value vpid_len)
{
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
}

CAMLprim value OPAMW_WriteRegistry(value hKey, value lpSubKey, value lpValueName, value dwType, value lpData)
{
  CAMLparam5(hKey, lpSubKey, lpValueName, dwType, lpData);

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

  CAMLreturn(Val_unit);
}

CAMLprim value OPAMW_GetConsoleOutputCP(value unit)
{
  CAMLparam1(unit);

  CAMLreturn(Val_int(GetConsoleOutputCP()));
}

CAMLprim value OPAMW_SetConsoleOutputCP(value wCodePageID)
{
  CAMLparam1(wCodePageID);

  CAMLreturn(Val_bool(SetConsoleOutputCP(Int_val(wCodePageID))));
}

CAMLprim value OPAMW_SetConsoleCP(value wCodePageID)
{
  CAMLparam1(wCodePageID);

  CAMLreturn(Val_bool(SetConsoleCP(Int_val(wCodePageID))));
}

CAMLprim value OPAMW_output(value hConsoleOutput, value str)
{
  CAMLparam2(hConsoleOutput, str);

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

  CAMLreturn(Val_unit);
}

CAMLprim value OPAMW_GetCurrentConsoleFontEx(value hConsoleOutput, value bMaximumWindow)
{
  CAMLparam2(hConsoleOutput, bMaximumWindow);
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

  CAMLreturn(result);
}

CAMLprim value OPAMW_WideCharToMultiByte(value codePage, value flags, value str)
{
  CAMLparam3(codePage, flags, str);
  CAMLlocal1(result);

  UINT CodePage = Int_val(codePage);
  DWORD dwFlags = Int_val(flags);
  LPCWSTR lpWideCharStr = (LPCWSTR)String_val(str);
  int cbMultiByte = caml_string_length(str) / 2;

  int len = WideCharToMultiByte(CodePage, dwFlags, lpWideCharStr, cbMultiByte, NULL, 0, NULL, NULL);
  result = caml_alloc_string(len);
  WideCharToMultiByte(CodePage, dwFlags, lpWideCharStr, cbMultiByte, String_val(result), len, NULL, NULL);

  CAMLreturn(result);
}

CAMLprim value OPAMW_CheckGlyphs(value fontName, value glyphList, value length)
{
  CAMLparam3(fontName, glyphList, length);
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

  CAMLreturn(result);
}

/*
 * Somewhat against my better judgement, wrap SHGetFolderPath rather than SHGetKnownFolderPath to maintain XP compatibility.
 * OPAM already requires Windows Vista+ because of GetCurrentConsoleFontEx, but there may be a workaround for that for XP lusers.
 */
CAMLprim value OPAMW_SHGetFolderPath(value nFolder, value dwFlags)
{
  CAMLparam2(nFolder, dwFlags);
  CAMLlocal1(result);
  TCHAR szPath[MAX_PATH];

  if (SUCCEEDED(SHGetFolderPath(NULL, Int_val(nFolder), NULL, Int_val(dwFlags), szPath)))
    result = caml_copy_string(szPath);
  else
    caml_failwith("OPAMW_SHGetFolderPath");

  CAMLreturn(result);
}

CAMLprim value OPAMW_SendMessageTimeout(value hWnd, value uTimeout, value fuFlags, value msg, value wParam, value lParam)
{
  CAMLparam5(hWnd, msg, wParam, lParam, fuFlags);
  CAMLxparam1(uTimeout);
  CAMLlocal1(result);

  DWORD dwReturnValue;
  HRESULT lResult;
  WPARAM rwParam;
  LPARAM rlParam;
  UINT rMsg;

  switch (Int_val(msg))
  {
    case 0:
      {
        rMsg = WM_SETTINGCHANGE;
        rwParam = Int_val(wParam);
        rlParam = (LPARAM)String_val(lParam);
        break;
      }
    default:
      {
        caml_failwith("OPAMW_SendMessageTimeout: message not implemented");
        break;
      }
  }

  lResult = SendMessageTimeout((HWND)Int_val(hWnd), rMsg, rwParam, rlParam, Int_val(fuFlags), Int_val(uTimeout), &dwReturnValue);

  switch (Int_val(msg))
  {
    case 0:
      {
        result = caml_alloc(2, 0);
        Store_field(result, 0, Val_int(lResult));
        Store_field(result, 1, Val_int(dwReturnValue));
        break;
      }
  }

  CAMLreturn(result);
}

CAMLprim value OPAMW_SendMessageTimeout_byte(value * argv, int argn)
{
  return OPAMW_SendMessageTimeout(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

/*
 * OPAMW_parent_putenv is implemented using Process Injection.
 * Idea inspired by Bill Stewart's editvar (http://www.westmesatech.com/editv.html)
 * Full technical details at http://www.codeproject.com/Articles/4610/Three-Ways-to-Inject-Your-Code-into-Another-Proces#section_3
 */

static char* getProcessInfo(HANDLE hProcessSnapshot, DWORD processId, PROCESSENTRY32 *entry)
{
  entry->dwSize = sizeof(PROCESSENTRY32);

  if (hProcessSnapshot == INVALID_HANDLE_VALUE)
    return "getProcessInfo: could not create snapshot";

  /*
   * Locate our process
   */
  if (!Process32First(hProcessSnapshot, entry))
  {
    CloseHandle(hProcessSnapshot);
    return "getProcessInfo: could not walk process tree";
  }
  else
  {
    while (entry->th32ProcessID != processId)
    {
      if (!Process32Next(hProcessSnapshot, entry))
      {
        CloseHandle(hProcessSnapshot);
        return "getProcessInfo: could not find process!";
      }
    }
  }

  return NULL;
}

CAMLprim value OPAMW_GetParentProcess(value parent_of_parent)
{
  CAMLparam1(parent_of_parent);

  PROCESSENTRY32 entry;
  char* msg;
  /*
   * Create a Toolhelp Snapshot of running processes
   */
  HANDLE hProcessSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

  msg = getProcessInfo(hProcessSnapshot, GetCurrentProcessId(), &entry);
  if (!msg && Bool_val(parent_of_parent))
    msg = getProcessInfo(hProcessSnapshot, entry.th32ParentProcessID, &entry);
  if (msg)
    caml_failwith(msg);

  /*
   * Finished with the snapshot
   */
  CloseHandle(hProcessSnapshot);

  CAMLreturn(caml_copy_int32(entry.th32ParentProcessID));
}

char* InjectSetEnvironmentVariable(DWORD pid, char* key, char* val);

CAMLprim value OPAMW_parent_putenv(value pid, value key, value val)
{
  CAMLparam3(pid, key, val);
  CAMLlocal1(res);

  char* result;

  /*
   * MSDN is all over the place as to what the technical limits are for environment variables
   * (looks like 32KiB for both both name and value) however there's no need to inject 64KiB
   * data each time - hence 4KiB "limit".
   */
  if (caml_string_length(key) > 4095 || caml_string_length(val) > 4095)
    caml_invalid_argument("Strings too long");

  result = InjectSetEnvironmentVariable(Int32_val(pid), String_val(key), String_val(val));

  if (result == NULL)
  {
    res = Val_true;
  }
  else if (strlen(result) == 0)
  {
    res = Val_false;
  }
  else
  {
    caml_failwith(result);
  }

  CAMLreturn(res);
}

CAMLprim value OPAMW_IsWoW64Mismatch(value pid)
{
  CAMLparam1(pid);

  BOOL pidWoW64 = CurrentProcessIsWoW64();
  BOOL ppidWoW64 = FALSE;
  HANDLE hProcess;

  if (IsWoW64Process)
  {
    if ((hProcess = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, Int32_val(pid))))
    {
      IsWoW64Process(hProcess, &ppidWoW64);
      CloseHandle(hProcess);
    }
  }

  CAMLreturn(Val_bool(pidWoW64 != ppidWoW64));
}

CAMLprim value OPAMW_GetConsoleAlias(value alias, value exeName)
{
  CAMLparam2(alias, exeName);
  CAMLlocal1(result);

  DWORD nLength = 8192;
  LPTSTR buffer = (LPTSTR)malloc(nLength);

  if (!buffer)
    caml_raise_out_of_memory();

  if (GetConsoleAlias(String_val(alias), buffer, nLength, String_val(exeName)))
  {
    result = caml_copy_string(buffer);
  }
  else
  {
    result = caml_copy_string("");
  }

  free(buffer);

  CAMLreturn(result);
}

/* These empty stubs are required for Unix only
CAMLprim value win_create_process_native(value cmd, value cmdline, value env, value fd1, value fd2, value fd3)
{
  CAMLparam5(cmd, cmdline, env, fd1, fd2); CAMLxparam1(fd3);

CAMLprim value win_create_process(value * argv, int argn)
{

*/
