unit uWLXExports;

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, listplug, uWLXTypes;

function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
procedure ListCloseWindow(ListWin: HWND); stdcall;
procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
procedure ListSetDefaultParams(dps: PListDefaultParamStruct); stdcall;
function ListSendCommand(ListWin: HWND; Command, Parameter: Integer): Integer; stdcall;
function ListSearchText(ListWin: HWND; SearchString: PAnsiChar; SearchParameter: Integer): Integer; stdcall;
function ListSearchTextW(ListWin: HWND; SearchString: PWideChar; SearchParameter: Integer): Integer; stdcall;
function ListSearchDialog(ListWin: HWND; FindNext: Integer): Integer; stdcall;

implementation

uses
  uSettings, uWin32LogWindow;

const
  DETECT_STRING =
    'EXT="LOG" | EXT="TXT" | EXT="OUT" | EXT="ERR" | EXT="TRACE" | EXT="CSV" | ' +
    'FIND="[ERROR]" | FIND="[WARN]" | FIND="INFO"';

var
  GSettingsLoaded: Boolean = False;

procedure EnsureSettingsLoaded;
var
  Buf: array[0..MAX_PATH - 1] of WideChar;
  S: string;
begin
  if GSettingsLoaded then
    Exit;
  GSettingsLoaded := True;

  FillChar(Buf, SizeOf(Buf), 0);
  GetModuleFileNameW(hInstance, Buf, MAX_PATH);
  S := string(WideString(Buf));
  GPluginDir := ExtractFilePath(S);
  LoadSettings;
end;

function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
begin
  EnsureSettingsLoaded;
  Result := CreateLogViewWindow(ParentWin, string(FileToLoad), ShowFlags);
end;

function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
begin
  EnsureSettingsLoaded;
  Result := CreateLogViewWindow(ParentWin, string(WideString(FileToLoad)), ShowFlags);
end;

procedure ListCloseWindow(ListWin: HWND); stdcall;
begin
  DestroyLogViewWindow(ListWin);
end;

procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
begin
  StrLCopy(DetectString, PAnsiChar(AnsiString(DETECT_STRING)), MaxLen - 1);
end;

procedure ListSetDefaultParams(dps: PListDefaultParamStruct); stdcall;
begin
  EnsureSettingsLoaded;
end;

function ListSendCommand(ListWin: HWND; Command, Parameter: Integer): Integer; stdcall;
begin
  Result := SendLogViewCommand(ListWin, Command, Parameter);
end;

function ListSearchText(ListWin: HWND; SearchString: PAnsiChar; SearchParameter: Integer): Integer; stdcall;
begin
  if SearchString <> nil then
    Result := SearchLogViewText(ListWin, string(SearchString), SearchParameter)
  else
    Result := SearchLogViewText(ListWin, '', SearchParameter);
end;

function ListSearchTextW(ListWin: HWND; SearchString: PWideChar; SearchParameter: Integer): Integer; stdcall;
begin
  if SearchString <> nil then
    Result := SearchLogViewText(ListWin, string(WideString(SearchString)), SearchParameter)
  else
    Result := SearchLogViewText(ListWin, '', SearchParameter);
end;

function ListSearchDialog(ListWin: HWND; FindNext: Integer): Integer; stdcall;
begin
  Result := SearchLogViewDialog(ListWin, FindNext);
end;

end.
