unit uWin32LogWindow;

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, listplug;

function CreateLogViewWindow(ParentWin: HWND; const FilePath: string; ShowFlags: Integer = 0): HWND;
procedure DestroyLogViewWindow(Wnd: HWND);
function SendLogViewCommand(Wnd: HWND; Command, Parameter: Integer): Integer;
function SearchLogViewText(Wnd: HWND; const SearchString: string; SearchParameter: Integer): Integer;
function SearchLogViewDialog(Wnd: HWND; FindNext: Integer): Integer;

implementation

uses
  Messages, Classes, Math, DateUtils, CommCtrl, uLogTypes, uLogModel, uLogLoader, uLogParser,
  uSettings, uPluginOptions;

const
  LOGVIEW_WNDCLASS = 'WLXLogViewer64Window';
  LOGVIEW_WRAPVIEW_WNDCLASS = 'WLXLogViewer64WrapView';
  IDC_LOG_LIST = 1001;
  IDC_BTN_PREV_ERR = 1101;
  IDC_BTN_NEXT_ERR = 1102;
  IDC_BTN_PREV_WARN = 1103;
  IDC_BTN_NEXT_WARN = 1104;
  IDC_BTN_PREV_INFO = 1105;
  IDC_BTN_NEXT_INFO = 1106;
  IDC_CHK_TAIL = 1107;
  IDC_CHK_FOLLOW = 1108;
  IDC_EDT_SEARCH = 1109;
  IDC_BTN_CLEAR = 1110;
  IDC_BTN_OPTIONS = 1111;
  IDC_CHK_LINENUM = 1112;
  IDC_BTN_COPY = 1113;
  IDC_STATUS = 1114;
  IDM_CTX_COPYLINE = 1201;
  IDM_CTX_COPYVISIBLE = 1202;
  IDM_CTX_LINENUM = 1203;
  IDM_CTX_WORDWRAP = 1204;
  IDM_CTX_GOTODT = 1205;
  IDM_CTX_GOTOLINE = 1206;

  TIMER_FILTER = 2101;
  TIMER_TAIL = 2102;
  FILTER_DEBOUNCE_MS = 120;
  TOOLBAR_H = 34;
  STATUS_H = 22;
  TOOLBAR_BG_COLOR: COLORREF = $00F0F0F0; // RGB(240,240,240)
  PROP_PARENT_STATE = 'WLX_LOGVIEW_PARENT_STATE';
  PROP_ESC_STATE = 'WLX_LOGVIEW_ESC_STATE';
  PROP_ESC_PREVPROC = 'WLX_LOGVIEW_ESC_PREVPROC';

type
  TIndexArray = array of Integer;

  TLogViewState = class
  public
    WindowHandle: HWND;
    ParentHandle: HWND;
    ListHandle: HWND;
    ShowFlags: Integer;
    IsListerMode: Boolean;
    FileName: string;
    FontHandle: HFONT;
    UiFontHandle: HFONT;
    OwnUiFont: Boolean;
    ItemHeight: Integer;
    CharWidth: Integer;
    Loaded: TLoadedLog;
    VisibleIdx: TIndexArray;
    VisibleCount: Integer;
    VisibleDirect: Boolean;
    MaxLineChars: Integer;
    SearchText: string;
    SearchTextLower: string;
    FollowTail: Boolean;
    TailActive: Boolean;
    TailFilePos: Int64;
    TailLineNo: Integer;
    TailPartial: AnsiString;

    BtnPrevErr: HWND;
    BtnNextErr: HWND;
    BtnPrevWarn: HWND;
    BtnNextWarn: HWND;
    BtnPrevInfo: HWND;
    BtnNextInfo: HWND;
    ChkTail: HWND;
    ChkFollow: HWND;
    ChkLineNum: HWND;
    LblSearch: HWND;
    EdtSearch: HWND;
    BtnClear: HWND;
    BtnOptions: HWND;
    StatusHandle: HWND;
    StatECount: Integer;
    StatWCount: Integer;
    StatICount: Integer;
    StatELast: TDateTime;
    StatWLast: TDateTime;
    StatILast: TDateTime;
    PrevListWndProc: WNDPROC;
    ParentPrevWndProc: WNDPROC;
    ParentSubclassed: Boolean;
    WrapHeights: array of Integer;
    WrapStamps: array of Integer;
    WrapStampToken: Integer;
    WrapCacheWidth: Integer;
    WrapMeasureDC: HDC;
    ListIsNoData: Boolean;
    ListIsViewport: Boolean;
    ViewTopIndex: Integer;
    ViewCaretIndex: Integer;
    ViewAnchorIndex: Integer;
    ViewSelected: array of Byte;
    ViewSelCapacity: Integer;
    LastSearchText: string;
    LastSearchFlags: Integer;

    constructor Create;
    destructor Destroy; override;
    procedure InitFont;
    function LoadFile: Boolean;
    procedure BuildToolbar;
    procedure EnsureListMode;
    procedure SyncListItems;
    procedure AppendVisibleItems(AAppendCount: Integer);
    procedure UpdateLayout;
    procedure UpdateListMetrics;
    procedure EnsureWrapCacheCapacity(ACount: Integer);
    procedure ResetWrapCache;
    function MeasureVisibleItemHeight(AVisibleIndex: Integer): Integer;
    function IsViewport: Boolean; inline;
    function ViewBaseVisibleCount: Integer;
    procedure UpdateViewScrollBars;
    procedure EnsureViewSelectionCapacity(ACount: Integer);
    procedure ClearViewSelection;
    function IsViewSelected(AIndex: Integer): Boolean;
    procedure SetViewSelected(AIndex: Integer; AValue: Boolean);
    procedure SetViewTopIndex(AIndex: Integer);
    procedure EnsureViewVisible(AIndex: Integer);
    function ViewIndexAtY(AY: Integer): Integer;
    procedure HandleViewMouseDown(X, Y: Integer; Shift: WPARAM);
    procedure HandleViewKeyDown(Key: WPARAM);
    procedure PaintViewport(DC: HDC);
    function GetTopIndex: Integer;
    procedure SetTopIndex(AIndex: Integer);
    procedure SelectAllVisible;
    function CurrentVisibleIndex: Integer;
    procedure SelectVisibleIndex(AVisibleIndex: Integer; ATopIndex: Boolean = True);
    function MapVisibleToRaw(AVisibleIndex: Integer): Integer;
    function RawLine(AVisibleIndex: Integer): string;
    procedure ApplyFilter(AKeepTopIndex: Boolean = False; ASelectDefaultFirst: Boolean = True);
    function LineText(AVisibleIndex: Integer): AnsiString;
    function BgColor(ALevel: TLogLevel): COLORREF;
    function FgColor(ALevel: TLogLevel): COLORREF;
    procedure ApplyColorRules(const AEntry: TLogEntry; var ALevel: TLogLevel; var ABg, AFg: COLORREF);
    function CopySelection: Boolean;
    function CopyCurrentLine: Boolean;
    function CopyAllVisible: Boolean;
    procedure GotoLevel(AForward: Boolean; ALevel: TLogLevel);
    procedure GotoLineNumber(ALine: Integer);
    procedure GotoDateTime(ADT: TDateTime);
    procedure StartTail;
    procedure StopTail;
    procedure TailTick;
    procedure AppendTailLine(const ALine: AnsiString);
    procedure ApplySettingsToControls;
    procedure UpdateStatusBar;
    procedure ShowContextMenu(X, Y: Integer);
    function FindText(const AText: string; AMatchCase, AWholeWords, ABackwards: Boolean;
      AFromCurrent: Boolean): Boolean;
  end;

  PPromptTextState = ^TPromptTextState;
  TPromptTextState = record
    EditHandle: HWND;
    Accepted: Boolean;
    Value: string;
  end;

  PPromptDateTimeState = ^TPromptDateTimeState;
  TPromptDateTimeState = record
    DateHandle: HWND;
    TimeHandle: HWND;
    Accepted: Boolean;
    Value: TDateTime;
  end;

function GetState(Wnd: HWND): TLogViewState; inline;
begin
  Result := TLogViewState(GetWindowLongPtr(Wnd, GWLP_USERDATA));
end;

function LowerAsciiByte(B: Byte): Byte; inline;
begin
  if (B >= Ord('A')) and (B <= Ord('Z')) then
    Result := B + 32
  else
    Result := B;
end;

