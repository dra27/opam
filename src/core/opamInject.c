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

#ifdef _WIN32

#include <Windows.h>

/* SetEnvironmentVariable function pointer type */
typedef LRESULT (WINAPI *SETENVIRONMENTVARIABLE)(LPCTSTR,LPCTSTR);

/*
 * Data structure to pass to the remote thread
 */
typedef struct {
  SETENVIRONMENTVARIABLE SetEnvironmentVariable;
  TCHAR lpName[4096];
  TCHAR lpValue[4096];
  BOOL result;
} INJDATA, *PINJDATA;

/*
 * Code to inject into the parent process
 */
static DWORD WINAPI ThreadFunc (INJDATA *pData)
{
  /*
   * Call the provided function pointer with its two arguments and return the result
   */
  pData->result = pData->SetEnvironmentVariable(pData->lpName, pData->lpValue);

  return 0;
}

/*
 * This is a dummy function used to calculate the code size of ThreadFunc.
 * This assumes that the linker does not re-order the functions.
 *   If it's a worry, could make the symbols public and use /ORDER (http://msdn.microsoft.com/en-us/library/00kh39zz.aspx)
 *   Presumably there's a gcc equivalent for mingw.
 */
static void AfterThreadFunc (void)
{
  return;
}

char* InjectSetEnvironmentVariable(DWORD pid, char* key, char* val)
{
  /*
   * Open the parent process for code injection
   */
  HANDLE hProcess = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ, FALSE, pid);
  INJDATA payload = {NULL, "", "", FALSE};
  INJDATA* pData;
  DWORD* pCode;
  const int codeSize = ((LPBYTE)AfterThreadFunc - (LPBYTE)ThreadFunc);
  HANDLE hThread;

  if (!hProcess)
    return "OPAMW_parent_putenv: could not open parent process";

  payload.SetEnvironmentVariable = (SETENVIRONMENTVARIABLE)GetProcAddress(GetModuleHandle("kernel32"), "SetEnvironmentVariableA");

  /*
   * Set-up the instruction
   */
  strcpy(payload.lpName, key);
  strcpy(payload.lpValue, val);

  /*
   * Allocate a page in the parent process to hold the instruction and copy payload to it
   */
  pData = (INJDATA*)VirtualAllocEx(hProcess, 0, sizeof(INJDATA), MEM_COMMIT, PAGE_READWRITE);
  if (!pData)
  {
    CloseHandle(hProcess);
    return "OPAMW_parent_putenv: could not allocate page in parent process";
  }
  if (!WriteProcessMemory(hProcess, pData, &payload, sizeof(INJDATA), NULL))
  {
    VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
    CloseHandle(hProcess);
    return "OPAMW_parent_putenv: could not copy data to parent process";
  }

  /*
   * Allocate a page in the parent process to hold ThreadFunc and copy the code there
   */
  pCode = (PDWORD)VirtualAllocEx(hProcess, 0, codeSize, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
  if (!pCode)
  {
    VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
    CloseHandle(hProcess);
    return "OPAMW_parent_putenv: could not allocate executable page in parent process";
  }
  if (!WriteProcessMemory(hProcess, pCode, &ThreadFunc, codeSize, NULL))
  {
    VirtualFreeEx(hProcess, pCode, 0, MEM_RELEASE);
    VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
    CloseHandle(hProcess);
    return "OPAMW_parent_putenv: could not copy code to parent process";
  }

  /*
   * Start the remote thread
   */
  hThread = CreateRemoteThread(hProcess, NULL, 0, (LPTHREAD_START_ROUTINE)pCode, pData, 0, NULL);
  if (!hThread)
  {
    VirtualFreeEx(hProcess, pCode, 0, MEM_RELEASE);
    VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
    CloseHandle(hProcess);
    return "OPAMW_parent_putenv: could not start remote thread in parent";
  }

  /*
   * Wait for the thread to terminate
   * Intentionally not releasing the OCaml runtime lock (i.e. I haven't considered if it's safe to do so!)
   */
  WaitForSingleObject(hThread, INFINITE);
  CloseHandle(hThread);

  /*
   * Get the result back
   */
  ReadProcessMemory(hProcess, pData, &payload, sizeof(INJDATA), NULL);

  /*
   * Release the memory
   */
  VirtualFreeEx(hProcess, pCode, 0, MEM_RELEASE);
  VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
  CloseHandle(hProcess);

  return (payload.result ? NULL : "");
}

#endif