function IsAsciiText(const S: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if Byte(S[I]) >= $80 then
      Exit(False);
  Result := True;
end;

function RawContainsTextCI(const P: PAnsiChar; RawLen: Integer; const NeedleLower: string): Boolean;
var
  I, J, NLen, LastStart: Integer;
  C, N: Byte;
begin
  NLen := Length(NeedleLower);
  if NLen = 0 then
    Exit(True);
  if (P = nil) or (RawLen < NLen) then
    Exit(False);

  LastStart := RawLen - NLen;
  for I := 0 to LastStart do
  begin
    J := 0;
    while J < NLen do
    begin
      C := Byte(P[I + J]);
      N := Byte(NeedleLower[J + 1]);
      if LowerAsciiByte(C) <> LowerAsciiByte(N) then
        Break;
      Inc(J);
    end;
    if J = NLen then
      Exit(True);
  end;
  Result := False;
end;

procedure DrawListItem(State: TLogViewState; DIS: PDrawItemStruct); forward;

function IsLikelyListerMode(ParentWin: HWND; ShowFlags: Integer): Boolean;
var
  Root: HWND;
  Style: PtrUInt;
begin
  if (ShowFlags and lcp_forceshow) <> 0 then
    Exit(True);
  Root := GetAncestor(ParentWin, GA_ROOT);
  if (ParentWin <> 0) and (Root = ParentWin) then
    Exit(True);
  Style := PtrUInt(GetWindowLongPtr(ParentWin, GWL_STYLE));
  Result := (Style and WS_POPUP) <> 0;
end;

function ResolveListerRoot(const State: TLogViewState): HWND; inline;
begin
  Result := 0;
  if State = nil then
    Exit;
  Result := GetAncestor(State.ParentHandle, GA_ROOT);
  if Result = 0 then
    Result := State.ParentHandle;
end;

function EscForwardWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  State: TLogViewState;
  Prev: WNDPROC;
  RootWnd: HWND;
begin
  State := TLogViewState(GetProp(Wnd, PChar(PROP_ESC_STATE)));
  Prev := WNDPROC(GetProp(Wnd, PChar(PROP_ESC_PREVPROC)));
  if (State <> nil) and State.IsListerMode and
     (((Msg = WM_KEYDOWN) or (Msg = WM_SYSKEYDOWN)) and (WParam = VK_ESCAPE) or
      ((Msg = WM_CHAR) and (WParam = 27))) then
  begin
    if AppSettings.CloseOnEscInLister then
    begin
      RootWnd := ResolveListerRoot(State);
      if RootWnd <> 0 then
      begin
        PostMessage(RootWnd, WM_KEYDOWN, VK_ESCAPE, LParam);
        PostMessage(RootWnd, WM_KEYUP, VK_ESCAPE, LParam);
      end;
    end;
    Result := 0;
    Exit;
  end;

  if Assigned(Prev) then
    Result := CallWindowProc(Prev, Wnd, Msg, WParam, LParam)
  else
    Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

procedure AttachEscForwarder(AHandle: HWND; AState: TLogViewState);
var
  Prev: WNDPROC;
begin
  if (AHandle = 0) or (AState = nil) or (not IsWindow(AHandle)) then
    Exit;
  if GetProp(AHandle, PChar(PROP_ESC_PREVPROC)) <> 0 then
    Exit;
  Prev := WNDPROC(SetWindowLongPtr(AHandle, GWLP_WNDPROC, PtrInt(@EscForwardWndProc)));
  SetProp(AHandle, PChar(PROP_ESC_PREVPROC), HANDLE(Prev));
  SetProp(AHandle, PChar(PROP_ESC_STATE), HANDLE(AState));
end;

procedure DetachEscForwarder(AHandle: HWND);
var
  Prev: WNDPROC;
begin
  if (AHandle = 0) or (not IsWindow(AHandle)) then
    Exit;
  Prev := WNDPROC(GetProp(AHandle, PChar(PROP_ESC_PREVPROC)));
  if Assigned(Prev) then
    SetWindowLongPtr(AHandle, GWLP_WNDPROC, PtrInt(Prev));
  RemoveProp(AHandle, PChar(PROP_ESC_PREVPROC));
  RemoveProp(AHandle, PChar(PROP_ESC_STATE));
end;

function ListerParentWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  State: TLogViewState;
begin
  State := TLogViewState(GetProp(Wnd, PChar(PROP_PARENT_STATE)));
  if (State <> nil) and State.IsListerMode and (not AppSettings.CloseOnEscInLister) then
  begin
    if ((Msg = WM_KEYDOWN) or (Msg = WM_SYSKEYDOWN)) and (WParam = VK_ESCAPE) then
      Exit(0);
    if (Msg = WM_CHAR) and (WParam = 27) then
      Exit(0);
    if (Msg = WM_COMMAND) and (LOWORD(WParam) = IDCANCEL) then
      Exit(0);
  end;
  if (State <> nil) and Assigned(State.ParentPrevWndProc) then
    Result := CallWindowProc(State.ParentPrevWndProc, Wnd, Msg, WParam, LParam)
  else
    Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

function LogListWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  State: TLogViewState;
  RootWnd: HWND;
begin
  State := TLogViewState(GetWindowLongPtr(Wnd, GWLP_USERDATA));
  if (State <> nil) and
     (((Msg = WM_KEYDOWN) or (Msg = WM_SYSKEYDOWN)) and (WParam = VK_F3)) then
  begin
    if State.LastSearchText <> '' then
    begin
      State.FindText(
        State.LastSearchText,
        (State.LastSearchFlags and lcs_matchcase) <> 0,
        (State.LastSearchFlags and lcs_wholewords) <> 0,
        (GetKeyState(VK_SHIFT) and $8000) <> 0,
        True
      );
      Exit(0);
    end;
    RootWnd := GetAncestor(State.ParentHandle, GA_ROOT);
    if RootWnd = 0 then
      RootWnd := State.ParentHandle;
    if RootWnd <> 0 then
    begin
      SendMessage(RootWnd, Msg, WParam, LParam);
      SendMessage(RootWnd, WM_KEYUP, WParam, LParam);
    end;
    Exit(0);
  end;
  if (State <> nil) and
     (((Msg = WM_KEYDOWN) or (Msg = WM_SYSKEYDOWN)) and
       (((WParam = VK_F) and ((GetKeyState(VK_CONTROL) and $8000) <> 0)) or
        (WParam = VK_F7))) then
  begin
    RootWnd := GetAncestor(State.ParentHandle, GA_ROOT);
    if RootWnd = 0 then
      RootWnd := State.ParentHandle;
    if RootWnd <> 0 then
    begin
      SendMessage(RootWnd, Msg, WParam, LParam);
      SendMessage(RootWnd, WM_KEYUP, WParam, LParam);
    end;
    Exit(0);
  end;
  if (State <> nil) and
     (((Msg = WM_KEYDOWN) or (Msg = WM_SYSKEYDOWN) or (Msg = WM_KEYUP) or (Msg = WM_SYSKEYUP)) and
      (WParam >= Ord('1')) and (WParam <= Ord('8'))) then
  begin
    RootWnd := GetAncestor(State.ParentHandle, GA_ROOT);
    if RootWnd = 0 then
      RootWnd := State.ParentHandle;
    if RootWnd <> 0 then
      PostMessage(RootWnd, Msg, WParam, LParam);
    Exit(0);
  end;
  if (State <> nil) and (Msg = WM_CHAR) and (WParam >= Ord('1')) and (WParam <= Ord('8')) then
  begin
    RootWnd := GetAncestor(State.ParentHandle, GA_ROOT);
    if RootWnd = 0 then
      RootWnd := State.ParentHandle;
    if RootWnd <> 0 then
      PostMessage(RootWnd, Msg, WParam, LParam);
    Exit(0);
  end;

  if Msg = WM_GETDLGCODE then
  begin
    if (State <> nil) and State.IsListerMode and (not AppSettings.CloseOnEscInLister) then
    begin
      if Assigned(State.PrevListWndProc) then
        Result := CallWindowProc(State.PrevListWndProc, Wnd, Msg, WParam, LParam) or DLGC_WANTALLKEYS
      else
        Result := DLGC_WANTALLKEYS;
    end
    else
    begin
      if (State <> nil) and Assigned(State.PrevListWndProc) then
        Result := CallWindowProc(State.PrevListWndProc, Wnd, Msg, WParam, LParam)
      else
        Result := 0;
    end;
    Exit;
  end;
  if (State <> nil) and State.IsListerMode and (not AppSettings.CloseOnEscInLister) then
  begin
    if ((Msg = WM_KEYDOWN) or (Msg = WM_SYSKEYDOWN)) and (WParam = VK_ESCAPE) then
      Exit(0);
    if (Msg = WM_CHAR) and (WParam = 27) then
      Exit(0);
  end;
  if (State <> nil) and State.IsListerMode and AppSettings.CloseOnEscInLister then
  begin
    if ((Msg = WM_KEYDOWN) or (Msg = WM_SYSKEYDOWN)) and (WParam = VK_ESCAPE) then
    begin
      RootWnd := ResolveListerRoot(State);
      if RootWnd <> 0 then
      begin
        PostMessage(RootWnd, WM_KEYDOWN, VK_ESCAPE, LParam);
        PostMessage(RootWnd, WM_KEYUP, VK_ESCAPE, LParam);
      end;
      Exit(0);
    end;
    if (Msg = WM_CHAR) and (WParam = 27) then
    begin
      RootWnd := ResolveListerRoot(State);
      if RootWnd <> 0 then
      begin
        PostMessage(RootWnd, WM_KEYDOWN, VK_ESCAPE, LParam);
        PostMessage(RootWnd, WM_KEYUP, VK_ESCAPE, LParam);
      end;
      Exit(0);
    end;
  end;

  if (State <> nil) and Assigned(State.PrevListWndProc) then
    Result := CallWindowProc(State.PrevListWndProc, Wnd, Msg, WParam, LParam)
  else
    Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

function WrapViewWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  State: TLogViewState;
  PS: TPaintStruct;
  DC: HDC;
  SI: TScrollInfo;
  NewTop, Delta: Integer;
begin
  State := TLogViewState(GetWindowLongPtr(Wnd, GWLP_USERDATA));
  case Msg of
    WM_ERASEBKGND:
      begin
        Result := 1;
        Exit;
      end;
    WM_PAINT:
      begin
        DC := BeginPaint(Wnd, PS);
        if (State <> nil) and (DC <> 0) then
          State.PaintViewport(DC);
        EndPaint(Wnd, PS);
        Result := 0;
        Exit;
      end;
    WM_SIZE:
      begin
        if State <> nil then
        begin
          State.ResetWrapCache;
          State.UpdateViewScrollBars;
          InvalidateRect(Wnd, nil, False);
        end;
        Result := 0;
        Exit;
      end;
    WM_VSCROLL:
      begin
        if State <> nil then
        begin
          NewTop := State.ViewTopIndex;
          case LOWORD(WParam) of
            SB_LINEUP: Dec(NewTop);
            SB_LINEDOWN: Inc(NewTop);
            SB_PAGEUP: Dec(NewTop, State.ViewBaseVisibleCount);
            SB_PAGEDOWN: Inc(NewTop, State.ViewBaseVisibleCount);
            SB_THUMBTRACK,
            SB_THUMBPOSITION:
              begin
                FillChar(SI, SizeOf(SI), 0);
                SI.cbSize := SizeOf(SI);
                SI.fMask := SIF_TRACKPOS;
                GetScrollInfo(Wnd, SB_VERT, SI);
                NewTop := SI.nTrackPos;
              end;
            SB_TOP: NewTop := 0;
            SB_BOTTOM: NewTop := State.VisibleCount - 1;
          end;
          State.SetViewTopIndex(NewTop);
        end;
        Result := 0;
        Exit;
      end;
    WM_MOUSEWHEEL:
      begin
        if State <> nil then
        begin
          Delta := SmallInt(HIWORD(WParam));
          State.SetViewTopIndex(State.ViewTopIndex - (Delta div WHEEL_DELTA) * 3);
        end;
        Result := 0;
        Exit;
      end;
    WM_LBUTTONDOWN:
      begin
        if State <> nil then
          State.HandleViewMouseDown(SmallInt(LOWORD(LParam)), SmallInt(HIWORD(LParam)), WParam);
        Result := 0;
        Exit;
      end;
    WM_KEYDOWN:
      begin
        if State <> nil then
          State.HandleViewKeyDown(WParam);
        Result := 0;
        Exit;
      end;
    WM_SETFOCUS,
    WM_KILLFOCUS:
      begin
        InvalidateRect(Wnd, nil, False);
      end;
    WM_GETDLGCODE:
      begin
        Result := DLGC_WANTARROWS or DLGC_WANTCHARS or DLGC_WANTALLKEYS;
        Exit;
      end;
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

function PromptTextWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  State: PPromptTextState;
  Len: Integer;
begin
  case Msg of
    WM_NCCREATE:
      begin
        SetWindowLongPtr(Wnd, GWLP_USERDATA, PtrInt(PCREATESTRUCT(LParam)^.lpCreateParams));
        Result := 1;
        Exit;
      end;
    WM_COMMAND:
      begin
        State := PPromptTextState(GetWindowLongPtr(Wnd, GWLP_USERDATA));
        if HIWORD(WParam) = BN_CLICKED then
        begin
          case LOWORD(WParam) of
            IDOK:
              begin
                if (State <> nil) and (State^.EditHandle <> 0) then
                begin
                  Len := GetWindowTextLength(State^.EditHandle);
                  SetLength(State^.Value, Len);
                  if Len > 0 then
                    GetWindowText(State^.EditHandle, PChar(State^.Value), Len + 1);
                  State^.Accepted := True;
                end;
                DestroyWindow(Wnd);
                Result := 0;
                Exit;
              end;
            IDCANCEL:
              begin
                DestroyWindow(Wnd);
                Result := 0;
                Exit;
              end;
          end;
        end;
      end;
    WM_CLOSE:
      begin
        DestroyWindow(Wnd);
        Result := 0;
        Exit;
      end;
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

function PromptDateTimeWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  State: PPromptDateTimeState;
  STDate, STTime: SYSTEMTIME;
begin
  case Msg of
    WM_NCCREATE:
      begin
        SetWindowLongPtr(Wnd, GWLP_USERDATA, PtrInt(PCREATESTRUCT(LParam)^.lpCreateParams));
        Result := 1;
        Exit;
      end;
    WM_COMMAND:
      begin
        State := PPromptDateTimeState(GetWindowLongPtr(Wnd, GWLP_USERDATA));
        if HIWORD(WParam) = BN_CLICKED then
        begin
          case LOWORD(WParam) of
            IDOK:
              begin
                if (State <> nil) and (State^.DateHandle <> 0) and (State^.TimeHandle <> 0) then
                begin
                  FillChar(STDate, SizeOf(STDate), 0);
                  FillChar(STTime, SizeOf(STTime), 0);
                  if (SendMessage(State^.DateHandle, DTM_GETSYSTEMTIME, 0, PtrInt(@STDate)) = GDT_VALID) and
                     (SendMessage(State^.TimeHandle, DTM_GETSYSTEMTIME, 0, PtrInt(@STTime)) = GDT_VALID) then
                  begin
                    try
                      State^.Value := EncodeDate(STDate.wYear, STDate.wMonth, STDate.wDay) +
                        EncodeTime(STTime.wHour, STTime.wMinute, STTime.wSecond, 0);
                      State^.Accepted := True;
                    except
                      State^.Accepted := False;
                    end;
                  end;
                end;
                DestroyWindow(Wnd);
                Result := 0;
                Exit;
              end;
            IDCANCEL:
              begin
                DestroyWindow(Wnd);
                Result := 0;
                Exit;
              end;
          end;
        end;
      end;
    WM_CLOSE:
      begin
        DestroyWindow(Wnd);
        Result := 0;
        Exit;
      end;
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

constructor TLogViewState.Create;
begin
  inherited Create;
  WindowHandle := 0;
  ParentHandle := 0;
  ListHandle := 0;
  ShowFlags := 0;
  IsListerMode := False;
  FileName := '';
  FontHandle := 0;
  UiFontHandle := 0;
  OwnUiFont := False;
  ItemHeight := 18;
  CharWidth := 8;
  Loaded := TLoadedLog.Create;
  SetLength(VisibleIdx, 0);
  VisibleCount := 0;
  VisibleDirect := True;
  MaxLineChars := 0;
  SearchText := '';
  SearchTextLower := '';
  FollowTail := True;
  TailActive := False;
  TailFilePos := 0;
  TailLineNo := 0;
  TailPartial := '';
  StatECount := 0;
  StatWCount := 0;
  StatICount := 0;
  StatELast := 0;
  StatWLast := 0;
  StatILast := 0;
  PrevListWndProc := nil;
  ParentPrevWndProc := nil;
  ParentSubclassed := False;
  SetLength(WrapHeights, 0);
  SetLength(WrapStamps, 0);
  WrapStampToken := 1;
  WrapCacheWidth := -1;
  WrapMeasureDC := 0;
  ListIsNoData := True;
  ListIsViewport := False;
  ViewTopIndex := 0;
  ViewCaretIndex := -1;
  ViewAnchorIndex := -1;
  ViewSelCapacity := 0;
  SetLength(ViewSelected, 0);
  LastSearchText := '';
  LastSearchFlags := 0;
end;

destructor TLogViewState.Destroy;
begin
  StopTail;
  if WrapMeasureDC <> 0 then
    DeleteDC(WrapMeasureDC);
  if FontHandle <> 0 then
    DeleteObject(FontHandle);
  if OwnUiFont and (UiFontHandle <> 0) then
    DeleteObject(UiFontHandle);
  Loaded.Free;
  inherited Destroy;
end;

procedure TLogViewState.InitFont;
var
  ScreenDC: HDC;
  PixPerInch: Integer;
begin
  if FontHandle <> 0 then
    DeleteObject(FontHandle);

  ScreenDC := GetDC(0);
  PixPerInch := GetDeviceCaps(ScreenDC, LOGPIXELSY);
  ReleaseDC(0, ScreenDC);

  FontHandle := CreateFont(
    -MulDiv(AppSettings.FontSize, PixPerInch, 72),
    0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET,
    OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
    FIXED_PITCH or FF_MODERN, PChar(AppSettings.FontName));

  if (WrapMeasureDC <> 0) and (FontHandle <> 0) then
    SelectObject(WrapMeasureDC, FontHandle);
end;

function TLogViewState.LoadFile: Boolean;
begin
  Result := Loaded.LoadFromFile(FileName);
  if not Result then
    Exit;

  TailLineNo := Loaded.Log.Count;
  TailFilePos := Loaded.FileSize;
  MaxLineChars := Loaded.MaxVisibleChars;
  SearchText := '';
  SearchTextLower := '';
  KillTimer(WindowHandle, TIMER_FILTER);
  if GetWindowTextLength(EdtSearch) <> 0 then
    SetWindowText(EdtSearch, '');

  SendMessage(ListHandle, WM_SETREDRAW, 0, 0);
  try
    ApplyFilter(False, False);
    if VisibleCount > 0 then
    begin
      if AppSettings.TailEnabled then
        SelectVisibleIndex(VisibleCount - 1)
      else
        SelectVisibleIndex(0);
    end;
  finally
    SendMessage(ListHandle, WM_SETREDRAW, 1, 0);
    InvalidateRect(ListHandle, nil, False);
  end;

  if AppSettings.TailEnabled then
  begin
    SendMessage(ChkTail, BM_SETCHECK, BST_CHECKED, 0);
    StartTail;
  end
  else
  begin
    SendMessage(ChkTail, BM_SETCHECK, BST_UNCHECKED, 0);
    StopTail;
  end;
end;

function TLogViewState.CurrentVisibleIndex: Integer;
var
  I: Integer;
begin
  if IsViewport then
  begin
    if (ViewCaretIndex >= 0) and (ViewCaretIndex < VisibleCount) then
      Exit(ViewCaretIndex);
    for I := 0 to VisibleCount - 1 do
      if IsViewSelected(I) then
        Exit(I);
    Exit(-1);
  end;

  Result := SendMessage(ListHandle, LB_GETCARETINDEX, 0, 0);
  if (Result >= 0) and (Result < VisibleCount) then
    Exit;
  for I := 0 to VisibleCount - 1 do
    if SendMessage(ListHandle, LB_GETSEL, I, 0) > 0 then
      Exit(I);
  Result := -1;
end;

procedure TLogViewState.SelectVisibleIndex(AVisibleIndex: Integer; ATopIndex: Boolean);
begin
  if (AVisibleIndex < 0) or (AVisibleIndex >= VisibleCount) then
    Exit;

  if IsViewport then
  begin
    EnsureViewSelectionCapacity(VisibleCount);
    ClearViewSelection;
    SetViewSelected(AVisibleIndex, True);
    ViewCaretIndex := AVisibleIndex;
    ViewAnchorIndex := AVisibleIndex;
    if ATopIndex then
      SetViewTopIndex(AVisibleIndex)
    else
      EnsureViewVisible(AVisibleIndex);
    SetFocus(ListHandle);
    InvalidateRect(ListHandle, nil, False);
    Exit;
  end;

  SendMessage(ListHandle, LB_SETSEL, 0, LPARAM(-1));
  SendMessage(ListHandle, LB_SETSEL, 1, AVisibleIndex);
  SendMessage(ListHandle, LB_SETCARETINDEX, AVisibleIndex, 0);
  if ATopIndex then
    SendMessage(ListHandle, LB_SETTOPINDEX, AVisibleIndex, 0);
  SetFocus(ListHandle);
  InvalidateRect(ListHandle, nil, False);
end;

procedure TLogViewState.BuildToolbar;
begin
  BtnPrevErr := CreateWindow('BUTTON', '<E',
    WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    6, 6, 34, 23, WindowHandle, HMENU(IDC_BTN_PREV_ERR), hInstance, nil);
  BtnNextErr := CreateWindow('BUTTON', 'E>',
    WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    42, 6, 34, 23, WindowHandle, HMENU(IDC_BTN_NEXT_ERR), hInstance, nil);

  BtnPrevWarn := CreateWindow('BUTTON', '<W',
    WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    82, 6, 34, 23, WindowHandle, HMENU(IDC_BTN_PREV_WARN), hInstance, nil);
  BtnNextWarn := CreateWindow('BUTTON', 'W>',
    WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    118, 6, 34, 23, WindowHandle, HMENU(IDC_BTN_NEXT_WARN), hInstance, nil);

  BtnPrevInfo := CreateWindow('BUTTON', '<I',
    WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    158, 6, 34, 23, WindowHandle, HMENU(IDC_BTN_PREV_INFO), hInstance, nil);
  BtnNextInfo := CreateWindow('BUTTON', 'I>',
    WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    194, 6, 34, 23, WindowHandle, HMENU(IDC_BTN_NEXT_INFO), hInstance, nil);

  ChkTail := CreateWindow('BUTTON', 'Tail',
    WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    236, 8, 58, 20, WindowHandle, HMENU(IDC_CHK_TAIL), hInstance, nil);
  ChkFollow := CreateWindow('BUTTON', 'Follow',
    WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    300, 8, 70, 20, WindowHandle, HMENU(IDC_CHK_FOLLOW), hInstance, nil);
  ChkLineNum := CreateWindow('BUTTON', 'Line#',
    WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    375, 8, 66, 20, WindowHandle, HMENU(IDC_CHK_LINENUM), hInstance, nil);
  BtnOptions := CreateWindow('BUTTON', 'Options',
    WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    446, 6, 72, 23, WindowHandle, HMENU(IDC_BTN_OPTIONS), hInstance, nil);

  LblSearch := CreateWindow('STATIC', 'Filter:',
    WS_CHILD or WS_VISIBLE or SS_LEFT,
    524, 10, 40, 16, WindowHandle, 0, hInstance, nil);
  EdtSearch := CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '',
    WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL,
    566, 6, 138, 23, WindowHandle, HMENU(IDC_EDT_SEARCH), hInstance, nil);
  BtnClear := CreateWindow('BUTTON', 'X',
    WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    708, 6, 28, 23, WindowHandle, HMENU(IDC_BTN_CLEAR), hInstance, nil);

  StatusHandle := CreateWindowEx(0, STATUSCLASSNAME, '',
    WS_CHILD or WS_VISIBLE or SBARS_TOOLTIPS,
    0, 0, 0, 0, WindowHandle, HMENU(IDC_STATUS), hInstance, nil);

  AttachEscForwarder(BtnPrevErr, Self);
  AttachEscForwarder(BtnNextErr, Self);
  AttachEscForwarder(BtnPrevWarn, Self);
  AttachEscForwarder(BtnNextWarn, Self);
  AttachEscForwarder(BtnPrevInfo, Self);
  AttachEscForwarder(BtnNextInfo, Self);
  AttachEscForwarder(ChkTail, Self);
  AttachEscForwarder(ChkFollow, Self);
  AttachEscForwarder(ChkLineNum, Self);
  AttachEscForwarder(BtnOptions, Self);
  AttachEscForwarder(EdtSearch, Self);
  AttachEscForwarder(BtnClear, Self);
end;

procedure TLogViewState.EnsureListMode;
var
  WantViewport: Boolean;
  Style: DWORD;
  CR: TRect;
begin
  WantViewport := AppSettings.WordWrap;
  if (ListHandle <> 0) and (ListIsViewport = WantViewport) then
    Exit;

  if (ListHandle <> 0) and IsWindow(ListHandle) then
  begin
    if Assigned(PrevListWndProc) then
      SetWindowLongPtr(ListHandle, GWLP_WNDPROC, PtrInt(PrevListWndProc));
    SetWindowLongPtr(ListHandle, GWLP_USERDATA, 0);
    DestroyWindow(ListHandle);
    ListHandle := 0;
    PrevListWndProc := nil;
  end;

  if WantViewport then
  begin
    ListHandle := CreateWindowEx(
      WS_EX_CLIENTEDGE,
      LOGVIEW_WRAPVIEW_WNDCLASS,
      nil,
      WS_CHILD or WS_VISIBLE or WS_VSCROLL or WS_TABSTOP,
      0, TOOLBAR_H, 100, 100,
      WindowHandle, HMENU(IDC_LOG_LIST), hInstance, nil);
  end
  else
  begin
    Style := WS_CHILD or WS_VISIBLE or WS_VSCROLL or WS_HSCROLL or
      LBS_NOINTEGRALHEIGHT or LBS_NOTIFY or LBS_EXTENDEDSEL or
      LBS_OWNERDRAWFIXED or LBS_NODATA;

    ListHandle := CreateWindowEx(
      WS_EX_CLIENTEDGE,
      'LISTBOX',
      nil,
      Style,
      0, TOOLBAR_H, 100, 100,
      WindowHandle, HMENU(IDC_LOG_LIST), hInstance, nil);
  end;

  if ListHandle <> 0 then
  begin
    SetWindowLongPtr(ListHandle, GWLP_USERDATA, PtrInt(Self));
    PrevListWndProc := WNDPROC(SetWindowLongPtr(ListHandle, GWLP_WNDPROC, PtrInt(@LogListWndProc)));
    if FontHandle <> 0 then
      SendMessage(ListHandle, WM_SETFONT, WPARAM(FontHandle), LPARAM(1));
    ListIsViewport := WantViewport;
    ListIsNoData := not WantViewport;
    GetClientRect(WindowHandle, CR);
    MoveWindow(ListHandle, 0, TOOLBAR_H, CR.Right, Max(0, CR.Bottom - TOOLBAR_H - STATUS_H), True);
    if WantViewport then
      UpdateViewScrollBars;
  end;
end;

procedure TLogViewState.SyncListItems;
var
  TopMax: Integer;
begin
  if ListHandle = 0 then
    Exit;

  if IsViewport then
  begin
    EnsureViewSelectionCapacity(VisibleCount);
    if VisibleCount <= 0 then
    begin
      ViewTopIndex := 0;
      ViewCaretIndex := -1;
      ViewAnchorIndex := -1;
      ClearViewSelection;
    end
    else
    begin
      if ViewCaretIndex < 0 then
        ViewCaretIndex := 0;
      if ViewCaretIndex >= VisibleCount then
        ViewCaretIndex := VisibleCount - 1;
      if (ViewAnchorIndex < 0) or (ViewAnchorIndex >= VisibleCount) then
        ViewAnchorIndex := ViewCaretIndex;
      if not IsViewSelected(ViewCaretIndex) then
      begin
        ClearViewSelection;
        SetViewSelected(ViewCaretIndex, True);
      end;
      TopMax := Max(0, VisibleCount - ViewBaseVisibleCount);
      if ViewTopIndex > TopMax then
        ViewTopIndex := TopMax;
      if ViewTopIndex < 0 then
        ViewTopIndex := 0;
    end;
    ResetWrapCache;
    UpdateViewScrollBars;
    InvalidateRect(ListHandle, nil, False);
    Exit;
  end;

  if ListIsNoData then
  begin
    SendMessage(ListHandle, LB_SETCOUNT, VisibleCount, 0);
  end
  else
    SendMessage(ListHandle, LB_SETCOUNT, VisibleCount, 0);

  if AppSettings.WordWrap then
  begin
    ResetWrapCache;
    InvalidateRect(ListHandle, nil, False);
  end
  else
  begin
    if VisibleCount > 0 then
      SendMessage(ListHandle, LB_SETITEMHEIGHT, 0, ItemHeight);
    InvalidateRect(ListHandle, nil, False);
  end;
end;

procedure TLogViewState.AppendVisibleItems(AAppendCount: Integer);
begin
  if (ListHandle = 0) or (AAppendCount <= 0) then
    Exit;

  if IsViewport then
  begin
    EnsureViewSelectionCapacity(VisibleCount);
    UpdateViewScrollBars;
    InvalidateRect(ListHandle, nil, False);
    Exit;
  end;

  if ListIsNoData then
  begin
    SendMessage(ListHandle, LB_SETCOUNT, VisibleCount, 0);
    Exit;
  end;
  SendMessage(ListHandle, LB_SETCOUNT, VisibleCount, 0);
  InvalidateRect(ListHandle, nil, False);
end;

procedure TLogViewState.UpdateLayout;
var
  R: TRect;
  FilterX: Integer;
  Parts: array[0..1] of Integer;
begin
  GetClientRect(WindowHandle, R);
  MoveWindow(ListHandle, 0, TOOLBAR_H, R.Right, Max(0, R.Bottom - TOOLBAR_H - STATUS_H), True);
  MoveWindow(StatusHandle, 0, R.Bottom - STATUS_H, R.Right, STATUS_H, True);

  MoveWindow(BtnPrevErr, 6, 6, 34, 23, True);
  MoveWindow(BtnNextErr, 42, 6, 34, 23, True);
  MoveWindow(BtnPrevWarn, 82, 6, 34, 23, True);
  MoveWindow(BtnNextWarn, 118, 6, 34, 23, True);
  MoveWindow(BtnPrevInfo, 158, 6, 34, 23, True);
  MoveWindow(BtnNextInfo, 194, 6, 34, 23, True);
  MoveWindow(ChkTail, 236, 8, 58, 20, True);
  MoveWindow(ChkFollow, 300, 8, 70, 20, True);
  MoveWindow(ChkLineNum, 375, 8, 66, 20, True);
  MoveWindow(BtnOptions, 446, 6, 72, 23, True);

  // Keep filter controls right-aligned with fixed widths.
  FilterX := Max(524, R.Right - (6 + 40 + 2 + 138 + 4 + 28));
  MoveWindow(LblSearch, FilterX, 10, 40, 16, True);
  MoveWindow(EdtSearch, FilterX + 42, 6, 138, 23, True);
  MoveWindow(BtnClear, FilterX + 184, 6, 28, 23, True);

  Parts[0] := Max(220, R.Right - 495);
  Parts[1] := -1;
  SendMessage(StatusHandle, SB_SETPARTS, 2, LPARAM(@Parts[0]));
  if AppSettings.WordWrap and (ListHandle <> 0) then
  begin
    ResetWrapCache;
    if IsViewport then
      UpdateViewScrollBars;
    InvalidateRect(ListHandle, nil, False);
  end;
  UpdateStatusBar;
end;

procedure TLogViewState.UpdateListMetrics;
var
  DC: HDC;
  OldF: HGDIOBJ;
  TM: TTextMetric;
  Extent: Integer;
  OldItemHeight, OldCharWidth: Integer;
begin
  if ListHandle = 0 then
    Exit;
  OldItemHeight := ItemHeight;
  OldCharWidth := CharWidth;
  DC := GetDC(ListHandle);
  OldF := SelectObject(DC, FontHandle);
  if GetTextMetrics(DC, TM) then
  begin
    ItemHeight := Max(14, TM.tmHeight + 4);
    CharWidth := Max(6, TM.tmAveCharWidth);
  end;
  SelectObject(DC, OldF);
  ReleaseDC(ListHandle, DC);

  if (not AppSettings.WordWrap) and (not IsViewport) then
    SendMessage(ListHandle, LB_SETITEMHEIGHT, 0, ItemHeight);

  if IsViewport then
  begin
    ResetWrapCache;
    UpdateViewScrollBars;
    InvalidateRect(ListHandle, nil, False);
    Exit;
  end;

  if AppSettings.WordWrap or (not AppSettings.ShowHorzScrollbar) then
    Extent := 0
  else
    Extent := (Max(Loaded.MaxVisibleChars, MaxLineChars) + AppSettings.LineNumberWidth + 4) * CharWidth;
  SendMessage(ListHandle, LB_SETHORIZONTALEXTENT, Extent, 0);
  if (OldItemHeight <> ItemHeight) or (OldCharWidth <> CharWidth) then
    ResetWrapCache;
end;

procedure TLogViewState.EnsureWrapCacheCapacity(ACount: Integer);
var
  NewCap: Integer;
begin
  if ACount <= Length(WrapHeights) then
    Exit;
  NewCap := Max(ACount, Length(WrapHeights) + (Length(WrapHeights) div 2) + 256);
  if NewCap < 1024 then
    NewCap := 1024;
  SetLength(WrapHeights, NewCap);
  SetLength(WrapStamps, NewCap);
end;

procedure TLogViewState.ResetWrapCache;
begin
  EnsureWrapCacheCapacity(VisibleCount);
  Inc(WrapStampToken);
  if WrapStampToken = 0 then
  begin
    if Length(WrapStamps) > 0 then
      FillChar(WrapStamps[0], Length(WrapStamps) * SizeOf(Integer), 0);
    WrapStampToken := 1;
  end;
  WrapCacheWidth := -1;
end;

function TLogViewState.MeasureVisibleItemHeight(AVisibleIndex: Integer): Integer;
var
  RawIdx, WrapLeft, W, TopIdx, VisRows, MinMeasure, MaxMeasure, I: Integer;
  R: TRect;
  DC: HDC;
  OldF: HGDIOBJ;
  RawPtr: PAnsiChar;
  RawLen: Integer;
  OnlyWhitespace: Boolean;
  OwnDC: Boolean;
begin
  Result := ItemHeight;
  if (AVisibleIndex < 0) or (AVisibleIndex >= VisibleCount) then
    Exit;
  if not AppSettings.WordWrap then
    Exit;
  EnsureWrapCacheCapacity(VisibleCount);

  GetClientRect(ListHandle, R);
  W := R.Right - R.Left;
  if W <= 0 then
    Exit;
  if WrapCacheWidth <> W then
  begin
    WrapCacheWidth := W;
    Inc(WrapStampToken);
    if WrapStampToken = 0 then
    begin
      if Length(WrapStamps) > 0 then
        FillChar(WrapStamps[0], Length(WrapStamps) * SizeOf(Integer), 0);
      WrapStampToken := 1;
    end;
  end;
  if (AVisibleIndex < Length(WrapHeights)) and
     (AVisibleIndex < Length(WrapStamps)) and
     (WrapStamps[AVisibleIndex] = WrapStampToken) and
     (WrapHeights[AVisibleIndex] > 0) then
    Exit(WrapHeights[AVisibleIndex]);

  // Keep variable-height list performance: estimate off-screen rows with base height.
  if IsViewport then
    TopIdx := ViewTopIndex
  else
    TopIdx := SendMessage(ListHandle, LB_GETTOPINDEX, 0, 0);
  VisRows := Max(1, (R.Bottom - R.Top) div Max(1, ItemHeight));
  MinMeasure := Max(0, TopIdx - VisRows);
  MaxMeasure := Min(VisibleCount - 1, TopIdx + (VisRows * 2));
  if (AVisibleIndex < MinMeasure) or (AVisibleIndex > MaxMeasure) then
    Exit(ItemHeight);

  RawIdx := MapVisibleToRaw(AVisibleIndex);
  if RawIdx < 0 then
    Exit;
  RawLen := Loaded.Log[RawIdx].RawLen;
  if RawLen > 0 then
    RawPtr := Loaded.Log.RawPtr(Loaded.Log[RawIdx].RawOffset)
  else
    RawPtr := nil;

  // Empty/blank log lines should always keep the simple single-line height.
  if (RawPtr = nil) or (RawLen <= 0) then
  begin
    if AVisibleIndex < Length(WrapHeights) then
    begin
      WrapHeights[AVisibleIndex] := ItemHeight;
      WrapStamps[AVisibleIndex] := WrapStampToken;
    end;
    Exit(ItemHeight);
  end;
  OnlyWhitespace := True;
  for I := 0 to RawLen - 1 do
    if RawPtr[I] > ' ' then
    begin
      OnlyWhitespace := False;
      Break;
    end;
  if OnlyWhitespace then
  begin
    if AVisibleIndex < Length(WrapHeights) then
    begin
      WrapHeights[AVisibleIndex] := ItemHeight;
      WrapStamps[AVisibleIndex] := WrapStampToken;
    end;
    Exit(ItemHeight);
  end;

  WrapLeft := 4;
  if AppSettings.ShowLineNumbers then
    WrapLeft := 4 + (AppSettings.LineNumberWidth + 1) * CharWidth + 2;

  R.Left := 0;
  R.Top := 0;
  R.Right := Max(8, W - WrapLeft - 2);
  R.Bottom := 32767;

  OwnDC := False;
  if WrapMeasureDC = 0 then
  begin
    WrapMeasureDC := CreateCompatibleDC(0);
    if (WrapMeasureDC <> 0) and (FontHandle <> 0) then
      SelectObject(WrapMeasureDC, FontHandle);
  end;

  if WrapMeasureDC <> 0 then
    DC := WrapMeasureDC
  else
  begin
    DC := GetDC(ListHandle);
    OwnDC := DC <> 0;
  end;
  if DC = 0 then
    Exit(ItemHeight);

  OldF := 0;
  if (WrapMeasureDC = 0) and (FontHandle <> 0) then
    OldF := SelectObject(DC, FontHandle);
  DrawTextA(DC, RawPtr, RawLen, R, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
  if OldF <> 0 then
    SelectObject(DC, OldF);
  if OwnDC then
    ReleaseDC(ListHandle, DC);

  Result := Max(ItemHeight, (R.Bottom - R.Top) + 2);
  if AVisibleIndex < Length(WrapHeights) then
  begin
    WrapHeights[AVisibleIndex] := Result;
    WrapStamps[AVisibleIndex] := WrapStampToken;
  end;
end;

function TLogViewState.IsViewport: Boolean; inline;
begin
  Result := ListIsViewport and (ListHandle <> 0);
end;

function TLogViewState.ViewBaseVisibleCount: Integer;
var
  R: TRect;
begin
  if (not IsViewport) or (ListHandle = 0) then
    Exit(1);
  GetClientRect(ListHandle, R);
  Result := Max(1, (R.Bottom - R.Top) div Max(1, ItemHeight));
end;

procedure TLogViewState.UpdateViewScrollBars;
var
  SI: TScrollInfo;
  MaxTop: Integer;
begin
  if not IsViewport then
    Exit;

  if VisibleCount <= 0 then
  begin
    ViewTopIndex := 0;
    MaxTop := 0;
  end
  else
  begin
    MaxTop := Max(0, VisibleCount - ViewBaseVisibleCount);
    if ViewTopIndex > MaxTop then
      ViewTopIndex := MaxTop;
    if ViewTopIndex < 0 then
      ViewTopIndex := 0;
  end;

  FillChar(SI, SizeOf(SI), 0);
  SI.cbSize := SizeOf(SI);
  SI.fMask := SIF_RANGE or SIF_PAGE or SIF_POS;
  SI.nMin := 0;
  SI.nMax := Max(0, VisibleCount - 1);
  SI.nPage := ViewBaseVisibleCount;
  if SI.nPage < 1 then
    SI.nPage := 1;
  SI.nPos := ViewTopIndex;
  SetScrollInfo(ListHandle, SB_VERT, SI, True);
end;

procedure TLogViewState.EnsureViewSelectionCapacity(ACount: Integer);
var
  NewCap: Integer;
begin
  if ACount <= ViewSelCapacity then
    Exit;
  NewCap := Max(ACount, ViewSelCapacity + 4096);
  SetLength(ViewSelected, NewCap);
  ViewSelCapacity := NewCap;
end;

procedure TLogViewState.ClearViewSelection;
begin
  if (ViewSelCapacity > 0) and (Length(ViewSelected) > 0) then
    FillChar(ViewSelected[0], ViewSelCapacity * SizeOf(Byte), 0);
end;

function TLogViewState.IsViewSelected(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < VisibleCount) and
            (AIndex < ViewSelCapacity) and (ViewSelected[AIndex] <> 0);
end;

procedure TLogViewState.SetViewSelected(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex >= VisibleCount) then
    Exit;
  EnsureViewSelectionCapacity(AIndex + 1);
  if AValue then
    ViewSelected[AIndex] := 1
  else
    ViewSelected[AIndex] := 0;
end;

procedure TLogViewState.SetViewTopIndex(AIndex: Integer);
var
  MaxTop: Integer;
begin
  if not IsViewport then
    Exit;
  MaxTop := Max(0, VisibleCount - ViewBaseVisibleCount);
  if AIndex < 0 then
    AIndex := 0;
  if AIndex > MaxTop then
    AIndex := MaxTop;
  if AIndex <> ViewTopIndex then
  begin
    ViewTopIndex := AIndex;
    UpdateViewScrollBars;
    InvalidateRect(ListHandle, nil, False);
  end
  else
    UpdateViewScrollBars;
end;

procedure TLogViewState.EnsureViewVisible(AIndex: Integer);
var
  VC: Integer;
begin
  if (AIndex < 0) or (AIndex >= VisibleCount) then
    Exit;
  VC := ViewBaseVisibleCount;
  if AIndex < ViewTopIndex then
    SetViewTopIndex(AIndex)
  else if AIndex >= ViewTopIndex + VC then
    SetViewTopIndex(AIndex - VC + 1)
  else
    InvalidateRect(ListHandle, nil, False);
end;

function TLogViewState.ViewIndexAtY(AY: Integer): Integer;
var
  Y, I, H, PaintH: Integer;
  R: TRect;
begin
  Result := -1;
  if not IsViewport then
    Exit;
  GetClientRect(ListHandle, R);
  PaintH := Max(0, R.Bottom - R.Top);
  Y := 0;
  I := ViewTopIndex;
  while (I < VisibleCount) and (Y < PaintH) do
  begin
    H := MeasureVisibleItemHeight(I);
    if (AY >= Y) and (AY < Y + H) then
      Exit(I);
    Inc(Y, H);
    Inc(I);
  end;
end;

procedure TLogViewState.HandleViewMouseDown(X, Y: Integer; Shift: WPARAM);
var
  Idx, J, A, B: Integer;
begin
  if not IsViewport then
    Exit;
  Idx := ViewIndexAtY(Y);
  if Idx < 0 then
    Exit;
  SetFocus(ListHandle);

  if ((Shift and MK_SHIFT) <> 0) and (ViewAnchorIndex >= 0) then
  begin
    EnsureViewSelectionCapacity(VisibleCount);
    ClearViewSelection;
    A := Min(ViewAnchorIndex, Idx);
    B := Max(ViewAnchorIndex, Idx);
    for J := A to B do
      SetViewSelected(J, True);
    ViewCaretIndex := Idx;
  end
  else if (Shift and MK_CONTROL) <> 0 then
  begin
    SetViewSelected(Idx, not IsViewSelected(Idx));
    ViewCaretIndex := Idx;
    ViewAnchorIndex := Idx;
  end
  else
  begin
    EnsureViewSelectionCapacity(VisibleCount);
    ClearViewSelection;
    SetViewSelected(Idx, True);
    ViewCaretIndex := Idx;
    ViewAnchorIndex := Idx;
  end;

  EnsureViewVisible(ViewCaretIndex);
  InvalidateRect(ListHandle, nil, False);
end;

procedure TLogViewState.HandleViewKeyDown(Key: WPARAM);
var
  VC, NewIdx, A, B, J: Integer;
  WithShift, WithCtrl: Boolean;
begin
  if not IsViewport then
    Exit;
  if VisibleCount <= 0 then
    Exit;

  VC := ViewBaseVisibleCount;
  if VC <= 0 then
    VC := 1;

  NewIdx := ViewCaretIndex;
  if NewIdx < 0 then
    NewIdx := 0;
  WithCtrl := (GetKeyState(VK_CONTROL) and $8000) <> 0;
  WithShift := (GetKeyState(VK_SHIFT) and $8000) <> 0;

  case Key of
    VK_UP: Dec(NewIdx);
    VK_DOWN: Inc(NewIdx);
    VK_PRIOR: Dec(NewIdx, VC);
    VK_NEXT: Inc(NewIdx, VC);
    VK_HOME:
      if WithCtrl then
        NewIdx := 0
      else
        SetViewTopIndex(0);
    VK_END:
      if WithCtrl then
        NewIdx := VisibleCount - 1
      else
        SetViewTopIndex(VisibleCount - 1);
  else
    Exit;
  end;

  if NewIdx < 0 then
    NewIdx := 0;
  if NewIdx >= VisibleCount then
    NewIdx := VisibleCount - 1;

  if WithShift and (ViewAnchorIndex >= 0) then
  begin
    EnsureViewSelectionCapacity(VisibleCount);
    ClearViewSelection;
    A := Min(ViewAnchorIndex, NewIdx);
    B := Max(ViewAnchorIndex, NewIdx);
    for J := A to B do
      SetViewSelected(J, True);
  end
  else if not WithCtrl then
  begin
    EnsureViewSelectionCapacity(VisibleCount);
    ClearViewSelection;
    SetViewSelected(NewIdx, True);
    ViewAnchorIndex := NewIdx;
  end;

  ViewCaretIndex := NewIdx;
  EnsureViewVisible(NewIdx);
  InvalidateRect(ListHandle, nil, False);
end;

procedure TLogViewState.PaintViewport(DC: HDC);
var
  R, ItemR: TRect;
  Brush: HBRUSH;
  Y, I, H: Integer;
  DIS: TDrawItemStruct;
begin
  if (not IsViewport) or (DC = 0) then
    Exit;

  GetClientRect(ListHandle, R);
  Brush := CreateSolidBrush(AppSettings.BgColor);
  FillRect(DC, R, Brush);
  DeleteObject(Brush);

  if VisibleCount <= 0 then
    Exit;

  Y := 0;
  I := ViewTopIndex;
  while (I < VisibleCount) and (Y < (R.Bottom - R.Top)) do
  begin
    H := MeasureVisibleItemHeight(I);
    ItemR.Left := 0;
    ItemR.Top := Y;
    ItemR.Right := R.Right;
    ItemR.Bottom := Min(R.Bottom, Y + H);

    FillChar(DIS, SizeOf(DIS), 0);
    DIS.CtlType := ODT_LISTBOX;
    DIS.CtlID := IDC_LOG_LIST;
    DIS.itemID := I;
    DIS.hwndItem := ListHandle;
    DIS.hDC := DC;
    DIS.rcItem := ItemR;
    if IsViewSelected(I) or (I = ViewCaretIndex) then
      DIS.itemState := ODS_SELECTED
    else
      DIS.itemState := 0;
    DrawListItem(Self, @DIS);

    Inc(Y, H);
    Inc(I);
  end;

  if Y < R.Bottom then
  begin
    ItemR.Left := 0;
    ItemR.Top := Y;
    ItemR.Right := R.Right;
    ItemR.Bottom := R.Bottom;
    Brush := CreateSolidBrush(AppSettings.BgColor);
    FillRect(DC, ItemR, Brush);
    DeleteObject(Brush);
  end;
end;

function TLogViewState.GetTopIndex: Integer;
begin
  if ListHandle = 0 then
    Exit(0);
  if IsViewport then
    Result := ViewTopIndex
  else
    Result := SendMessage(ListHandle, LB_GETTOPINDEX, 0, 0);
end;

procedure TLogViewState.SetTopIndex(AIndex: Integer);
begin
  if ListHandle = 0 then
    Exit;
  if IsViewport then
    SetViewTopIndex(AIndex)
  else
    SendMessage(ListHandle, LB_SETTOPINDEX, AIndex, 0);
end;

procedure TLogViewState.SelectAllVisible;
var
  I: Integer;
begin
  if IsViewport then
  begin
    EnsureViewSelectionCapacity(VisibleCount);
    for I := 0 to VisibleCount - 1 do
      ViewSelected[I] := 1;
    if (VisibleCount > 0) and (ViewCaretIndex < 0) then
      ViewCaretIndex := 0;
    InvalidateRect(ListHandle, nil, False);
  end
  else if VisibleCount > 0 then
    SendMessage(ListHandle, LB_SELITEMRANGEEX, VisibleCount - 1, 0);
end;

function TLogViewState.MapVisibleToRaw(AVisibleIndex: Integer): Integer;
begin
  if (AVisibleIndex < 0) or (AVisibleIndex >= VisibleCount) then
    Exit(-1);
  if VisibleDirect then
    Result := AVisibleIndex
  else
    Result := VisibleIdx[AVisibleIndex];
end;

procedure TLogViewState.ApplyFilter(AKeepTopIndex: Boolean; ASelectDefaultFirst: Boolean);
var
  I, Cnt, CurRaw, CurVis, TopBefore, TopMax: Integer;
  FocusWnd: HWND;
  KeepSearchFocus: Boolean;
  RawS: string;
  Entry: TLogEntry;
  RawIdx: Integer;
  SearchAscii: Boolean;
  RawPtr: PAnsiChar;
begin
  FocusWnd := GetFocus;
  KeepSearchFocus := (EdtSearch <> 0) and (FocusWnd = EdtSearch);

  if AKeepTopIndex then
    TopBefore := GetTopIndex
  else
    TopBefore := -1;

  CurVis := CurrentVisibleIndex;
  CurRaw := MapVisibleToRaw(CurVis);
  SearchAscii := IsAsciiText(SearchTextLower);

  if SearchTextLower = '' then
  begin
    VisibleDirect := True;
    VisibleCount := Loaded.Log.Count;
    SetLength(VisibleIdx, 0);
  end
  else
  begin
    VisibleDirect := False;
    SetLength(VisibleIdx, Loaded.Log.Count);
    Cnt := 0;
    for I := 0 to Loaded.Log.Count - 1 do
    begin
      Entry := Loaded.Log[I];
      if SearchAscii then
      begin
        if Entry.RawLen > 0 then
          RawPtr := Loaded.Log.RawPtr(Entry.RawOffset)
        else
          RawPtr := nil;
        if (RawPtr <> nil) and RawContainsTextCI(RawPtr, Entry.RawLen, SearchTextLower) then
        begin
          VisibleIdx[Cnt] := I;
          Inc(Cnt);
        end;
      end
      else
      begin
        RawS := LowerCase(Loaded.Log.RawStr(Entry.RawOffset, Entry.RawLen));
        if Pos(SearchTextLower, RawS) > 0 then
        begin
          VisibleIdx[Cnt] := I;
          Inc(Cnt);
        end;
      end;
    end;
    SetLength(VisibleIdx, Cnt);
    VisibleCount := Cnt;
  end;

  SyncListItems;
  UpdateListMetrics;

  StatECount := 0; StatWCount := 0; StatICount := 0;
  StatELast := 0; StatWLast := 0; StatILast := 0;
  if VisibleDirect then
  begin
    for I := 0 to VisibleCount - 1 do
    begin
      Entry := Loaded.Log[I];
      case Entry.Level of
        lError:
          begin
            Inc(StatECount);
            if Entry.TimeStamp > StatELast then StatELast := Entry.TimeStamp;
          end;
        lWarn:
          begin
            Inc(StatWCount);
            if Entry.TimeStamp > StatWLast then StatWLast := Entry.TimeStamp;
          end;
        lInfo:
          begin
            Inc(StatICount);
            if Entry.TimeStamp > StatILast then StatILast := Entry.TimeStamp;
          end;
      end;
    end;
  end
  else
  begin
    for I := 0 to VisibleCount - 1 do
    begin
      RawIdx := VisibleIdx[I];
      if RawIdx < 0 then Continue;
      Entry := Loaded.Log[RawIdx];
      case Entry.Level of
        lError:
          begin
            Inc(StatECount);
            if Entry.TimeStamp > StatELast then StatELast := Entry.TimeStamp;
          end;
        lWarn:
          begin
            Inc(StatWCount);
            if Entry.TimeStamp > StatWLast then StatWLast := Entry.TimeStamp;
          end;
        lInfo:
          begin
            Inc(StatICount);
            if Entry.TimeStamp > StatILast then StatILast := Entry.TimeStamp;
          end;
      end;
    end;
  end;
  UpdateStatusBar;

  if CurRaw >= 0 then
  begin
    if VisibleDirect then
      CurVis := CurRaw
    else
    begin
      CurVis := -1;
      for I := 0 to VisibleCount - 1 do
        if VisibleIdx[I] = CurRaw then
        begin
          CurVis := I;
          Break;
        end;
    end;
    if CurVis >= 0 then
      SelectVisibleIndex(CurVis, False);
  end
  else if ASelectDefaultFirst and (VisibleCount > 0) then
    SelectVisibleIndex(0, False);

  if TopBefore >= 0 then
  begin
    TopMax := Max(0, VisibleCount - 1);
    if TopBefore > TopMax then
      TopBefore := TopMax;
    SetTopIndex(TopBefore);
  end;

  if KeepSearchFocus and (EdtSearch <> 0) and IsWindow(EdtSearch) then
    SetFocus(EdtSearch);

  InvalidateRect(ListHandle, nil, False);
end;

function TLogViewState.LineText(AVisibleIndex: Integer): AnsiString;
var
  RawIdx: Integer;
  E: TLogEntry;
  Num, S: string;
  Pad: Integer;
begin
  Result := '';
  RawIdx := MapVisibleToRaw(AVisibleIndex);
  if RawIdx < 0 then
    Exit;
  E := Loaded.Log[RawIdx];
  S := Loaded.Log.RawStr(E.RawOffset, E.RawLen);
  if AppSettings.ShowLineNumbers then
  begin
    Num := IntToStr(E.LineNo);
    Pad := Max(0, AppSettings.LineNumberWidth - Length(Num));
    Result := AnsiString(StringOfChar(' ', Pad) + Num + '  ' + S);
  end
  else
    Result := AnsiString(S);
end;

function TLogViewState.RawLine(AVisibleIndex: Integer): string;
var
  RawIdx: Integer;
  E: TLogEntry;
begin
  Result := '';
  RawIdx := MapVisibleToRaw(AVisibleIndex);
  if RawIdx < 0 then
    Exit;
  E := Loaded.Log[RawIdx];
  Result := Loaded.Log.RawStr(E.RawOffset, E.RawLen);
end;

function TLogViewState.BgColor(ALevel: TLogLevel): COLORREF;
begin
  case ALevel of
    lError: Result := AppSettings.ErrBg;
    lWarn: Result := AppSettings.WarnBg;
    lInfo: Result := AppSettings.InfoBg;
    lDebug: Result := AppSettings.DebugBg;
    lTrace: Result := AppSettings.TraceBg;
  else
    Result := AppSettings.CustomBg;
  end;
end;

function TLogViewState.FgColor(ALevel: TLogLevel): COLORREF;
begin
  case ALevel of
    lError: Result := AppSettings.ErrFg;
    lWarn: Result := AppSettings.WarnFg;
    lInfo: Result := AppSettings.InfoFg;
    lDebug: Result := AppSettings.DebugFg;
    lTrace: Result := AppSettings.TraceFg;
  else
    Result := AppSettings.CustomFg;
  end;
end;

procedure TLogViewState.ApplyColorRules(const AEntry: TLogEntry; var ALevel: TLogLevel; var ABg, AFg: COLORREF);
var
  I: Integer;
  Rule: TColorStringRule;
  SLower: string;
  ARawText: string;
begin
  if AppSettings.ColorRuleCount <= 0 then
    Exit;

  ARawText := Loaded.Log.RawStr(AEntry.RawOffset, AEntry.RawLen);
  SLower := LowerCase(ARawText);
  for I := 0 to AppSettings.ColorRuleCount - 1 do
  begin
    Rule := AppSettings.ColorRules[I];
    if (not Rule.Enabled) or (Rule.Pattern = '') then
      Continue;
    if Pos(LowerCase(Rule.Pattern), SLower) <= 0 then
      Continue;

    if Rule.UseLevel then
    begin
      ALevel := Rule.Level;
      ABg := BgColor(ALevel);
      AFg := FgColor(ALevel);
    end
    else
    begin
      ABg := Rule.Color;
      if Rule.FgColor <> NO_COLOR_OVERRIDE then
        AFg := Rule.FgColor;
    end;
    Exit;
  end;
end;

function CopyTextToClipboard(Wnd: HWND; const S: string): Boolean;
var
  WS: UnicodeString;
  Mem: HGLOBAL;
  P: PWideChar;
  Sz: NativeUInt;
begin
  Result := False;
  WS := UTF8Decode(UTF8Encode(S));
  Sz := (Length(WS) + 1) * SizeOf(WideChar);
  Mem := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, Sz);
  if Mem = 0 then
    Exit;

  P := GlobalLock(Mem);
  if P = nil then
  begin
    GlobalFree(Mem);
    Exit;
  end;
  if Length(WS) > 0 then
    Move(WS[1], P^, Length(WS) * SizeOf(WideChar));
  P[Length(WS)] := #0;
  GlobalUnlock(Mem);

  if not OpenClipboard(Wnd) then
  begin
    GlobalFree(Mem);
    Exit;
  end;
  try
    EmptyClipboard;
    if SetClipboardData(CF_UNICODETEXT, Mem) <> 0 then
      Result := True
    else
      GlobalFree(Mem);
  finally
    CloseClipboard;
  end;
end;

function TLogViewState.CopySelection: Boolean;
var
  I, CurSel: Integer;
  S: string;
begin
  Result := False;
  S := '';
  if IsViewport then
  begin
    for I := 0 to VisibleCount - 1 do
      if IsViewSelected(I) then
        S := S + RawLine(I) + LineEnding;
  end
  else
  begin
    for I := 0 to VisibleCount - 1 do
      if SendMessage(ListHandle, LB_GETSEL, I, 0) > 0 then
        S := S + RawLine(I) + LineEnding;
  end;

  if S = '' then
  begin
    CurSel := CurrentVisibleIndex;
    if CurSel <> LB_ERR then
      S := RawLine(CurSel);
  end;

  if S <> '' then
    Result := CopyTextToClipboard(WindowHandle, S);
end;

function TLogViewState.CopyCurrentLine: Boolean;
var
  CurSel: Integer;
begin
  Result := False;
  CurSel := CurrentVisibleIndex;
  if CurSel = LB_ERR then
    Exit;
  Result := CopyTextToClipboard(WindowHandle, RawLine(CurSel));
end;

function TLogViewState.CopyAllVisible: Boolean;
var
  I: Integer;
  S: string;
begin
  S := '';
  for I := 0 to VisibleCount - 1 do
    S := S + RawLine(I) + LineEnding;
  Result := (S <> '') and CopyTextToClipboard(WindowHandle, S);
end;

procedure TLogViewState.GotoLevel(AForward: Boolean; ALevel: TLogLevel);
var
  CurSel, I, RawIdx: Integer;
begin
  FollowTail := False;
  SendMessage(ChkFollow, BM_SETCHECK, BST_UNCHECKED, 0);
  CurSel := CurrentVisibleIndex;
  if CurSel = LB_ERR then
    CurSel := 0;

  if AForward then
  begin
    for I := CurSel + 1 to VisibleCount - 1 do
    begin
      RawIdx := MapVisibleToRaw(I);
        if (RawIdx >= 0) and (Loaded.Log[RawIdx].Level = ALevel) then
        begin
          SelectVisibleIndex(I);
          Exit;
        end;
    end;
  end
  else
  begin
    for I := CurSel - 1 downto 0 do
    begin
      RawIdx := MapVisibleToRaw(I);
        if (RawIdx >= 0) and (Loaded.Log[RawIdx].Level = ALevel) then
        begin
          SelectVisibleIndex(I);
          Exit;
        end;
    end;
  end;
end;

procedure TLogViewState.GotoLineNumber(ALine: Integer);
var
  I, RawIdx: Integer;
begin
  FollowTail := False;
  SendMessage(ChkFollow, BM_SETCHECK, BST_UNCHECKED, 0);
  if ALine <= 0 then
    Exit;
  for I := 0 to VisibleCount - 1 do
  begin
    RawIdx := MapVisibleToRaw(I);
    if (RawIdx >= 0) and (Loaded.Log[RawIdx].LineNo >= ALine) then
    begin
      SelectVisibleIndex(I);
      Exit;
    end;
  end;
end;

procedure TLogViewState.GotoDateTime(ADT: TDateTime);
var
  I, RawIdx: Integer;
  TS: TDateTime;
begin
  FollowTail := False;
  SendMessage(ChkFollow, BM_SETCHECK, BST_UNCHECKED, 0);
  for I := 0 to VisibleCount - 1 do
  begin
    RawIdx := MapVisibleToRaw(I);
    if RawIdx < 0 then
      Continue;
    TS := Loaded.Log[RawIdx].TimeStamp;
    if (TS > 0) and (TS >= ADT) then
    begin
      SelectVisibleIndex(I);
      Exit;
    end;
  end;
end;

procedure TLogViewState.StartTail;
begin
  TailActive := True;
  TailPartial := '';
  SetTimer(WindowHandle, TIMER_TAIL, EnsureRange(AppSettings.TailIntervalMs, 200, 30000), nil);
end;

procedure TLogViewState.StopTail;
begin
  TailActive := False;
  KillTimer(WindowHandle, TIMER_TAIL);
end;

procedure TLogViewState.AppendTailLine(const ALine: AnsiString);
var
  RawOff, Idx: Integer;
  Tmp: string;
begin
  Inc(TailLineNo);
  RawOff := Loaded.Log.AppendRaw(PAnsiChar(ALine), Length(ALine));
  Idx := Loaded.Log.PrepareAdd;
  Tmp := string(ALine);
  TLogParser.ParseLine(Tmp, TailLineNo, Loaded.Format, Loaded.Log.Slot(Idx)^);
  Loaded.Log.Slot(Idx)^.RawOffset := RawOff;
  Loaded.Log.Slot(Idx)^.RawLen := Length(ALine);
  Loaded.Log.CommitAdd;
  if Length(ALine) > MaxLineChars then
    MaxLineChars := Length(ALine);
end;

procedure TLogViewState.TailTick;
var
  SR: TSearchRec;
  NewSize, Delta: Int64;
  FS: TFileStream;
  Buf: RawByteString;
  P, LineStart: Integer;
  S: AnsiString;
  OneLine: AnsiString;
  OldVisibleCount, AddedVisible, OldTop, TopMax: Integer;
  OldMaxLineChars, RawStart, RawEnd, RawIdx: Integer;
  Entry: TLogEntry;
  Extent: Integer;
  SavedSelRaw: array of Integer;
  SavedSelCount: Integer;
  SavedCaretRaw: Integer;
  I, VisIdx, CurRaw: Integer;
begin
  if not TailActive then
    Exit;
  if FileName = '' then
    Exit;

  NewSize := 0;
  if FindFirst(FileName, faAnyFile, SR) = 0 then
  begin
    NewSize := SR.Size;
    FindClose(SR);
  end;
  if NewSize <= TailFilePos then
    Exit;

  Delta := NewSize - TailFilePos;
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    FS.Position := TailFilePos;
    SetLength(Buf, Delta);
    if Delta > 0 then
      FS.ReadBuffer(Buf[1], Delta);
  finally
    FS.Free;
  end;
  TailFilePos := NewSize;

  S := TailPartial + Buf;
  TailPartial := '';
  OldVisibleCount := VisibleCount;
  OldTop := GetTopIndex;
  OldMaxLineChars := MaxLineChars;
  SavedSelCount := 0;
  SavedCaretRaw := -1;
  if not FollowTail then
  begin
    SetLength(SavedSelRaw, VisibleCount);
    for I := 0 to VisibleCount - 1 do
    begin
      if IsViewport then
      begin
        if IsViewSelected(I) then
        begin
          SavedSelRaw[SavedSelCount] := MapVisibleToRaw(I);
          Inc(SavedSelCount);
        end;
      end
      else if SendMessage(ListHandle, LB_GETSEL, I, 0) > 0 then
      begin
        SavedSelRaw[SavedSelCount] := MapVisibleToRaw(I);
        Inc(SavedSelCount);
      end;
    end;
    SetLength(SavedSelRaw, SavedSelCount);
    CurRaw := MapVisibleToRaw(CurrentVisibleIndex);
    if CurRaw >= 0 then
      SavedCaretRaw := CurRaw;
  end;
  RawStart := Loaded.Log.Count;
  LineStart := 1;
  for P := 1 to Length(S) do
  begin
    if S[P] = #10 then
    begin
      if (P > LineStart) and (S[P - 1] = #13) then
        OneLine := Copy(S, LineStart, P - LineStart - 1)
      else
        OneLine := Copy(S, LineStart, P - LineStart);
      AppendTailLine(OneLine);
      LineStart := P + 1;
    end;
  end;
  if LineStart <= Length(S) then
    TailPartial := Copy(S, LineStart, MaxInt);

  RawEnd := Loaded.Log.Count - 1;
  if RawEnd < RawStart then
    Exit;

  // Incremental fast path like original app: no full filter rebuild while no search is active.
  if SearchTextLower = '' then
  begin
    VisibleDirect := True;
    VisibleCount := Loaded.Log.Count;
    SetLength(VisibleIdx, 0);
    AddedVisible := VisibleCount - OldVisibleCount;
    if AddedVisible > 0 then
      AppendVisibleItems(AddedVisible);

    if AppSettings.WordWrap then
      EnsureWrapCacheCapacity(VisibleCount);

    if (not AppSettings.WordWrap) and AppSettings.ShowHorzScrollbar and (MaxLineChars <> OldMaxLineChars) then
    begin
      Extent := (Max(Loaded.MaxVisibleChars, MaxLineChars) + AppSettings.LineNumberWidth + 4) * CharWidth;
      SendMessage(ListHandle, LB_SETHORIZONTALEXTENT, Extent, 0);
    end;

    for RawIdx := RawStart to RawEnd do
    begin
      Entry := Loaded.Log[RawIdx];
      case Entry.Level of
        lError:
          begin
            Inc(StatECount);
            if Entry.TimeStamp > StatELast then StatELast := Entry.TimeStamp;
          end;
        lWarn:
          begin
            Inc(StatWCount);
            if Entry.TimeStamp > StatWLast then StatWLast := Entry.TimeStamp;
          end;
        lInfo:
          begin
            Inc(StatICount);
            if Entry.TimeStamp > StatILast then StatILast := Entry.TimeStamp;
          end;
      end;
    end;

    UpdateStatusBar;
    if FollowTail and (VisibleCount > 0) then
      SelectVisibleIndex(VisibleCount - 1)
    else
    begin
      TopMax := Max(0, VisibleCount - 1);
      if OldTop > TopMax then
        OldTop := TopMax;
      if OldTop >= 0 then
        SetTopIndex(OldTop);
      InvalidateRect(ListHandle, nil, False);
    end;
  end
  else
  begin
    ApplyFilter(not FollowTail);
    if FollowTail and (VisibleCount > 0) then
      SelectVisibleIndex(VisibleCount - 1);
  end;

  if (not FollowTail) and (SavedSelCount > 0) then
  begin
    if IsViewport then
      ClearViewSelection
    else
      SendMessage(ListHandle, LB_SETSEL, 0, LPARAM(-1));
    for I := 0 to SavedSelCount - 1 do
    begin
      if VisibleDirect then
      begin
        if (SavedSelRaw[I] >= 0) and (SavedSelRaw[I] < VisibleCount) then
          VisIdx := SavedSelRaw[I]
        else
          VisIdx := -1;
      end
      else
      begin
        VisIdx := -1;
        for RawIdx := 0 to VisibleCount - 1 do
          if VisibleIdx[RawIdx] = SavedSelRaw[I] then
          begin
            VisIdx := RawIdx;
            Break;
          end;
      end;
      if VisIdx >= 0 then
      begin
        if IsViewport then
          SetViewSelected(VisIdx, True)
        else
          SendMessage(ListHandle, LB_SETSEL, 1, VisIdx);
      end;
    end;
    if SavedCaretRaw >= 0 then
    begin
      if VisibleDirect then
      begin
        if (SavedCaretRaw >= 0) and (SavedCaretRaw < VisibleCount) then
          VisIdx := SavedCaretRaw
        else
          VisIdx := -1;
      end
      else
      begin
        VisIdx := -1;
        for RawIdx := 0 to VisibleCount - 1 do
          if VisibleIdx[RawIdx] = SavedCaretRaw then
          begin
            VisIdx := RawIdx;
            Break;
          end;
      end;
      if VisIdx >= 0 then
      begin
        if IsViewport then
          ViewCaretIndex := VisIdx
        else
          SendMessage(ListHandle, LB_SETCARETINDEX, VisIdx, 0);
      end;
    end;
    if IsViewport and (ViewCaretIndex >= 0) then
      EnsureViewVisible(ViewCaretIndex);
    InvalidateRect(ListHandle, nil, False);
  end;
end;

procedure TLogViewState.ApplySettingsToControls;
var
  BaseGui: HGDIOBJ;
  LF: Windows.LOGFONTA;
begin
  EnsureListMode;
  SendMessage(ChkLineNum, BM_SETCHECK, Ord(AppSettings.ShowLineNumbers), 0);
  SendMessage(ChkFollow, BM_SETCHECK, Ord(FollowTail), 0);
  SendMessage(ChkTail, BM_SETCHECK, Ord(AppSettings.TailEnabled), 0);

  if OwnUiFont and (UiFontHandle <> 0) then
  begin
    DeleteObject(UiFontHandle);
    UiFontHandle := 0;
    OwnUiFont := False;
  end;
  BaseGui := GetStockObject(DEFAULT_GUI_FONT);
  if (BaseGui <> 0) and (GetObject(BaseGui, SizeOf(LF), @LF) = SizeOf(LF)) then
  begin
    LF.lfWeight := FW_NORMAL;
    UiFontHandle := CreateFontIndirect(LF);
    OwnUiFont := UiFontHandle <> 0;
  end;
  if UiFontHandle = 0 then
    UiFontHandle := HFONT(BaseGui);

  if UiFontHandle <> 0 then
  begin
    SendMessage(BtnPrevErr, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(BtnNextErr, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(BtnPrevWarn, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(BtnNextWarn, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(BtnPrevInfo, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(BtnNextInfo, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(ChkTail, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(ChkFollow, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(ChkLineNum, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(BtnOptions, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(LblSearch, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(EdtSearch, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(BtnClear, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
    SendMessage(StatusHandle, WM_SETFONT, WPARAM(UiFontHandle), LPARAM(1));
  end;

  InitFont;
  SendMessage(ListHandle, WM_SETFONT, WPARAM(FontHandle), LPARAM(1));
  UpdateListMetrics;
  UpdateStatusBar;
end;

procedure TLogViewState.UpdateStatusBar;
var
  SLines, SMain: string;
  function Ts(const D: TDateTime): string;
  begin
    if D > 0 then
      Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', D)
    else
      Result := '-';
  end;
begin
  if StatusHandle = 0 then Exit;

  if VisibleCount = Loaded.Log.Count then
    SLines := Format('Lines: %d', [Loaded.Log.Count])
  else
    SLines := Format('Lines: %d | Visible: %d', [Loaded.Log.Count, VisibleCount]);

  SMain := Format('%s | %s | %s Byte | Format: %s',
    [ExtractFileName(FileName), SLines, FormatFloat('#,##0', TailFilePos), LogFormatNames[Loaded.Format]]);

  SendMessage(StatusHandle, SB_SETTEXT, 0, LPARAM(PChar(SMain)));
  SendMessage(StatusHandle, SB_SETTEXT, 1 or SBT_OWNERDRAW, 0);
  InvalidateRect(StatusHandle, nil, False);
end;

function PromptText(AOwner: HWND; const ACaption, APrompt, ADefault: string;
  out AValue: string): Boolean;
var
  PromptState: TPromptTextState;
const
  CLS = 'WLXLogPromptWnd2';
  IDC_EDT = 1;
var
  WC: WNDCLASS;
  Wnd, Edt, BtnOK, BtnCancel, Lbl: HWND;
  Msg: TMsg;
  R: TRect;
  UiFont, DefFont: HFONT;
  LF: Windows.LOGFONTA;
begin
  Result := False;
  PromptState.EditHandle := 0;
  PromptState.Accepted := False;
  PromptState.Value := '';
  FillChar(WC, SizeOf(WC), 0);
  if not Windows.GetClassInfo(hInstance, CLS, WC) then
  begin
    WC.lpfnWndProc := @PromptTextWndProc;
    WC.hInstance := hInstance;
    WC.hCursor := LoadCursor(0, IDC_ARROW);
    WC.hbrBackground := COLOR_BTNFACE + 1;
    WC.lpszClassName := CLS;
    Windows.RegisterClass(WC);
  end;

  Wnd := CreateWindowEx(WS_EX_DLGMODALFRAME, CLS, PChar(ACaption),
    WS_POPUP or WS_CAPTION or WS_SYSMENU,
    CW_USEDEFAULT, CW_USEDEFAULT, 430, 150,
    AOwner, 0, hInstance, @PromptState);
  if Wnd = 0 then
    Exit;
  Lbl := CreateWindow('STATIC', PChar(APrompt), WS_CHILD or WS_VISIBLE,
    10, 10, 400, 18, Wnd, 0, hInstance, nil);
  Edt := CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', PChar(ADefault),
    WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL,
    10, 34, 400, 24, Wnd, HMENU(IDC_EDT), hInstance, nil);
  PromptState.EditHandle := Edt;
  BtnOK := CreateWindow('BUTTON', 'OK', WS_CHILD or WS_VISIBLE or BS_DEFPUSHBUTTON,
    250, 72, 75, 24, Wnd, HMENU(IDOK), hInstance, nil);
  BtnCancel := CreateWindow('BUTTON', 'Cancel', WS_CHILD or WS_VISIBLE,
    335, 72, 75, 24, Wnd, HMENU(IDCANCEL), hInstance, nil);
  SendMessage(Edt, EM_SETSEL, 0, -1);

  UiFont := 0;
  DefFont := HFONT(GetStockObject(DEFAULT_GUI_FONT));
  FillChar(LF, SizeOf(LF), 0);
  if (DefFont <> 0) and (GetObject(DefFont, SizeOf(LF), @LF) = SizeOf(LF)) then
  begin
    LF.lfWeight := FW_NORMAL;
    UiFont := CreateFontIndirect(LF);
  end;
  if UiFont = 0 then
    UiFont := DefFont;
  if UiFont <> 0 then
  begin
    SendMessage(Lbl, WM_SETFONT, WPARAM(UiFont), LPARAM(1));
    SendMessage(Edt, WM_SETFONT, WPARAM(UiFont), LPARAM(1));
    SendMessage(BtnOK, WM_SETFONT, WPARAM(UiFont), LPARAM(1));
    SendMessage(BtnCancel, WM_SETFONT, WPARAM(UiFont), LPARAM(1));
  end;

  if AOwner <> 0 then
    EnableWindow(AOwner, False);
  if AOwner <> 0 then
  begin
    GetWindowRect(AOwner, R);
    SetWindowPos(Wnd, 0, R.Left + 40, R.Top + 40, 0, 0, SWP_NOSIZE or SWP_NOZORDER);
  end;
  ShowWindow(Wnd, SW_SHOW);
  SetFocus(Edt);

  while IsWindow(Wnd) and GetMessage(Msg, 0, 0, 0) do
  begin
    if not IsDialogMessage(Wnd, Msg) then
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
  end;

  if PromptState.Accepted then
  begin
    AValue := PromptState.Value;
    Result := True;
  end;

  if AOwner <> 0 then
  begin
    EnableWindow(AOwner, True);
    SetActiveWindow(AOwner);
  end;
  if IsWindow(Wnd) then
    DestroyWindow(Wnd);
  if (UiFont <> 0) and (UiFont <> DefFont) then
    DeleteObject(UiFont);
end;

function PromptDateTime(AOwner: HWND; out AValue: TDateTime): Boolean;
var
  PromptState: TPromptDateTimeState;
const
  CLS = 'WLXLogDateTimeWnd2';
var
  WC: WNDCLASS;
  Wnd, DtDate, DtTime, BtnOK, BtnCancel, Lbl: HWND;
  Msg: TMsg;
  R: TRect;
  ICC: TInitCommonControlsEx;
  STDate, STTime: SYSTEMTIME;
  Y, M, D, H, N, S, MS: Word;
  UiFont, DefFont: HFONT;
  LF: Windows.LOGFONTA;
begin
  Result := False;
  PromptState.DateHandle := 0;
  PromptState.TimeHandle := 0;
  PromptState.Accepted := False;
  PromptState.Value := 0;
  FillChar(ICC, SizeOf(ICC), 0);
  ICC.dwSize := SizeOf(ICC);
  ICC.dwICC := ICC_DATE_CLASSES;
  InitCommonControlsEx(ICC);

  FillChar(WC, SizeOf(WC), 0);
  if not Windows.GetClassInfo(hInstance, CLS, WC) then
  begin
    WC.lpfnWndProc := @PromptDateTimeWndProc;
    WC.hInstance := hInstance;
    WC.hCursor := LoadCursor(0, IDC_ARROW);
    WC.hbrBackground := COLOR_BTNFACE + 1;
    WC.lpszClassName := CLS;
    Windows.RegisterClass(WC);
  end;

  Wnd := CreateWindowEx(WS_EX_DLGMODALFRAME, CLS, 'Go to date/time',
    WS_POPUP or WS_CAPTION or WS_SYSMENU,
    CW_USEDEFAULT, CW_USEDEFAULT, 430, 170,
    AOwner, 0, hInstance, @PromptState);
  if Wnd = 0 then
    Exit;
  Lbl := CreateWindow('STATIC', 'Select date and time:', WS_CHILD or WS_VISIBLE,
    10, 10, 380, 18, Wnd, 0, hInstance, nil);
  if Lbl = 0 then ;

  DtDate := CreateWindowEx(WS_EX_CLIENTEDGE, DATETIMEPICK_CLASS, '',
    WS_CHILD or WS_VISIBLE or DTS_SHORTDATEFORMAT,
    10, 34, 170, 24, Wnd, HMENU(1), hInstance, nil);
  DtTime := CreateWindowEx(WS_EX_CLIENTEDGE, DATETIMEPICK_CLASS, '',
    WS_CHILD or WS_VISIBLE or DTS_TIMEFORMAT or DTS_UPDOWN,
    190, 34, 120, 24, Wnd, HMENU(2), hInstance, nil);
  PromptState.DateHandle := DtDate;
  PromptState.TimeHandle := DtTime;
  SendMessage(DtDate, DTM_SETFORMAT, 0, LPARAM(PChar('yyyy-MM-dd')));
  SendMessage(DtTime, DTM_SETFORMAT, 0, LPARAM(PChar('HH:mm:ss')));

  DecodeDateTime(Now, Y, M, D, H, N, S, MS);
  FillChar(STDate, SizeOf(STDate), 0);
  STDate.wYear := Y;
  STDate.wMonth := M;
  STDate.wDay := D;
  FillChar(STTime, SizeOf(STTime), 0);
  STTime.wHour := H;
  STTime.wMinute := N;
  STTime.wSecond := S;
  SendMessage(DtDate, DTM_SETSYSTEMTIME, GDT_VALID, LPARAM(@STDate));
  SendMessage(DtTime, DTM_SETSYSTEMTIME, GDT_VALID, LPARAM(@STTime));

  BtnOK := CreateWindow('BUTTON', 'OK', WS_CHILD or WS_VISIBLE or BS_DEFPUSHBUTTON,
    250, 96, 75, 24, Wnd, HMENU(IDOK), hInstance, nil);
  BtnCancel := CreateWindow('BUTTON', 'Cancel', WS_CHILD or WS_VISIBLE,
    335, 96, 75, 24, Wnd, HMENU(IDCANCEL), hInstance, nil);
  if (BtnOK = 0) or (BtnCancel = 0) then ;

  UiFont := 0;
  DefFont := HFONT(GetStockObject(DEFAULT_GUI_FONT));
  FillChar(LF, SizeOf(LF), 0);
  if (DefFont <> 0) and (GetObject(DefFont, SizeOf(LF), @LF) = SizeOf(LF)) then
  begin
    LF.lfWeight := FW_NORMAL;
    UiFont := CreateFontIndirect(LF);
  end;
  if UiFont = 0 then
    UiFont := DefFont;
  if UiFont <> 0 then
  begin
    SendMessage(Lbl, WM_SETFONT, WPARAM(UiFont), LPARAM(1));
    SendMessage(DtDate, WM_SETFONT, WPARAM(UiFont), LPARAM(1));
    SendMessage(DtTime, WM_SETFONT, WPARAM(UiFont), LPARAM(1));
    SendMessage(BtnOK, WM_SETFONT, WPARAM(UiFont), LPARAM(1));
    SendMessage(BtnCancel, WM_SETFONT, WPARAM(UiFont), LPARAM(1));
  end;

  if AOwner <> 0 then
    EnableWindow(AOwner, False);
  if AOwner <> 0 then
  begin
    GetWindowRect(AOwner, R);
    SetWindowPos(Wnd, 0, R.Left + 40, R.Top + 40, 0, 0, SWP_NOSIZE or SWP_NOZORDER);
  end;
  ShowWindow(Wnd, SW_SHOW);
  SetFocus(DtDate);

  while IsWindow(Wnd) and GetMessage(Msg, 0, 0, 0) do
  begin
    if not IsDialogMessage(Wnd, Msg) then
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
  end;

  if PromptState.Accepted then
  begin
    AValue := PromptState.Value;
    Result := True;
  end;

  if AOwner <> 0 then
  begin
    EnableWindow(AOwner, True);
    SetActiveWindow(AOwner);
  end;
  if IsWindow(Wnd) then
    DestroyWindow(Wnd);
  if (UiFont <> 0) and (UiFont <> DefFont) then
    DeleteObject(UiFont);
end;

procedure TLogViewState.ShowContextMenu(X, Y: Integer);
var
  Menu: HMENU;
  Flags: UINT;
  P: TPoint;
begin
  Menu := CreatePopupMenu;
  AppendMenu(Menu, MF_STRING, IDM_CTX_COPYLINE, 'Copy line');
  AppendMenu(Menu, MF_STRING, IDM_CTX_COPYVISIBLE, 'Copy all visible');
  AppendMenu(Menu, MF_SEPARATOR, 0, nil);
  Flags := MF_STRING;
  if AppSettings.ShowLineNumbers then
    Flags := Flags or MF_CHECKED;
  AppendMenu(Menu, Flags, IDM_CTX_LINENUM, 'Line numbers');

  Flags := MF_STRING;
  if AppSettings.WordWrap then
    Flags := Flags or MF_CHECKED;
  AppendMenu(Menu, Flags, IDM_CTX_WORDWRAP, 'Word wrap');
  AppendMenu(Menu, MF_SEPARATOR, 0, nil);
  AppendMenu(Menu, MF_STRING, IDM_CTX_GOTODT, 'Go to date/time');
  AppendMenu(Menu, MF_STRING, IDM_CTX_GOTOLINE, 'Go to line');

  if (X = -1) and (Y = -1) then
  begin
    GetCursorPos(P);
    X := P.X;
    Y := P.Y;
  end;

  SetForegroundWindow(WindowHandle);
  TrackPopupMenu(Menu, TPM_LEFTBUTTON or TPM_RIGHTBUTTON, X, Y, 0, WindowHandle, nil);
  DestroyMenu(Menu);
end;

function IsWordChar(C: Char): Boolean; inline;
begin
  Result := ((C >= '0') and (C <= '9')) or
            ((C >= 'A') and (C <= 'Z')) or
            ((C >= 'a') and (C <= 'z')) or
            (C = '_');
end;

function TLogViewState.FindText(const AText: string; AMatchCase, AWholeWords, ABackwards: Boolean;
  AFromCurrent: Boolean): Boolean;
var
  Needle, Hay: string;
  I, StartIdx, RawIdx, P: Integer;
  CurIdx: Integer;
  LeftOk, RightOk: Boolean;
begin
  Result := False;
  if (AText = '') or (VisibleCount <= 0) then
    Exit;

  if AMatchCase then
    Needle := AText
  else
    Needle := LowerCase(AText);

  CurIdx := CurrentVisibleIndex;
  if CurIdx < 0 then
    CurIdx := 0;

  if ABackwards then
  begin
    if AFromCurrent then StartIdx := CurIdx - 1 else StartIdx := VisibleCount - 1;
    for I := StartIdx downto 0 do
    begin
      RawIdx := MapVisibleToRaw(I);
      if RawIdx < 0 then Continue;
      Hay := Loaded.Log.RawStr(Loaded.Log[RawIdx].RawOffset, Loaded.Log[RawIdx].RawLen);
      if not AMatchCase then
        Hay := LowerCase(Hay);
      P := Pos(Needle, Hay);
      if P <= 0 then Continue;
      if AWholeWords then
      begin
        LeftOk := (P = 1) or (not IsWordChar(Hay[P - 1]));
        RightOk := (P + Length(Needle) > Length(Hay)) or (not IsWordChar(Hay[P + Length(Needle)]));
        if not (LeftOk and RightOk) then Continue;
      end;
      SelectVisibleIndex(I);
      Exit(True);
    end;
  end
  else
  begin
    if AFromCurrent then StartIdx := CurIdx + 1 else StartIdx := 0;
    for I := StartIdx to VisibleCount - 1 do
    begin
      RawIdx := MapVisibleToRaw(I);
      if RawIdx < 0 then Continue;
      Hay := Loaded.Log.RawStr(Loaded.Log[RawIdx].RawOffset, Loaded.Log[RawIdx].RawLen);
      if not AMatchCase then
        Hay := LowerCase(Hay);
      P := Pos(Needle, Hay);
      if P <= 0 then Continue;
      if AWholeWords then
      begin
        LeftOk := (P = 1) or (not IsWordChar(Hay[P - 1]));
        RightOk := (P + Length(Needle) > Length(Hay)) or (not IsWordChar(Hay[P + Length(Needle)]));
        if not (LeftOk and RightOk) then Continue;
      end;
      SelectVisibleIndex(I);
      Exit(True);
    end;
  end;
end;

procedure DrawListItem(State: TLogViewState; DIS: PDrawItemStruct);
var
  R: TRect;
  Brush: HBRUSH;
  Txt: AnsiString;
  RawPtr: PAnsiChar;
  RawLen: Integer;
  RawIdx: Integer;
  E: TLogEntry;
  Lvl: TLogLevel;
  Bg, Fg: COLORREF;
  SepX: Integer;
  LineCol: COLORREF;
  Pen, OldPen: HPEN;
  Num, NumText: string;
  Pad: Integer;
  TextR: TRect;
begin
  if (State = nil) or (DIS = nil) then
    Exit;
  if Integer(DIS^.itemID) < 0 then
    Exit;
  if DIS^.itemID >= UINT(State.VisibleCount) then
    Exit;

  RawIdx := State.MapVisibleToRaw(DIS^.itemID);
  if RawIdx < 0 then
    Exit;

  E := State.Loaded.Log[RawIdx];
  Lvl := E.Level;
  Bg := State.BgColor(Lvl);
  Fg := State.FgColor(Lvl);
  RawLen := E.RawLen;
  if RawLen > 0 then
    RawPtr := State.Loaded.Log.RawPtr(E.RawOffset)
  else
    RawPtr := nil;
  State.ApplyColorRules(E, Lvl, Bg, Fg);
  if (DIS^.itemState and ODS_SELECTED) <> 0 then
  begin
    Bg := RGB(0, 120, 215);
    Fg := RGB(255, 255, 255);
  end;

  R := DIS^.rcItem;
  Brush := CreateSolidBrush(Bg);
  FillRect(DIS^.hDC, R, Brush);
  DeleteObject(Brush);

  if AppSettings.ShowLineNumbers then
  begin
    SepX := DIS^.rcItem.Left + 4 + (AppSettings.LineNumberWidth + 1) * State.CharWidth;
    if SepX < DIS^.rcItem.Left then
      SepX := DIS^.rcItem.Left;
    if SepX > DIS^.rcItem.Right then
      SepX := DIS^.rcItem.Right;
    LineCol := RGB(
      (GetRValue(Bg) * 2 + GetRValue(Fg)) div 3,
      (GetGValue(Bg) * 2 + GetGValue(Fg)) div 3,
      (GetBValue(Bg) * 2 + GetBValue(Fg)) div 3
    );
    Pen := CreatePen(PS_SOLID, 1, LineCol);
    OldPen := SelectObject(DIS^.hDC, Pen);
    MoveToEx(DIS^.hDC, SepX, DIS^.rcItem.Top, nil);
    LineTo(DIS^.hDC, SepX, DIS^.rcItem.Bottom);
    SelectObject(DIS^.hDC, OldPen);
    DeleteObject(Pen);
  end;

  SetTextColor(DIS^.hDC, Fg);
  SetBkMode(DIS^.hDC, TRANSPARENT);
  if State.FontHandle <> 0 then
    SelectObject(DIS^.hDC, State.FontHandle);

  if AppSettings.WordWrap then
  begin
    TextR := DIS^.rcItem;
    Inc(TextR.Top, 1);
    Dec(TextR.Right, 2);

    if AppSettings.ShowLineNumbers then
    begin
      Num := IntToStr(E.LineNo);
      Pad := Max(0, AppSettings.LineNumberWidth - Length(Num));
      NumText := StringOfChar(' ', Pad) + Num + ' ';
      TextOutA(DIS^.hDC, DIS^.rcItem.Left + 4, DIS^.rcItem.Top + 1, PAnsiChar(AnsiString(NumText)), Length(NumText));
      TextR.Left := DIS^.rcItem.Left + 4 + (AppSettings.LineNumberWidth + 1) * State.CharWidth + 2;
    end
    else
      TextR.Left := DIS^.rcItem.Left + 4;

    if (RawPtr <> nil) and (RawLen > 0) then
      DrawTextA(DIS^.hDC, RawPtr, RawLen, TextR,
        DT_WORDBREAK or DT_NOPREFIX or DT_LEFT);
  end
  else
  begin
    Txt := State.LineText(DIS^.itemID);
    Inc(R.Left, 4);
    DrawTextA(DIS^.hDC, PAnsiChar(Txt), Length(Txt), R,
      DT_SINGLELINE or DT_VCENTER or DT_LEFT or DT_NOPREFIX);
  end;
end;

procedure DrawStatusStats(State: TLogViewState; DIS: PDrawItemStruct);
var
  R: TRect;
  B: HBRUSH;
  S_E, S_W, S_I: string;
  LastStat: TDateTime;
  X, Y, TotalW: Integer;
  FontNormal, FontBold, OldFont, PrevFont: HGDIOBJ;
  LF: LOGFONT;
  Sz: TSize;
  function Ts(const D: TDateTime): string;
  begin
    if D > 0 then
      Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', D)
    else
      Result := '-';
  end;
  function IsLatest(const D: TDateTime): Boolean;
  begin
    Result := (LastStat > 0) and (D = LastStat);
  end;
  function PartWidth(const S: string; Bold: Boolean): Integer;
  begin
    if Bold and (FontBold <> 0) then
      PrevFont := SelectObject(DIS^.hDC, FontBold)
    else
      PrevFont := SelectObject(DIS^.hDC, FontNormal);
    if (S <> '') and GetTextExtentPoint32(DIS^.hDC, PChar(S), Length(S), Sz) then
      Result := Sz.cx
    else
      Result := 0;
    SelectObject(DIS^.hDC, PrevFont);
  end;
begin
  if (State = nil) or (DIS = nil) then
    Exit;
  if DIS^.itemID <> 1 then
    Exit;

  R := DIS^.rcItem;
  B := CreateSolidBrush(GetSysColor(COLOR_3DFACE));
  FillRect(DIS^.hDC, R, B);
  DeleteObject(B);

  FontNormal := HGDIOBJ(SendMessage(State.StatusHandle, WM_GETFONT, 0, 0));
  if FontNormal = 0 then
    FontNormal := GetStockObject(DEFAULT_GUI_FONT);
  FontBold := 0;
  FillChar(LF, SizeOf(LF), 0);
  if (FontNormal <> 0) and (GetObject(FontNormal, SizeOf(LF), @LF) = SizeOf(LF)) then
  begin
    LF.lfWeight := FW_BOLD;
    FontBold := CreateFontIndirect(LF);
  end;

  OldFont := SelectObject(DIS^.hDC, FontNormal);
  SetBkMode(DIS^.hDC, TRANSPARENT);
  SetTextColor(DIS^.hDC, GetSysColor(COLOR_BTNTEXT));

  S_E := Format('E: %d (%s)', [State.StatECount, Ts(State.StatELast)]);
  S_W := Format('W: %d (%s)', [State.StatWCount, Ts(State.StatWLast)]);
  S_I := Format('I: %d (%s)', [State.StatICount, Ts(State.StatILast)]);

  LastStat := 0;
  if State.StatELast > LastStat then LastStat := State.StatELast;
  if State.StatWLast > LastStat then LastStat := State.StatWLast;
  if State.StatILast > LastStat then LastStat := State.StatILast;

  TotalW :=
    PartWidth(S_E, IsLatest(State.StatELast)) +
    PartWidth('  ', False) +
    PartWidth(S_W, IsLatest(State.StatWLast)) +
    PartWidth('  ', False) +
    PartWidth(S_I, IsLatest(State.StatILast));

  X := R.Right - TotalW - 4;
  if X < R.Left + 2 then X := R.Left + 2;
  if GetTextExtentPoint32(DIS^.hDC, PChar('A'), 1, Sz) then
    Y := R.Top + (R.Bottom - R.Top - Sz.cy) div 2
  else
    Y := R.Top + 2;
  if Y < R.Top then Y := R.Top;

  if IsLatest(State.StatELast) and (FontBold <> 0) then
    SelectObject(DIS^.hDC, FontBold)
  else
    SelectObject(DIS^.hDC, FontNormal);
  TextOut(DIS^.hDC, X, Y, PChar(S_E), Length(S_E));
  Inc(X, PartWidth(S_E, IsLatest(State.StatELast)));

  SelectObject(DIS^.hDC, FontNormal);
  TextOut(DIS^.hDC, X, Y, PChar('  '), 2);
  Inc(X, PartWidth('  ', False));

  if IsLatest(State.StatWLast) and (FontBold <> 0) then
    SelectObject(DIS^.hDC, FontBold)
  else
    SelectObject(DIS^.hDC, FontNormal);
  TextOut(DIS^.hDC, X, Y, PChar(S_W), Length(S_W));
  Inc(X, PartWidth(S_W, IsLatest(State.StatWLast)));

  SelectObject(DIS^.hDC, FontNormal);
  TextOut(DIS^.hDC, X, Y, PChar('  '), 2);
  Inc(X, PartWidth('  ', False));

  if IsLatest(State.StatILast) and (FontBold <> 0) then
    SelectObject(DIS^.hDC, FontBold)
  else
    SelectObject(DIS^.hDC, FontNormal);
  TextOut(DIS^.hDC, X, Y, PChar(S_I), Length(S_I));

  SelectObject(DIS^.hDC, OldFont);
  if FontBold <> 0 then
    DeleteObject(FontBold);
end;

function LogViewWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  State: TLogViewState;
  CS: PCREATESTRUCT;
  MI: PMeasureItemStruct;
  DI: PDrawItemStruct;
  PS: TPaintStruct;
  Input: string;
  N: Integer;
  DT: TDateTime;
  PaintDC: HDC;
  FillR: TRect;
  FillB: HBRUSH;
begin
  if (Msg = WM_KEYDOWN) or (Msg = WM_SYSKEYDOWN) or (Msg = WM_CHAR) then
  begin
    State := GetState(Wnd);
    if (State <> nil) and State.IsListerMode and (not AppSettings.CloseOnEscInLister) then
      if (((Msg = WM_KEYDOWN) or (Msg = WM_SYSKEYDOWN)) and (WParam = VK_ESCAPE)) or
         ((Msg = WM_CHAR) and (WParam = 27)) then
      begin
        Result := 0;
        Exit;
      end;
  end;

  case Msg of
    WM_CREATE:
      begin
        CS := PCREATESTRUCT(LParam);
        State := TLogViewState(CS^.lpCreateParams);
        State.WindowHandle := Wnd;
        State.IsListerMode := IsLikelyListerMode(State.ParentHandle, State.ShowFlags);
        SetWindowLongPtr(Wnd, GWLP_USERDATA, PtrInt(State));
        SendMessage(Wnd, WM_SETREDRAW, 0, 0);
        if State.IsListerMode and (State.ParentHandle <> 0) and IsWindow(State.ParentHandle) then
        begin
          SetProp(State.ParentHandle, PChar(PROP_PARENT_STATE), HANDLE(State));
          State.ParentPrevWndProc := WNDPROC(SetWindowLongPtr(State.ParentHandle, GWLP_WNDPROC, PtrInt(@ListerParentWndProc)));
          State.ParentSubclassed := Assigned(State.ParentPrevWndProc);
        end;

        State.BuildToolbar;
        AttachEscForwarder(Wnd, State);
        State.EnsureListMode;

        State.FollowTail := True;
        State.ApplySettingsToControls;
        State.UpdateLayout;
        if not State.LoadFile then
          State.SyncListItems;
        SendMessage(Wnd, WM_SETREDRAW, 1, 0);
        RedrawWindow(Wnd, nil, 0, RDW_INVALIDATE or RDW_ALLCHILDREN or RDW_UPDATENOW);
        Result := 0;
        Exit;
      end;

    WM_SIZE:
      begin
        State := GetState(Wnd);
        if State <> nil then
          State.UpdateLayout;
        Result := 0;
        Exit;
      end;

    WM_TIMER:
      begin
        State := GetState(Wnd);
        if State = nil then
          Exit(0);
        case WParam of
          TIMER_FILTER:
            begin
              KillTimer(Wnd, TIMER_FILTER);
              State.SearchTextLower := LowerCase(State.SearchText);
              State.ApplyFilter;
            end;
          TIMER_TAIL:
            State.TailTick;
        end;
        Result := 0;
        Exit;
      end;

    WM_COMMAND:
      begin
        State := GetState(Wnd);
        if State = nil then
          Exit(0);

        case LOWORD(WParam) of
          IDC_EDT_SEARCH:
            if HIWORD(WParam) = EN_CHANGE then
            begin
              SetLength(State.SearchText, GetWindowTextLength(State.EdtSearch));
              if Length(State.SearchText) > 0 then
                GetWindowText(State.EdtSearch, PChar(State.SearchText), Length(State.SearchText) + 1);
              SetTimer(Wnd, TIMER_FILTER, FILTER_DEBOUNCE_MS, nil);
            end;

          IDC_BTN_CLEAR:
            begin
              SetWindowText(State.EdtSearch, '');
              State.SearchText := '';
              State.SearchTextLower := '';
              State.ApplyFilter;
            end;

          IDC_BTN_PREV_ERR: State.GotoLevel(False, lError);
          IDC_BTN_NEXT_ERR: State.GotoLevel(True, lError);
          IDC_BTN_PREV_WARN: State.GotoLevel(False, lWarn);
          IDC_BTN_NEXT_WARN: State.GotoLevel(True, lWarn);
          IDC_BTN_PREV_INFO: State.GotoLevel(False, lInfo);
          IDC_BTN_NEXT_INFO: State.GotoLevel(True, lInfo);

          IDC_CHK_FOLLOW:
            begin
              State.FollowTail :=
                SendMessage(State.ChkFollow, BM_GETCHECK, 0, 0) = BST_CHECKED;
              if State.FollowTail and (State.VisibleCount > 0) then
                State.SelectVisibleIndex(State.VisibleCount - 1);
            end;

          IDC_CHK_LINENUM:
            begin
              AppSettings.ShowLineNumbers :=
                SendMessage(State.ChkLineNum, BM_GETCHECK, 0, 0) = BST_CHECKED;
              SaveSettings;
              State.ApplyFilter;
            end;

          IDC_CHK_TAIL:
            begin
              AppSettings.TailEnabled :=
                SendMessage(State.ChkTail, BM_GETCHECK, 0, 0) = BST_CHECKED;
              SaveSettings;
              if AppSettings.TailEnabled then
                State.StartTail
              else
                State.StopTail;
            end;

          IDC_BTN_OPTIONS:
            begin
              if ShowPluginOptions(Wnd, State.Loaded.Format) then
              begin
                State.ApplySettingsToControls;
                State.SearchTextLower := LowerCase(State.SearchText);
                State.ApplyFilter;
                if AppSettings.TailEnabled then
                  State.StartTail
                else
                  State.StopTail;
              end;
            end;

          IDM_CTX_COPYLINE:
            State.CopyCurrentLine;
          IDM_CTX_COPYVISIBLE:
            State.CopyAllVisible;
          IDM_CTX_LINENUM:
            begin
              AppSettings.ShowLineNumbers := not AppSettings.ShowLineNumbers;
              SaveSettings;
              SendMessage(State.ChkLineNum, BM_SETCHECK, Ord(AppSettings.ShowLineNumbers), 0);
              State.ApplyFilter;
            end;
          IDM_CTX_WORDWRAP:
            begin
              AppSettings.WordWrap := not AppSettings.WordWrap;
              SaveSettings;
              State.EnsureListMode;
              State.UpdateLayout;
              State.ApplyFilter;
            end;
          IDM_CTX_GOTOLINE:
            begin
              if PromptText(Wnd, 'Go to line', 'Line number:', '', Input) then
                if TryStrToInt(Trim(Input), N) then
                  State.GotoLineNumber(N);
            end;
          IDM_CTX_GOTODT:
            begin
              if PromptDateTime(Wnd, DT) then
                State.GotoDateTime(DT);
            end;
        end;
        Result := 0;
        Exit;
      end;

    WM_CONTEXTMENU:
      begin
        State := GetState(Wnd);
        if (State <> nil) and ((HWND(WParam) = State.ListHandle) or (HWND(WParam) = Wnd)) then
        begin
          State.ShowContextMenu(SmallInt(LOWORD(LParam)), SmallInt(HIWORD(LParam)));
          Result := 0;
          Exit;
        end;
      end;

    WM_MEASUREITEM:
      begin
        State := GetState(Wnd);
        MI := PMeasureItemStruct(LParam);
        if (State <> nil) and (MI <> nil) and (MI^.CtlID = IDC_LOG_LIST) then
        begin
          MI^.itemHeight := State.MeasureVisibleItemHeight(MI^.itemID);
          Result := 1;
          Exit;
        end;
      end;

    WM_DRAWITEM:
      begin
        State := GetState(Wnd);
        DI := PDrawItemStruct(LParam);
        if (State <> nil) and (DI <> nil) and (DI^.CtlID = IDC_LOG_LIST) then
        begin
          DrawListItem(State, DI);
          Result := 1;
          Exit;
        end;
        if (State <> nil) and (DI <> nil) and (DI^.CtlID = IDC_STATUS) then
        begin
          DrawStatusStats(State, DI);
          Result := 1;
          Exit;
        end;
      end;

    WM_ERASEBKGND:
      begin
        PaintDC := HDC(WParam);
        if PaintDC <> 0 then
        begin
          GetClientRect(Wnd, FillR);
          FillR.Bottom := Min(FillR.Bottom, TOOLBAR_H);
          FillB := CreateSolidBrush(TOOLBAR_BG_COLOR);
          FillRect(PaintDC, FillR, FillB);
          DeleteObject(FillB);
        end;
        Result := 1;
        Exit;
      end;

    WM_PAINT:
      begin
        PaintDC := BeginPaint(Wnd, PS);
        if PaintDC <> 0 then
        begin
          GetClientRect(Wnd, FillR);
          FillR.Bottom := Min(FillR.Bottom, TOOLBAR_H);
          FillB := CreateSolidBrush(TOOLBAR_BG_COLOR);
          FillRect(PaintDC, FillR, FillB);
          DeleteObject(FillB);
        end;
        EndPaint(Wnd, PS);
        Result := 0;
        Exit;
      end;

    WM_DESTROY:
      begin
        KillTimer(Wnd, TIMER_FILTER);
        KillTimer(Wnd, TIMER_TAIL);
        State := GetState(Wnd);
        if State <> nil then
        begin
          if State.ParentSubclassed and (State.ParentHandle <> 0) and IsWindow(State.ParentHandle) then
          begin
            if Assigned(State.ParentPrevWndProc) then
              SetWindowLongPtr(State.ParentHandle, GWLP_WNDPROC, PtrInt(State.ParentPrevWndProc));
            RemoveProp(State.ParentHandle, PChar(PROP_PARENT_STATE));
            State.ParentPrevWndProc := nil;
            State.ParentSubclassed := False;
          end;
          if (State.ListHandle <> 0) and IsWindow(State.ListHandle) then
          begin
            if Assigned(State.PrevListWndProc) then
              SetWindowLongPtr(State.ListHandle, GWLP_WNDPROC, PtrInt(State.PrevListWndProc));
            SetWindowLongPtr(State.ListHandle, GWLP_USERDATA, 0);
          end;
          DetachEscForwarder(State.BtnPrevErr);
          DetachEscForwarder(State.BtnNextErr);
          DetachEscForwarder(State.BtnPrevWarn);
          DetachEscForwarder(State.BtnNextWarn);
          DetachEscForwarder(State.BtnPrevInfo);
          DetachEscForwarder(State.BtnNextInfo);
          DetachEscForwarder(State.ChkTail);
          DetachEscForwarder(State.ChkFollow);
          DetachEscForwarder(State.ChkLineNum);
          DetachEscForwarder(State.BtnOptions);
          DetachEscForwarder(State.EdtSearch);
          DetachEscForwarder(State.BtnClear);
          DetachEscForwarder(Wnd);
          if (State.StatusHandle <> 0) and IsWindow(State.StatusHandle) then
          begin
            SendMessage(State.StatusHandle, SB_SETTEXT, 1, 0);
            SendMessage(State.StatusHandle, SB_SETTEXT, 0, 0);
          end;
          SetWindowLongPtr(Wnd, GWLP_USERDATA, 0);
          State.Free;
        end;
        Result := 0;
        Exit;
      end;
  end;

  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

procedure EnsureWrapViewClass;
var
  WC: WNDCLASS;
begin
  if Windows.GetClassInfo(hInstance, LOGVIEW_WRAPVIEW_WNDCLASS, WC) then
    Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.style := CS_HREDRAW or CS_VREDRAW;
  WC.lpfnWndProc := @WrapViewWndProc;
  WC.hInstance := hInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := COLOR_WINDOW + 1;
  WC.lpszClassName := LOGVIEW_WRAPVIEW_WNDCLASS;
  Windows.RegisterClass(WC);
end;

procedure EnsureWindowClass;
var
  WC: WNDCLASS;
begin
  EnsureWrapViewClass;
  if Windows.GetClassInfo(hInstance, LOGVIEW_WNDCLASS, WC) then
    Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.style := CS_HREDRAW or CS_VREDRAW;
  WC.lpfnWndProc := @LogViewWndProc;
  WC.hInstance := hInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := CreateSolidBrush(TOOLBAR_BG_COLOR);
  WC.lpszClassName := LOGVIEW_WNDCLASS;
  Windows.RegisterClass(WC);
end;

function CreateLogViewWindow(ParentWin: HWND; const FilePath: string; ShowFlags: Integer): HWND;
var
  State: TLogViewState;
begin
  EnsureWindowClass;
  State := TLogViewState.Create;
  State.ParentHandle := ParentWin;
  State.FileName := FilePath;
  State.ShowFlags := ShowFlags;

  Result := CreateWindowEx(
    0, LOGVIEW_WNDCLASS, '',
    WS_CHILD or WS_VISIBLE or WS_CLIPCHILDREN or WS_CLIPSIBLINGS,
    0, 0, 100, 100,
    ParentWin, 0, hInstance, State);

  if Result = 0 then
    State.Free;
end;

procedure DestroyLogViewWindow(Wnd: HWND);
begin
  if (Wnd <> 0) and IsWindow(Wnd) then
    DestroyWindow(Wnd);
end;

function SendLogViewCommand(Wnd: HWND; Command, Parameter: Integer): Integer;
var
  State: TLogViewState;
begin
  Result := LISTPLUGIN_OK;
  State := GetState(Wnd);
  if (State = nil) or (State.ListHandle = 0) then
    Exit(LISTPLUGIN_ERROR);

  case Command of
    lc_copy:
      if not State.CopySelection then
        Result := LISTPLUGIN_ERROR;
    lc_selectall:
      if State.VisibleCount > 0 then
        State.SelectAllVisible;
    lc_newparams:
      begin
        LoadSettings;
        State.ApplySettingsToControls;
        State.ApplyFilter;
        if AppSettings.TailEnabled then
          State.StartTail
        else
          State.StopTail;
      end;
    lc_setpercent:
      if State.VisibleCount > 0 then
        State.SetTopIndex(MulDiv(State.VisibleCount - 1, Parameter, 100));
  end;
end;

function SearchLogViewText(Wnd: HWND; const SearchString: string; SearchParameter: Integer): Integer;
var
  State: TLogViewState;
  Txt: string;
  Found: Boolean;
  MatchCase, WholeWords, Backwards, FindFirst: Boolean;
begin
  Result := LISTPLUGIN_ERROR;
  State := GetState(Wnd);
  if (State = nil) or (State.ListHandle = 0) then
    Exit;

  MatchCase := (SearchParameter and lcs_matchcase) <> 0;
  WholeWords := (SearchParameter and lcs_wholewords) <> 0;
  Backwards := (SearchParameter and lcs_backwards) <> 0;
  FindFirst := (SearchParameter and lcs_findfirst) <> 0;

  Txt := SearchString;
  if Txt = '' then
    Txt := State.LastSearchText;
  if Txt = '' then
    Exit;

  State.LastSearchText := Txt;
  State.LastSearchFlags := SearchParameter;
  Found := State.FindText(Txt, MatchCase, WholeWords, Backwards, not FindFirst);
  if Found then
    Result := LISTPLUGIN_OK;
end;

function SearchLogViewDialog(Wnd: HWND; FindNext: Integer): Integer;
var
  State: TLogViewState;
  Backwards: Boolean;
begin
  Result := LISTPLUGIN_ERROR;
  State := GetState(Wnd);
  if (State = nil) or (State.LastSearchText = '') then
    Exit;
  Backwards := FindNext = 0;
  if State.FindText(State.LastSearchText,
      (State.LastSearchFlags and lcs_matchcase) <> 0,
      (State.LastSearchFlags and lcs_wholewords) <> 0,
      Backwards,
      True) then
    Result := LISTPLUGIN_OK;
end;

end.
