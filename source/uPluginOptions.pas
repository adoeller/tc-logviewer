unit uPluginOptions;

{$mode objfpc}{$H+}

interface

uses
  Windows, uLogTypes;

function ShowPluginOptions(AOwner: HWND; ADetected: TLogFormat): Boolean;

implementation

uses
  Messages, SysUtils, Math, CommCtrl, CommDlg, uSettings;

const
  OPT_CLASS_NAME = 'WLXLogOptionsWindow';
  OPT_PAGE_CLASS = 'WLXLogOptionsPage';

  IDC_TAB = 3000;
  IDC_DETECTED = 3001;

  IDC_VIEW_LINENUM = 3101;
  IDC_VIEW_LINEWIDTH = 3102;
  IDC_VIEW_WORDWRAP = 3103;
  IDC_VIEW_HSCROLL = 3104;
  IDC_VIEW_FONTNAME = 3105;
  IDC_VIEW_FONTSIZE = 3106;
  IDC_VIEW_PICKFONT = 3107;
  IDC_VIEW_THEMEMODE = 3108;
  IDC_VIEW_FONTPREVIEW = 3109;
  IDC_VIEW_CLOSEESC = 3110;

  IDC_CLR_BG_BASE = 3200;
  IDC_CLR_FG_BASE = 3210;
  IDC_CLR_PALETTE = 3220;
  IDC_CLR_BG_SWATCH_BASE = 3230;
  IDC_CLR_FG_SWATCH_BASE = 3240;

  IDC_FMT_AUTODET = 3301;
  IDC_FMT_FORCE = 3302;
  IDC_FMT_MODE = 3303;
  IDC_FMT_DELIM = 3304;
  IDC_FMT_TSFMT = 3305;
  IDC_FMT_TSSTART = 3306;
  IDC_FMT_TSLEN = 3307;
  IDC_FMT_LVLSTART = 3308;
  IDC_FMT_LVLLEN = 3309;
  IDC_FMT_SRCSTART = 3310;
  IDC_FMT_SRCLEN = 3311;
  IDC_FMT_CUSTOMMODE_LBL = 3312;
  IDC_FMT_DELIM_LBL = 3313;
  IDC_FMT_TSFMT_LBL = 3314;
  IDC_FMT_FIELDS_LBL = 3315;
  IDC_FMT_POS_TS_LBL = 3316;
  IDC_FMT_POS_LVL_LBL = 3317;
  IDC_FMT_POS_SRC_LBL = 3318;
  IDC_FMT_FIELDNO_BASE = 3320;
  IDC_FMT_FIELDROLE_BASE = 3330;

  IDC_TAIL_ENABLE = 3401;
  IDC_TAIL_MS = 3402;

  IDC_RULE_LIST = 3501;
  IDC_RULE_PATTERN = 3502;
  IDC_RULE_BG = 3503;
  IDC_RULE_FG = 3504;
  IDC_RULE_ENABLED = 3505;
  IDC_RULE_USELEVEL = 3506;
  IDC_RULE_LEVEL = 3507;
  IDC_RULE_ADD = 3508;
  IDC_RULE_UPDATE = 3509;
  IDC_RULE_DELETE = 3510;
  IDC_RULE_AUTOFG = 3511;

type
  PThemeColors = ^TThemeColors;

  TOptionsState = class
  public
    Owner: HWND;
    Wnd: HWND;
    Done: Boolean;
    Accepted: Boolean;
    DetectedFmt: TLogFormat;
    S: TAppSettings;
    Tab: HWND;
    Pages: array[0..4] of HWND;
    DetectedLbl: HWND;
    PreviewFont: HFONT;
    UiFont: HFONT;
    SwatchBg: array[0..6] of COLORREF;
    SwatchFg: array[0..6] of COLORREF;
    RuleBgColor: COLORREF;
    RuleFgColor: COLORREF;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TOptionsState.Create;
begin
  inherited Create;
  S := AppSettings;
  PreviewFont := 0;
  UiFont := 0;
  RuleBgColor := AppSettings.BgColor;
  RuleFgColor := NO_COLOR_OVERRIDE;
end;

destructor TOptionsState.Destroy;
begin
  if PreviewFont <> 0 then
    DeleteObject(PreviewFont);
  if UiFont <> 0 then
    DeleteObject(UiFont);
  inherited Destroy;
end;

function SetFontForChildProc(Wnd: HWND; Data: LPARAM): BOOL; stdcall;
begin
  SendMessage(Wnd, WM_SETFONT, WPARAM(Data), LPARAM(1));
  Result := True;
end;

procedure ApplyNormalDialogFont(St: TOptionsState);
var
  BaseFont: HGDIOBJ;
  LF: Windows.LOGFONTA;
begin
  if St.UiFont <> 0 then
  begin
    DeleteObject(St.UiFont);
    St.UiFont := 0;
  end;

  BaseFont := GetStockObject(DEFAULT_GUI_FONT);
  if (BaseFont <> 0) and (GetObject(BaseFont, SizeOf(LF), @LF) = SizeOf(LF)) then
  begin
    LF.lfWeight := FW_NORMAL;
    St.UiFont := CreateFontIndirect(LF);
  end;

  if St.UiFont <> 0 then
  begin
    SendMessage(St.Wnd, WM_SETFONT, WPARAM(St.UiFont), LPARAM(1));
    EnumChildWindows(St.Wnd, @SetFontForChildProc, LPARAM(St.UiFont));
  end;
end;

function GetState(Wnd: HWND): TOptionsState; inline;
begin
  Result := TOptionsState(GetWindowLongPtr(Wnd, GWLP_USERDATA));
end;

function FindChildByID(AParent: HWND; AID: Integer): HWND;
var
  C, R: HWND;
begin
  Result := 0;
  C := GetWindow(AParent, GW_CHILD);
  while C <> 0 do
  begin
    if GetDlgCtrlID(C) = AID then
      Exit(C);
    R := FindChildByID(C, AID);
    if R <> 0 then
      Exit(R);
    C := GetWindow(C, GW_HWNDNEXT);
  end;
end;

function GetEditText(Wnd: HWND): string;
var
  L: Integer;
  U: UnicodeString;
begin
  Result := '';
  L := GetWindowTextLengthW(Wnd);
  SetLength(U, L);
  if L > 0 then
    GetWindowTextW(Wnd, PWideChar(U), L + 1);
  Result := UTF8Encode(U);
end;

procedure SetEditText(Wnd: HWND; const S: string);
begin
  SetWindowTextW(Wnd, PWideChar(UTF8Decode(S)));
end;

function ReadEditInt(AEdit: HWND; ADefault: Integer): Integer;
var
  OK: LongBool;
begin
  Result := GetDlgItemInt(GetParent(AEdit), GetDlgCtrlID(AEdit), OK, False);
  if not OK then
    Result := ADefault;
end;

function ColorToText(C: COLORREF): string;
begin
  Result := Format('#%.2x%.2x%.2x', [GetRValue(C), GetGValue(C), GetBValue(C)]);
end;

procedure InitCommonCtrls;
var
  ICC: TInitCommonControlsEx;
begin
  FillChar(ICC, SizeOf(ICC), 0);
  ICC.dwSize := SizeOf(ICC);
  ICC.dwICC := ICC_TAB_CLASSES;
  InitCommonControlsEx(ICC);
end;

procedure GetPaletteColorByIndex(const C: TThemeColors; Index: Integer; out Bg, Fg: COLORREF);
begin
  case Index of
    0: begin Bg := C.BgColor; Fg := C.FgColor; end;
    1: begin Bg := C.ErrBg; Fg := C.ErrFg; end;
    2: begin Bg := C.WarnBg; Fg := C.WarnFg; end;
    3: begin Bg := C.InfoBg; Fg := C.InfoFg; end;
    4: begin Bg := C.DebugBg; Fg := C.DebugFg; end;
    5: begin Bg := C.TraceBg; Fg := C.TraceFg; end;
  else
    begin Bg := C.CustomBg; Fg := C.CustomFg; end;
  end;
end;

procedure SetPaletteColorByIndex(var C: TThemeColors; Index: Integer; IsFg: Boolean; Col: COLORREF);
begin
  case Index of
    0: if IsFg then C.FgColor := Col else C.BgColor := Col;
    1: if IsFg then C.ErrFg := Col else C.ErrBg := Col;
    2: if IsFg then C.WarnFg := Col else C.WarnBg := Col;
    3: if IsFg then C.InfoFg := Col else C.InfoBg := Col;
    4: if IsFg then C.DebugFg := Col else C.DebugBg := Col;
    5: if IsFg then C.TraceFg := Col else C.TraceBg := Col;
  else
    if IsFg then C.CustomFg := Col else C.CustomBg := Col;
  end;
end;

function CurrentPalettePtr(St: TOptionsState): PThemeColors;
var
  Sel: Integer;
  H: HWND;
begin
  Result := @St.S.LightColors;
  H := FindChildByID(St.Wnd, IDC_CLR_PALETTE);
  if H = 0 then
    Exit;
  Sel := SendMessage(H, CB_GETCURSEL, 0, 0);
  if Sel = 1 then
    Result := @St.S.DarkColors;
end;

function PickColor(AOwner: HWND; Cur: COLORREF; out NewColor: COLORREF): Boolean;
var
  CC: TChooseColor;
  Cust: array[0..15] of COLORREF;
begin
  FillChar(CC, SizeOf(CC), 0);
  FillChar(Cust, SizeOf(Cust), 0);
  CC.lStructSize := SizeOf(CC);
  CC.hwndOwner := AOwner;
  CC.rgbResult := Cur;
  CC.lpCustColors := @Cust[0];
  CC.Flags := CC_RGBINIT or CC_FULLOPEN;
  Result := ChooseColor(@CC);
  if Result then
    NewColor := CC.rgbResult;
end;

function FontEnumProc(var E: Windows.ENUMLOGFONTEXA; var M: Windows.NEWTEXTMETRICEXA;
  FontType: LongInt; LParam: LPARAM): LongInt; stdcall;
var
  Combo: HWND;
  S: string;
  P: PChar;
begin
  if PtrUInt(@M) = 0 then ;
  if FontType = 0 then ;
  Combo := HWND(LParam);
  S := string(E.elfLogFont.lfFaceName);
  P := PChar(S);
  if SendMessage(Combo, CB_FINDSTRINGEXACT, -1, PtrInt(P)) = CB_ERR then
    SendMessage(Combo, CB_ADDSTRING, 0, PtrInt(P));
  Result := 1;
end;

procedure FillFontCombo(Combo: HWND; const Current: string);
const
  FallbackFonts: array[0..3] of string = ('Courier New', 'Consolas', 'Lucida Console', 'Segoe UI');
var
  LF: Windows.LOGFONTA;
  DC: HDC;
  I: Integer;
begin
  if Combo = 0 then Exit;
  SendMessage(Combo, CB_RESETCONTENT, 0, 0);
  FillChar(LF, SizeOf(LF), 0);
  LF.lfCharSet := DEFAULT_CHARSET;
  DC := GetDC(0);
  EnumFontFamiliesEx(DC, LF, @FontEnumProc, LPARAM(Combo), 0);
  ReleaseDC(0, DC);

  if SendMessage(Combo, CB_GETCOUNT, 0, 0) <= 0 then
    for I := Low(FallbackFonts) to High(FallbackFonts) do
      SendMessage(Combo, CB_ADDSTRING, 0, LPARAM(PChar(FallbackFonts[I])));

  if (Current <> '') and (SendMessage(Combo, CB_FINDSTRINGEXACT, WPARAM(-1), LPARAM(PChar(Current))) = CB_ERR) then
    SendMessage(Combo, CB_ADDSTRING, 0, LPARAM(PChar(Current)));
end;

function ComboSelectedText(H: HWND): string;
var
  Sel, L: Integer;
begin
  Result := '';
  if H = 0 then Exit;
  Sel := SendMessage(H, CB_GETCURSEL, 0, 0);
  if Sel <> CB_ERR then
  begin
    L := SendMessage(H, CB_GETLBTEXTLEN, Sel, 0);
    if L > 0 then
    begin
      SetLength(Result, L);
      SendMessage(H, CB_GETLBTEXT, Sel, LPARAM(PChar(Result)));
      Result := Trim(Result);
    end;
  end
  else
    Result := Trim(GetEditText(H));
end;

procedure UpdateFontPreview(St: TOptionsState);
var
  FontName: string;
  FontSize: Integer;
  FontCombo, SizeEdit, PrevLbl: HWND;
  ScreenDC: HDC;
  PPI: Integer;
begin
  FontCombo := FindChildByID(St.Wnd, IDC_VIEW_FONTNAME);
  SizeEdit := FindChildByID(St.Wnd, IDC_VIEW_FONTSIZE);
  PrevLbl := FindChildByID(St.Wnd, IDC_VIEW_FONTPREVIEW);
  if PrevLbl = 0 then
    Exit;

  FontName := ComboSelectedText(FontCombo);
  if FontName = '' then
    FontName := 'Courier New';
  FontSize := EnsureRange(ReadEditInt(SizeEdit, 9), 6, 36);

  if St.PreviewFont <> 0 then
  begin
    DeleteObject(St.PreviewFont);
    St.PreviewFont := 0;
  end;

  ScreenDC := GetDC(0);
  PPI := GetDeviceCaps(ScreenDC, LOGPIXELSY);
  ReleaseDC(0, ScreenDC);

  St.PreviewFont := CreateFont(
    -MulDiv(FontSize, PPI, 72),
    0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET,
    OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
    FIXED_PITCH or FF_MODERN, PChar(FontName));

  if St.PreviewFont <> 0 then
    SendMessage(PrevLbl, WM_SETFONT, WPARAM(St.PreviewFont), LPARAM(1));

  SetWindowText(PrevLbl, PChar('AaBbCcDdEe 1234 #@!  The quick brown fox'));
end;

procedure RefreshColorControls(St: TOptionsState);
const
  Names: array[0..6] of string = ('Default', 'ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE', 'Custom');
var
  I: Integer;
  Bg, Fg: COLORREF;
  C: PThemeColors;
  HB, HF: HWND;
begin
  C := CurrentPalettePtr(St);
  for I := 0 to 6 do
  begin
    GetPaletteColorByIndex(C^, I, Bg, Fg);
    HB := FindChildByID(St.Wnd, IDC_CLR_BG_BASE + I);
    HF := FindChildByID(St.Wnd, IDC_CLR_FG_BASE + I);
    if HB <> 0 then
      SetWindowText(HB, PChar('BG ' + ColorToText(Bg)));
    if HF <> 0 then
      SetWindowText(HF, PChar('FG ' + ColorToText(Fg)));

    St.SwatchBg[I] := Bg;
    St.SwatchFg[I] := Fg;
    InvalidateRect(FindChildByID(St.Wnd, IDC_CLR_BG_SWATCH_BASE + I), nil, True);
    InvalidateRect(FindChildByID(St.Wnd, IDC_CLR_FG_SWATCH_BASE + I), nil, True);
  end;
end;

function RuleLevelText(L: TLogLevel): string;
begin
  case L of
    lError: Result := 'ERROR';
    lWarn: Result := 'WARN';
    lInfo: Result := 'INFO';
    lDebug: Result := 'DEBUG';
    lTrace: Result := 'TRACE';
  else
    Result := 'Custom';
  end;
end;

procedure UpdateRuleColorButtons(St: TOptionsState);
var
  HBg, HFg, HUseLevel, HAutoFg, HLevel: HWND;
  UseLevel, AutoFg: Boolean;
begin
  HBg := FindChildByID(St.Wnd, IDC_RULE_BG);
  HFg := FindChildByID(St.Wnd, IDC_RULE_FG);
  HUseLevel := FindChildByID(St.Wnd, IDC_RULE_USELEVEL);
  HAutoFg := FindChildByID(St.Wnd, IDC_RULE_AUTOFG);
  HLevel := FindChildByID(St.Wnd, IDC_RULE_LEVEL);

  if HBg <> 0 then
    SetWindowText(HBg, PChar('BG ' + ColorToText(St.RuleBgColor)));
  if HFg <> 0 then
  begin
    if St.RuleFgColor = NO_COLOR_OVERRIDE then
      SetWindowText(HFg, 'FG Auto')
    else
      SetWindowText(HFg, PChar('FG ' + ColorToText(St.RuleFgColor)));
  end;

  UseLevel := (HUseLevel <> 0) and (SendMessage(HUseLevel, BM_GETCHECK, 0, 0) = BST_CHECKED);
  AutoFg := (HAutoFg <> 0) and (SendMessage(HAutoFg, BM_GETCHECK, 0, 0) = BST_CHECKED);

  if HBg <> 0 then
    EnableWindow(HBg, not UseLevel);
  if HFg <> 0 then
    EnableWindow(HFg, (not UseLevel) and (not AutoFg));
  if HAutoFg <> 0 then
    EnableWindow(HAutoFg, not UseLevel);
  if HLevel <> 0 then
    EnableWindow(HLevel, UseLevel);
end;

procedure RefreshRuleList(St: TOptionsState);
var
  I: Integer;
  H: HWND;
  R: TColorStringRule;
  S, EMark: string;
begin
  H := FindChildByID(St.Wnd, IDC_RULE_LIST);
  if H = 0 then
    Exit;
  SendMessage(H, LB_RESETCONTENT, 0, 0);
  for I := 0 to St.S.ColorRuleCount - 1 do
  begin
    R := St.S.ColorRules[I];
    if R.Enabled then EMark := 'x' else EMark := ' ';
    if R.UseLevel then
      S := Format('[%s] %s -> %s',
        [EMark, R.Pattern, RuleLevelText(R.Level)])
    else if R.FgColor = NO_COLOR_OVERRIDE then
      S := Format('[%s] %s -> BG %s / FG Auto',
        [EMark, R.Pattern, ColorToText(R.Color)])
    else
      S := Format('[%s] %s -> BG %s / FG %s',
        [EMark, R.Pattern, ColorToText(R.Color), ColorToText(R.FgColor)]);
    SendMessage(H, LB_ADDSTRING, 0, LPARAM(PChar(S)));
  end;
end;

procedure LoadRuleControls(St: TOptionsState; RuleIndex: Integer);
var
  R: TColorStringRule;
  H: HWND;
begin
  if (RuleIndex < 0) or (RuleIndex >= St.S.ColorRuleCount) then
    Exit;
  R := St.S.ColorRules[RuleIndex];
  SetEditText(FindChildByID(St.Wnd, IDC_RULE_PATTERN), R.Pattern);
  SendMessage(FindChildByID(St.Wnd, IDC_RULE_ENABLED), BM_SETCHECK, Ord(R.Enabled), 0);
  SendMessage(FindChildByID(St.Wnd, IDC_RULE_USELEVEL), BM_SETCHECK, Ord(R.UseLevel), 0);
  St.RuleBgColor := R.Color;
  St.RuleFgColor := R.FgColor;
  H := FindChildByID(St.Wnd, IDC_RULE_LEVEL);
  if H <> 0 then
    SendMessage(H, CB_SETCURSEL, Ord(R.Level), 0);
  SendMessage(FindChildByID(St.Wnd, IDC_RULE_AUTOFG), BM_SETCHECK, Ord(R.FgColor = NO_COLOR_OVERRIDE), 0);
  UpdateRuleColorButtons(St);
end;

function BuildRuleFromControls(St: TOptionsState; out R: TColorStringRule): Boolean;
var
  Sel: Integer;
  P: string;
begin
  FillChar(R, SizeOf(R), 0);
  P := Trim(GetEditText(FindChildByID(St.Wnd, IDC_RULE_PATTERN)));
  Result := P <> '';
  if not Result then
    Exit;

  R.Pattern := P;
  R.Enabled := SendMessage(FindChildByID(St.Wnd, IDC_RULE_ENABLED), BM_GETCHECK, 0, 0) = BST_CHECKED;
  R.UseLevel := SendMessage(FindChildByID(St.Wnd, IDC_RULE_USELEVEL), BM_GETCHECK, 0, 0) = BST_CHECKED;
  R.Color := St.RuleBgColor;
  if SendMessage(FindChildByID(St.Wnd, IDC_RULE_AUTOFG), BM_GETCHECK, 0, 0) = BST_CHECKED then
    R.FgColor := NO_COLOR_OVERRIDE
  else
    R.FgColor := St.RuleFgColor;
  Sel := SendMessage(FindChildByID(St.Wnd, IDC_RULE_LEVEL), CB_GETCURSEL, 0, 0);
  if (Sel < Ord(Low(TLogLevel))) or (Sel > Ord(High(TLogLevel))) then
    Sel := Ord(lCustom);
  R.Level := TLogLevel(Sel);
end;

procedure UpdateTabLayout(St: TOptionsState);
var
  R: TRect;
  I: Integer;
begin
  GetClientRect(St.Tab, R);
  SendMessage(St.Tab, TCM_ADJUSTRECT, 0, LPARAM(@R));
  MapWindowPoints(St.Tab, St.Wnd, PPOINT(@R), 2);
  for I := 0 to 4 do
    MoveWindow(St.Pages[I], R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, True);
end;

procedure ShowTabPage(St: TOptionsState; PageIdx: Integer);
var
  I: Integer;
begin
  for I := 0 to 4 do
    ShowWindow(St.Pages[I], IfThen(I = PageIdx, SW_SHOW, SW_HIDE));
end;

procedure ShowCtl(St: TOptionsState; AID: Integer; AVisible: Boolean);
var
  H: HWND;
begin
  H := FindChildByID(St.Wnd, AID);
  if H = 0 then
    Exit;
  ShowWindow(H, IfThen(AVisible, SW_SHOW, SW_HIDE));
  EnableWindow(H, AVisible);
end;

procedure UpdateCustomFormatVisible(St: TOptionsState);
var
  AutoDetect, ShowCustom, IsDelim: Boolean;
  H: HWND;
  I, Sel: Integer;
begin
  AutoDetect := SendMessage(FindChildByID(St.Wnd, IDC_FMT_AUTODET), BM_GETCHECK, 0, 0) = BST_CHECKED;
  H := FindChildByID(St.Wnd, IDC_FMT_FORCE);
  if H <> 0 then
    EnableWindow(H, not AutoDetect);

  Sel := -1;
  if H <> 0 then
    Sel := SendMessage(H, CB_GETCURSEL, 0, 0);
  ShowCustom := (not AutoDetect) and (Sel = Ord(lfCustom));

  ShowCtl(St, IDC_FMT_CUSTOMMODE_LBL, ShowCustom);
  ShowCtl(St, IDC_FMT_MODE, ShowCustom);
  ShowCtl(St, IDC_FMT_TSFMT_LBL, ShowCustom);
  ShowCtl(St, IDC_FMT_TSFMT, ShowCustom);

  H := FindChildByID(St.Wnd, IDC_FMT_MODE);
  if H <> 0 then
    Sel := SendMessage(H, CB_GETCURSEL, 0, 0)
  else
    Sel := 0;
  IsDelim := Sel = Ord(cfmDelimiter);

  ShowCtl(St, IDC_FMT_DELIM_LBL, ShowCustom and IsDelim);
  ShowCtl(St, IDC_FMT_DELIM, ShowCustom and IsDelim);
  ShowCtl(St, IDC_FMT_FIELDS_LBL, ShowCustom and IsDelim);
  for I := 0 to MAX_CUSTOM_FIELDS - 1 do
  begin
    ShowCtl(St, IDC_FMT_FIELDNO_BASE + I, ShowCustom and IsDelim);
    ShowCtl(St, IDC_FMT_FIELDROLE_BASE + I, ShowCustom and IsDelim);
  end;

  ShowCtl(St, IDC_FMT_POS_TS_LBL, ShowCustom and (not IsDelim));
  ShowCtl(St, IDC_FMT_TSSTART, ShowCustom and (not IsDelim));
  ShowCtl(St, IDC_FMT_TSLEN, ShowCustom and (not IsDelim));
  ShowCtl(St, IDC_FMT_POS_LVL_LBL, ShowCustom and (not IsDelim));
  ShowCtl(St, IDC_FMT_LVLSTART, ShowCustom and (not IsDelim));
  ShowCtl(St, IDC_FMT_LVLLEN, ShowCustom and (not IsDelim));
  ShowCtl(St, IDC_FMT_POS_SRC_LBL, ShowCustom and (not IsDelim));
  ShowCtl(St, IDC_FMT_SRCSTART, ShowCustom and (not IsDelim));
  ShowCtl(St, IDC_FMT_SRCLEN, ShowCustom and (not IsDelim));
end;

procedure FillFromSettings(St: TOptionsState);
var
  I, Sel: Integer;
  H: HWND;
begin
  SendMessage(FindChildByID(St.Wnd, IDC_VIEW_LINENUM), BM_SETCHECK, Ord(St.S.ShowLineNumbers), 0);
  H := FindChildByID(St.Wnd, IDC_VIEW_LINEWIDTH);
  if H <> 0 then
    SetWindowText(H, PChar(IntToStr(St.S.LineNumberWidth)));
  SendMessage(FindChildByID(St.Wnd, IDC_VIEW_WORDWRAP), BM_SETCHECK, Ord(St.S.WordWrap), 0);
  SendMessage(FindChildByID(St.Wnd, IDC_VIEW_HSCROLL), BM_SETCHECK, Ord(St.S.ShowHorzScrollbar), 0);
  SendMessage(FindChildByID(St.Wnd, IDC_VIEW_CLOSEESC), BM_SETCHECK, Ord(St.S.CloseOnEscInLister), 0);

  H := FindChildByID(St.Wnd, IDC_VIEW_FONTNAME);
  FillFontCombo(H, St.S.FontName);
  I := SendMessage(H, CB_FINDSTRINGEXACT, WPARAM(-1), LPARAM(PChar(St.S.FontName)));
  if I <> CB_ERR then
    SendMessage(H, CB_SETCURSEL, I, 0);
  H := FindChildByID(St.Wnd, IDC_VIEW_FONTSIZE);
  if H <> 0 then
    SetWindowText(H, PChar(IntToStr(St.S.FontSize)));

  H := FindChildByID(St.Wnd, IDC_VIEW_THEMEMODE);
  SendMessage(H, CB_RESETCONTENT, 0, 0);
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Auto (System)')));
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Always light')));
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Always dark')));
  SendMessage(H, CB_SETCURSEL, Integer(St.S.ThemeMode), 0);

  UpdateFontPreview(St);

  H := FindChildByID(St.Wnd, IDC_CLR_PALETTE);
  SendMessage(H, CB_RESETCONTENT, 0, 0);
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Light theme')));
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Dark theme')));
  SendMessage(H, CB_SETCURSEL, 0, 0);
  RefreshColorControls(St);

  RefreshRuleList(St);
  if St.S.ColorRuleCount > 0 then
  begin
    SendMessage(FindChildByID(St.Wnd, IDC_RULE_LIST), LB_SETCURSEL, 0, 0);
    LoadRuleControls(St, 0);
  end
  else
  begin
    SetEditText(FindChildByID(St.Wnd, IDC_RULE_PATTERN), '');
    SendMessage(FindChildByID(St.Wnd, IDC_RULE_ENABLED), BM_SETCHECK, BST_CHECKED, 0);
    SendMessage(FindChildByID(St.Wnd, IDC_RULE_USELEVEL), BM_SETCHECK, BST_UNCHECKED, 0);
    SendMessage(FindChildByID(St.Wnd, IDC_RULE_LEVEL), CB_SETCURSEL, Ord(lCustom), 0);
    SendMessage(FindChildByID(St.Wnd, IDC_RULE_AUTOFG), BM_SETCHECK, BST_CHECKED, 0);
    St.RuleBgColor := St.S.BgColor;
    St.RuleFgColor := NO_COLOR_OVERRIDE;
    UpdateRuleColorButtons(St);
  end;

  SendMessage(FindChildByID(St.Wnd, IDC_FMT_AUTODET), BM_SETCHECK, Ord(St.S.AutoDetectFormat), 0);
  H := FindChildByID(St.Wnd, IDC_FMT_FORCE);
  SendMessage(H, CB_RESETCONTENT, 0, 0);
  for I := Ord(Low(TLogFormat)) to Ord(High(TLogFormat)) do
    SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar(LogFormatNames[TLogFormat(I)])));
  SendMessage(H, CB_SETCURSEL, Integer(St.S.ForceFormat), 0);
  EnableWindow(H, not St.S.AutoDetectFormat);

  H := FindChildByID(St.Wnd, IDC_FMT_MODE);
  SendMessage(H, CB_RESETCONTENT, 0, 0);
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Delimiter')));
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Position')));
  SendMessage(H, CB_SETCURSEL, Integer(St.S.CustomFormat.Mode), 0);

  SetEditText(FindChildByID(St.Wnd, IDC_FMT_DELIM), St.S.CustomFormat.Delimiter);
  for I := 0 to MAX_CUSTOM_FIELDS - 1 do
  begin
    H := FindChildByID(St.Wnd, IDC_FMT_FIELDROLE_BASE + I);
    if H <> 0 then
    begin
      SendMessage(H, CB_RESETCONTENT, 0, 0);
      SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('--')));
      SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('TS')));
      SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Lvl')));
      SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Src')));
      SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Thr')));
      Sel := Integer(St.S.CustomFormat.FieldRoles[I]);
      if (Sel < Ord(Low(TCustomFieldRole))) or (Sel > Ord(High(TCustomFieldRole))) then
        Sel := Ord(cfrIgnore);
      SendMessage(H, CB_SETCURSEL, Sel, 0);
    end;
  end;
  SetEditText(FindChildByID(St.Wnd, IDC_FMT_TSFMT), St.S.CustomFormat.TimestampFmt);
  SetDlgItemInt(St.Wnd, IDC_FMT_TSSTART, St.S.CustomFormat.TSStart, False);
  SetDlgItemInt(St.Wnd, IDC_FMT_TSLEN, St.S.CustomFormat.TSLen, False);
  SetDlgItemInt(St.Wnd, IDC_FMT_LVLSTART, St.S.CustomFormat.LvlStart, False);
  SetDlgItemInt(St.Wnd, IDC_FMT_LVLLEN, St.S.CustomFormat.LvlLen, False);
  SetDlgItemInt(St.Wnd, IDC_FMT_SRCSTART, St.S.CustomFormat.SrcStart, False);
  SetDlgItemInt(St.Wnd, IDC_FMT_SRCLEN, St.S.CustomFormat.SrcLen, False);
  UpdateCustomFormatVisible(St);

  SendMessage(FindChildByID(St.Wnd, IDC_TAIL_ENABLE), BM_SETCHECK, Ord(St.S.TailEnabled), 0);
  SetDlgItemInt(St.Wnd, IDC_TAIL_MS, St.S.TailIntervalMs, False);
  SetWindowText(St.DetectedLbl, PChar('Detected format: ' + LogFormatNames[St.DetectedFmt]));
end;

procedure ApplyToSettings(St: TOptionsState);
var
  H: HWND;
  I, Sel: Integer;
  D: string;
begin
  St.S.ShowLineNumbers := SendMessage(FindChildByID(St.Wnd, IDC_VIEW_LINENUM), BM_GETCHECK, 0, 0) = BST_CHECKED;
  St.S.LineNumberWidth := EnsureRange(ReadEditInt(FindChildByID(St.Wnd, IDC_VIEW_LINEWIDTH), St.S.LineNumberWidth), 1, 9);
  St.S.WordWrap := SendMessage(FindChildByID(St.Wnd, IDC_VIEW_WORDWRAP), BM_GETCHECK, 0, 0) = BST_CHECKED;
  St.S.ShowHorzScrollbar := SendMessage(FindChildByID(St.Wnd, IDC_VIEW_HSCROLL), BM_GETCHECK, 0, 0) = BST_CHECKED;
  St.S.CloseOnEscInLister := SendMessage(FindChildByID(St.Wnd, IDC_VIEW_CLOSEESC), BM_GETCHECK, 0, 0) = BST_CHECKED;

  H := FindChildByID(St.Wnd, IDC_VIEW_FONTNAME);
  St.S.FontName := ComboSelectedText(H);
  if St.S.FontName = '' then
    St.S.FontName := 'Courier New';
  St.S.FontSize := EnsureRange(ReadEditInt(FindChildByID(St.Wnd, IDC_VIEW_FONTSIZE), St.S.FontSize), 6, 36);

  Sel := SendMessage(FindChildByID(St.Wnd, IDC_VIEW_THEMEMODE), CB_GETCURSEL, 0, 0);
  if (Sel >= Ord(Low(TThemeMode))) and (Sel <= Ord(High(TThemeMode))) then
    St.S.ThemeMode := TThemeMode(Sel)
  else
    St.S.ThemeMode := tmAuto;

  St.S.AutoDetectFormat := SendMessage(FindChildByID(St.Wnd, IDC_FMT_AUTODET), BM_GETCHECK, 0, 0) = BST_CHECKED;
  Sel := SendMessage(FindChildByID(St.Wnd, IDC_FMT_FORCE), CB_GETCURSEL, 0, 0);
  if (Sel >= 0) and (Sel <= Ord(High(TLogFormat))) then
    St.S.ForceFormat := TLogFormat(Sel);
  Sel := SendMessage(FindChildByID(St.Wnd, IDC_FMT_MODE), CB_GETCURSEL, 0, 0);
  if Sel in [0, 1] then
    St.S.CustomFormat.Mode := TCustomFormatMode(Sel);
  D := GetEditText(FindChildByID(St.Wnd, IDC_FMT_DELIM));
  if D <> '' then
    St.S.CustomFormat.Delimiter := D[1];
  St.S.CustomFormat.FieldCount := MAX_CUSTOM_FIELDS;
  for I := 0 to MAX_CUSTOM_FIELDS - 1 do
  begin
    Sel := SendMessage(FindChildByID(St.Wnd, IDC_FMT_FIELDROLE_BASE + I), CB_GETCURSEL, 0, 0);
    if (Sel >= Ord(Low(TCustomFieldRole))) and (Sel <= Ord(High(TCustomFieldRole))) then
      St.S.CustomFormat.FieldRoles[I] := TCustomFieldRole(Sel)
    else
      St.S.CustomFormat.FieldRoles[I] := cfrIgnore;
  end;
  St.S.CustomFormat.TimestampFmt := Trim(GetEditText(FindChildByID(St.Wnd, IDC_FMT_TSFMT)));
  St.S.CustomFormat.TSStart := ReadEditInt(FindChildByID(St.Wnd, IDC_FMT_TSSTART), St.S.CustomFormat.TSStart);
  St.S.CustomFormat.TSLen := ReadEditInt(FindChildByID(St.Wnd, IDC_FMT_TSLEN), St.S.CustomFormat.TSLen);
  St.S.CustomFormat.LvlStart := ReadEditInt(FindChildByID(St.Wnd, IDC_FMT_LVLSTART), St.S.CustomFormat.LvlStart);
  St.S.CustomFormat.LvlLen := ReadEditInt(FindChildByID(St.Wnd, IDC_FMT_LVLLEN), St.S.CustomFormat.LvlLen);
  St.S.CustomFormat.SrcStart := ReadEditInt(FindChildByID(St.Wnd, IDC_FMT_SRCSTART), St.S.CustomFormat.SrcStart);
  St.S.CustomFormat.SrcLen := ReadEditInt(FindChildByID(St.Wnd, IDC_FMT_SRCLEN), St.S.CustomFormat.SrcLen);

  St.S.TailEnabled := SendMessage(FindChildByID(St.Wnd, IDC_TAIL_ENABLE), BM_GETCHECK, 0, 0) = BST_CHECKED;
  St.S.TailIntervalMs := EnsureRange(ReadEditInt(FindChildByID(St.Wnd, IDC_TAIL_MS), St.S.TailIntervalMs), 200, 30000);

  AppSettings := St.S;
  ApplyThemeColors;
  St.S := AppSettings;
end;

procedure CreateViewPage(St: TOptionsState);
var
  P: HWND;
begin
  P := St.Pages[0];
  CreateWindow('BUTTON', 'Show line numbers', WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    10, 10, 220, 22, P, HMENU(IDC_VIEW_LINENUM), hInstance, nil);
  CreateWindow('STATIC', 'Digits:', WS_CHILD or WS_VISIBLE,
    10, 38, 110, 20, P, 0, hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '5', WS_CHILD or WS_VISIBLE or ES_NUMBER,
    128, 36, 50, 22, P, HMENU(IDC_VIEW_LINEWIDTH), hInstance, nil);
  CreateWindow('BUTTON', 'Word wrap', WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    10, 66, 220, 22, P, HMENU(IDC_VIEW_WORDWRAP), hInstance, nil);
  CreateWindow('BUTTON', 'Horizontal scrollbar', WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    10, 92, 220, 22, P, HMENU(IDC_VIEW_HSCROLL), hInstance, nil);
  CreateWindow('BUTTON', 'ESC closes lister window', WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    10, 116, 220, 22, P, HMENU(IDC_VIEW_CLOSEESC), hInstance, nil);
  CreateWindow('STATIC', 'Font:', WS_CHILD or WS_VISIBLE,
    10, 146, 80, 20, P, 0, hInstance, nil);
  CreateWindow('COMBOBOX', '', WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST or CBS_SORT or WS_VSCROLL,
    128, 144, 210, 300, P, HMENU(IDC_VIEW_FONTNAME), hInstance, nil);
  CreateWindow('BUTTON', 'v', WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    344, 143, 32, 24, P, HMENU(IDC_VIEW_PICKFONT), hInstance, nil);
  CreateWindow('STATIC', 'Font size:', WS_CHILD or WS_VISIBLE,
    10, 174, 80, 20, P, 0, hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '9', WS_CHILD or WS_VISIBLE or ES_NUMBER,
    128, 172, 50, 22, P, HMENU(IDC_VIEW_FONTSIZE), hInstance, nil);
  CreateWindow('STATIC', 'Appearance:', WS_CHILD or WS_VISIBLE,
    10, 204, 80, 20, P, 0, hInstance, nil);
  CreateWindow('COMBOBOX', '', WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST or WS_VSCROLL,
    128, 202, 210, 160, P, HMENU(IDC_VIEW_THEMEMODE), hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'STATIC', '',
    WS_CHILD or WS_VISIBLE or SS_LEFTNOWORDWRAP,
    10, 236, 366, 28, P, HMENU(IDC_VIEW_FONTPREVIEW), hInstance, nil);
end;

procedure CreateColorsPage(St: TOptionsState);
const
  Names: array[0..6] of string = ('Default', 'ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE', 'Custom');
var
  P: HWND;
  I, Y: Integer;
begin
  P := St.Pages[1];
  CreateWindow('STATIC', 'Edit colors for:', WS_CHILD or WS_VISIBLE,
    10, 12, 100, 20, P, 0, hInstance, nil);
  CreateWindow('COMBOBOX', '', WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST,
    110, 10, 150, 140, P, HMENU(IDC_CLR_PALETTE), hInstance, nil);

  for I := 0 to 6 do
  begin
    Y := 42 + I * 28;
    CreateWindow('STATIC', PChar(Names[I] + ':'), WS_CHILD or WS_VISIBLE,
      10, Y + 4, 60, 20, P, 0, hInstance, nil);
    CreateWindow('BUTTON', '', WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
      74, Y, 98, 24, P, HMENU(IDC_CLR_BG_BASE + I), hInstance, nil);
    CreateWindow('STATIC', '', WS_CHILD or WS_VISIBLE or SS_OWNERDRAW,
      176, Y + 2, 22, 20, P, HMENU(IDC_CLR_BG_SWATCH_BASE + I), hInstance, nil);
    CreateWindow('BUTTON', '', WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
      212, Y, 98, 24, P, HMENU(IDC_CLR_FG_BASE + I), hInstance, nil);
    CreateWindow('STATIC', '', WS_CHILD or WS_VISIBLE or SS_OWNERDRAW,
      314, Y + 2, 22, 20, P, HMENU(IDC_CLR_FG_SWATCH_BASE + I), hInstance, nil);
  end;
end;

procedure CreateRulesPage(St: TOptionsState);
var
  P, H: HWND;
begin
  P := St.Pages[2];
  CreateWindow('LISTBOX', '',
    WS_CHILD or WS_VISIBLE or WS_VSCROLL or WS_BORDER or LBS_NOTIFY,
    10, 10, 374, 110, P, HMENU(IDC_RULE_LIST), hInstance, nil);

  CreateWindow('STATIC', 'Pattern:', WS_CHILD or WS_VISIBLE,
    10, 128, 56, 20, P, 0, hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '',
    WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL,
    70, 126, 314, 22, P, HMENU(IDC_RULE_PATTERN), hInstance, nil);

  CreateWindow('BUTTON', 'Enabled', WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    10, 154, 80, 20, P, HMENU(IDC_RULE_ENABLED), hInstance, nil);
  CreateWindow('BUTTON', 'Use level', WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    100, 154, 90, 20, P, HMENU(IDC_RULE_USELEVEL), hInstance, nil);

  H := CreateWindow('COMBOBOX', '', WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST,
    196, 152, 112, 120, P, HMENU(IDC_RULE_LEVEL), hInstance, nil);
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('ERROR')));
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('WARN')));
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('INFO')));
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('DEBUG')));
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('TRACE')));
  SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Custom')));
  SendMessage(H, CB_SETCURSEL, Ord(lCustom), 0);

  CreateWindow('BUTTON', 'FG auto', WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    316, 154, 68, 20, P, HMENU(IDC_RULE_AUTOFG), hInstance, nil);

  CreateWindow('BUTTON', 'BG', WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    70, 180, 120, 24, P, HMENU(IDC_RULE_BG), hInstance, nil);
  CreateWindow('BUTTON', 'FG', WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    196, 180, 120, 24, P, HMENU(IDC_RULE_FG), hInstance, nil);

  CreateWindow('BUTTON', 'Add', WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    10, 212, 90, 24, P, HMENU(IDC_RULE_ADD), hInstance, nil);
  CreateWindow('BUTTON', 'Update', WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    106, 212, 90, 24, P, HMENU(IDC_RULE_UPDATE), hInstance, nil);
  CreateWindow('BUTTON', 'Delete', WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,
    202, 212, 90, 24, P, HMENU(IDC_RULE_DELETE), hInstance, nil);
end;

procedure CreateFormatPage(St: TOptionsState);
var
  P, H: HWND;
  I, X: Integer;
begin
  P := St.Pages[3];
  CreateWindow('BUTTON', 'Auto detect format', WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    10, 10, 220, 22, P, HMENU(IDC_FMT_AUTODET), hInstance, nil);
  CreateWindow('STATIC', 'Force format:', WS_CHILD or WS_VISIBLE,
    10, 38, 100, 20, P, 0, hInstance, nil);
  CreateWindow('COMBOBOX', '', WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST or WS_VSCROLL,
    120, 36, 260, 260, P, HMENU(IDC_FMT_FORCE), hInstance, nil);
  CreateWindow('STATIC', 'Custom mode:', WS_CHILD or WS_VISIBLE,
    10, 70, 100, 20, P, HMENU(IDC_FMT_CUSTOMMODE_LBL), hInstance, nil);
  CreateWindow('COMBOBOX', '', WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST,
    120, 68, 130, 120, P, HMENU(IDC_FMT_MODE), hInstance, nil);
  CreateWindow('STATIC', 'Delimiter:', WS_CHILD or WS_VISIBLE,
    260, 70, 60, 20, P, HMENU(IDC_FMT_DELIM_LBL), hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '|', WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL,
    324, 68, 56, 22, P, HMENU(IDC_FMT_DELIM), hInstance, nil);
  CreateWindow('STATIC', 'Field roles:', WS_CHILD or WS_VISIBLE,
    10, 98, 100, 20, P, HMENU(IDC_FMT_FIELDS_LBL), hInstance, nil);
  for I := 0 to MAX_CUSTOM_FIELDS - 1 do
  begin
    X := 10 + I * 47;
    CreateWindow('STATIC', PChar(IntToStr(I + 1) + ':'), WS_CHILD or WS_VISIBLE,
      X, 116, 20, 18, P, HMENU(IDC_FMT_FIELDNO_BASE + I), hInstance, nil);
    H := CreateWindow('COMBOBOX', '', WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST,
      X + 16, 112, 30, 120, P, HMENU(IDC_FMT_FIELDROLE_BASE + I), hInstance, nil);
    SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('--')));
    SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('TS')));
    SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Lvl')));
    SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Src')));
    SendMessage(H, CB_ADDSTRING, 0, LPARAM(PChar('Thr')));
    SendMessage(H, CB_SETCURSEL, 0, 0);
  end;
  CreateWindow('STATIC', 'Timestamp format:', WS_CHILD or WS_VISIBLE,
    10, 142, 110, 20, P, HMENU(IDC_FMT_TSFMT_LBL), hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', 'YYYY-MM-DD hh:nn:ss', WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL,
    120, 140, 260, 22, P, HMENU(IDC_FMT_TSFMT), hInstance, nil);

  CreateWindow('STATIC', 'TS start/len:', WS_CHILD or WS_VISIBLE, 10, 172, 100, 20, P, HMENU(IDC_FMT_POS_TS_LBL), hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '0', WS_CHILD or WS_VISIBLE or ES_NUMBER,
    120, 170, 50, 22, P, HMENU(IDC_FMT_TSSTART), hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '0', WS_CHILD or WS_VISIBLE or ES_NUMBER,
    176, 170, 50, 22, P, HMENU(IDC_FMT_TSLEN), hInstance, nil);

  CreateWindow('STATIC', 'LVL start/len:', WS_CHILD or WS_VISIBLE, 10, 200, 100, 20, P, HMENU(IDC_FMT_POS_LVL_LBL), hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '0', WS_CHILD or WS_VISIBLE or ES_NUMBER,
    120, 198, 50, 22, P, HMENU(IDC_FMT_LVLSTART), hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '0', WS_CHILD or WS_VISIBLE or ES_NUMBER,
    176, 198, 50, 22, P, HMENU(IDC_FMT_LVLLEN), hInstance, nil);

  CreateWindow('STATIC', 'SRC start/len:', WS_CHILD or WS_VISIBLE, 10, 228, 100, 20, P, HMENU(IDC_FMT_POS_SRC_LBL), hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '0', WS_CHILD or WS_VISIBLE or ES_NUMBER,
    120, 226, 50, 22, P, HMENU(IDC_FMT_SRCSTART), hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '0', WS_CHILD or WS_VISIBLE or ES_NUMBER,
    176, 226, 50, 22, P, HMENU(IDC_FMT_SRCLEN), hInstance, nil);
end;

procedure CreateTailPage(St: TOptionsState);
var
  P: HWND;
begin
  P := St.Pages[4];
  CreateWindow('BUTTON', 'Enable tail when opening file', WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX,
    10, 12, 260, 22, P, HMENU(IDC_TAIL_ENABLE), hInstance, nil);
  CreateWindow('STATIC', 'Tail interval (ms):', WS_CHILD or WS_VISIBLE,
    10, 42, 130, 20, P, 0, hInstance, nil);
  CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '1000', WS_CHILD or WS_VISIBLE or ES_NUMBER,
    146, 40, 90, 22, P, HMENU(IDC_TAIL_MS), hInstance, nil);
end;

procedure CreateOptionControls(St: TOptionsState);
var
  I: Integer;
  TC: TTCItem;
begin
  St.Tab := CreateWindowEx(0, WC_TABCONTROL, '', WS_CHILD or WS_VISIBLE or WS_CLIPSIBLINGS,
    10, 10, 408, 300, St.Wnd, HMENU(IDC_TAB), hInstance, nil);

  FillChar(TC, SizeOf(TC), 0);
  TC.mask := TCIF_TEXT;
  TC.pszText := 'View';
  SendMessage(St.Tab, TCM_INSERTITEM, 0, LPARAM(@TC));
  TC.pszText := 'Colors';
  SendMessage(St.Tab, TCM_INSERTITEM, 1, LPARAM(@TC));
  TC.pszText := 'Color Rules';
  SendMessage(St.Tab, TCM_INSERTITEM, 2, LPARAM(@TC));
  TC.pszText := 'Format';
  SendMessage(St.Tab, TCM_INSERTITEM, 3, LPARAM(@TC));
  TC.pszText := 'Tail';
  SendMessage(St.Tab, TCM_INSERTITEM, 4, LPARAM(@TC));

  for I := 0 to 4 do
    St.Pages[I] := CreateWindowEx(WS_EX_CONTROLPARENT, OPT_PAGE_CLASS, '',
      WS_CHILD or WS_VISIBLE, 0, 0, 100, 100, St.Wnd, 0, hInstance, nil);

  CreateViewPage(St);
  CreateColorsPage(St);
  CreateRulesPage(St);
  CreateFormatPage(St);
  CreateTailPage(St);
  UpdateTabLayout(St);
  ShowTabPage(St, 0);

  St.DetectedLbl := CreateWindow('STATIC', '', WS_CHILD or WS_VISIBLE,
    12, 316, 300, 20, St.Wnd, HMENU(IDC_DETECTED), hInstance, nil);
  CreateWindow('BUTTON', 'OK', WS_CHILD or WS_VISIBLE or BS_DEFPUSHBUTTON,
    258, 314, 75, 26, St.Wnd, HMENU(IDOK), hInstance, nil);
  CreateWindow('BUTTON', 'Cancel', WS_CHILD or WS_VISIBLE,
    342, 314, 75, 26, St.Wnd, HMENU(IDCANCEL), hInstance, nil);
end;

function PageWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
begin
  case Msg of
    WM_COMMAND, WM_NOTIFY, WM_DRAWITEM:
      begin
        SendMessage(GetParent(Wnd), Msg, WParam, LParam);
        Result := 0;
        Exit;
      end;
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

procedure DrawColorSwatch(St: TOptionsState; DI: PDrawItemStruct);
var
  Idx: Integer;
  C: COLORREF;
  R: TRect;
  B: HBRUSH;
  Border: HBRUSH;
begin
  Idx := -1;
  C := 0;
  if (DI^.CtlID >= IDC_CLR_BG_SWATCH_BASE) and (DI^.CtlID <= IDC_CLR_BG_SWATCH_BASE + 6) then
  begin
    Idx := DI^.CtlID - IDC_CLR_BG_SWATCH_BASE;
    C := St.SwatchBg[Idx];
  end
  else if (DI^.CtlID >= IDC_CLR_FG_SWATCH_BASE) and (DI^.CtlID <= IDC_CLR_FG_SWATCH_BASE + 6) then
  begin
    Idx := DI^.CtlID - IDC_CLR_FG_SWATCH_BASE;
    C := St.SwatchFg[Idx];
  end;
  if Idx < 0 then
    Exit;

  R := DI^.rcItem;
  B := CreateSolidBrush(C);
  FillRect(DI^.hDC, R, B);
  DeleteObject(B);
  Border := GetStockObject(BLACK_BRUSH);
  FrameRect(DI^.hDC, R, Border);
end;

function OptionsWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  St: TOptionsState;
  ID, Idx, Sel: Integer;
  NM: PNMHDR;
  Bg, Fg, NC: COLORREF;
  P: PThemeColors;
  DI: PDrawItemStruct;
  Rule: TColorStringRule;
begin
  case Msg of
    WM_CREATE:
      begin
        SetWindowLongPtr(Wnd, GWLP_USERDATA, PtrInt(PCREATESTRUCT(LParam)^.lpCreateParams));
        Result := 0;
        Exit;
      end;

    WM_NOTIFY:
      begin
        St := GetState(Wnd);
        if St <> nil then
        begin
          NM := PNMHDR(LParam);
          if (Integer(NM^.idFrom) = IDC_TAB) and (NM^.code = UINT(TCN_SELCHANGE)) then
          begin
            Idx := Integer(SendMessage(St.Tab, TCM_GETCURSEL, 0, 0));
            if Idx < 0 then Idx := 0;
            ShowTabPage(St, Idx);
          end;
        end;
        Result := 0;
        Exit;
      end;

    WM_DRAWITEM:
      begin
        St := GetState(Wnd);
        DI := PDrawItemStruct(LParam);
        if (St <> nil) and (DI <> nil) then
          DrawColorSwatch(St, DI);
        Result := 1;
        Exit;
      end;

    WM_COMMAND:
      begin
        St := GetState(Wnd);
        if St = nil then Exit(0);
        ID := LOWORD(WParam);

        if (ID >= IDC_CLR_BG_BASE) and (ID <= IDC_CLR_BG_BASE + 6) then
        begin
          Idx := ID - IDC_CLR_BG_BASE;
          P := CurrentPalettePtr(St);
          GetPaletteColorByIndex(P^, Idx, Bg, Fg);
          if PickColor(Wnd, Bg, NC) then
          begin
            SetPaletteColorByIndex(P^, Idx, False, NC);
            RefreshColorControls(St);
          end;
          Exit(0);
        end;

        if (ID >= IDC_CLR_FG_BASE) and (ID <= IDC_CLR_FG_BASE + 6) then
        begin
          Idx := ID - IDC_CLR_FG_BASE;
          P := CurrentPalettePtr(St);
          GetPaletteColorByIndex(P^, Idx, Bg, Fg);
          if PickColor(Wnd, Fg, NC) then
          begin
            SetPaletteColorByIndex(P^, Idx, True, NC);
            RefreshColorControls(St);
          end;
          Exit(0);
        end;

        if ID = IDC_RULE_LIST then
        begin
          if HIWORD(WParam) = LBN_SELCHANGE then
          begin
            Sel := SendMessage(FindChildByID(Wnd, IDC_RULE_LIST), LB_GETCURSEL, 0, 0);
            LoadRuleControls(St, Sel);
          end;
          Exit(0);
        end;

        case ID of
          IDC_VIEW_PICKFONT:
            SendMessage(FindChildByID(Wnd, IDC_VIEW_FONTNAME), CB_SHOWDROPDOWN, 1, 0);
          IDC_VIEW_FONTNAME:
            begin
              if (HIWORD(WParam) = CBN_SELCHANGE) or (HIWORD(WParam) = CBN_EDITCHANGE) then
                UpdateFontPreview(St);
            end;
          IDC_VIEW_FONTSIZE:
            begin
              if HIWORD(WParam) = EN_CHANGE then
                UpdateFontPreview(St);
            end;
          IDC_CLR_PALETTE:
            begin
              if HIWORD(WParam) = CBN_SELCHANGE then
                RefreshColorControls(St);
            end;
          IDC_RULE_USELEVEL, IDC_RULE_AUTOFG:
            UpdateRuleColorButtons(St);
          IDC_RULE_BG:
            begin
              if PickColor(Wnd, St.RuleBgColor, NC) then
              begin
                St.RuleBgColor := NC;
                UpdateRuleColorButtons(St);
              end;
            end;
          IDC_RULE_FG:
            begin
              if (St.RuleFgColor = NO_COLOR_OVERRIDE) then
                Bg := St.S.FgColor
              else
                Bg := St.RuleFgColor;
              if PickColor(Wnd, Bg, NC) then
              begin
                St.RuleFgColor := NC;
                SendMessage(FindChildByID(Wnd, IDC_RULE_AUTOFG), BM_SETCHECK, BST_UNCHECKED, 0);
                UpdateRuleColorButtons(St);
              end;
            end;
          IDC_RULE_ADD:
            begin
              if BuildRuleFromControls(St, Rule) and (St.S.ColorRuleCount < MAX_COLOR_STRINGS) then
              begin
                St.S.ColorRules[St.S.ColorRuleCount] := Rule;
                Inc(St.S.ColorRuleCount);
                RefreshRuleList(St);
                Sel := St.S.ColorRuleCount - 1;
                SendMessage(FindChildByID(Wnd, IDC_RULE_LIST), LB_SETCURSEL, Sel, 0);
                LoadRuleControls(St, Sel);
              end;
            end;
          IDC_RULE_UPDATE:
            begin
              Sel := SendMessage(FindChildByID(Wnd, IDC_RULE_LIST), LB_GETCURSEL, 0, 0);
              if (Sel >= 0) and (Sel < St.S.ColorRuleCount) and BuildRuleFromControls(St, Rule) then
              begin
                St.S.ColorRules[Sel] := Rule;
                RefreshRuleList(St);
                SendMessage(FindChildByID(Wnd, IDC_RULE_LIST), LB_SETCURSEL, Sel, 0);
                LoadRuleControls(St, Sel);
              end;
            end;
          IDC_RULE_DELETE:
            begin
              Sel := SendMessage(FindChildByID(Wnd, IDC_RULE_LIST), LB_GETCURSEL, 0, 0);
              if (Sel >= 0) and (Sel < St.S.ColorRuleCount) then
              begin
                for Idx := Sel to St.S.ColorRuleCount - 2 do
                  St.S.ColorRules[Idx] := St.S.ColorRules[Idx + 1];
                Dec(St.S.ColorRuleCount);
                if St.S.ColorRuleCount < 0 then
                  St.S.ColorRuleCount := 0;
                RefreshRuleList(St);
                if St.S.ColorRuleCount > 0 then
                begin
                  if Sel >= St.S.ColorRuleCount then
                    Sel := St.S.ColorRuleCount - 1;
                  SendMessage(FindChildByID(Wnd, IDC_RULE_LIST), LB_SETCURSEL, Sel, 0);
                  LoadRuleControls(St, Sel);
                end
                else
                begin
                  SetEditText(FindChildByID(St.Wnd, IDC_RULE_PATTERN), '');
                  UpdateRuleColorButtons(St);
                end;
              end;
            end;
          IDC_FMT_AUTODET:
            UpdateCustomFormatVisible(St);
          IDC_FMT_FORCE, IDC_FMT_MODE:
            begin
              if HIWORD(WParam) = CBN_SELCHANGE then
                UpdateCustomFormatVisible(St);
            end;
          IDOK:
            begin
              ApplyToSettings(St);
              SaveSettings;
              St.Accepted := True;
              St.Done := True;
              DestroyWindow(Wnd);
            end;
          IDCANCEL:
            begin
              St.Done := True;
              DestroyWindow(Wnd);
            end;
        end;
        Result := 0;
        Exit;
      end;

    WM_CLOSE:
      begin
        St := GetState(Wnd);
        if St <> nil then
          St.Done := True;
        DestroyWindow(Wnd);
        Result := 0;
        Exit;
      end;
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

procedure EnsureOptionsClass;
var
  WC: WNDCLASS;
begin
  if Windows.GetClassInfo(hInstance, OPT_CLASS_NAME, WC) then Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.style := CS_DBLCLKS;
  WC.lpfnWndProc := @OptionsWndProc;
  WC.hInstance := hInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := COLOR_BTNFACE + 1;
  WC.lpszClassName := OPT_CLASS_NAME;
  Windows.RegisterClass(WC);
end;

procedure EnsurePageClass;
var
  WC: WNDCLASS;
begin
  if Windows.GetClassInfo(hInstance, OPT_PAGE_CLASS, WC) then Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.style := CS_DBLCLKS;
  WC.lpfnWndProc := @PageWndProc;
  WC.hInstance := hInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := COLOR_BTNFACE + 1;
  WC.lpszClassName := OPT_PAGE_CLASS;
  Windows.RegisterClass(WC);
end;

function ShowPluginOptions(AOwner: HWND; ADetected: TLogFormat): Boolean;
var
  St: TOptionsState;
  Wnd: HWND;
  Msg: TMsg;
  RW, RO: TRect;
  X, Y: Integer;
begin
  InitCommonCtrls;
  EnsureOptionsClass;
  EnsurePageClass;
  LoadSettings;

  St := TOptionsState.Create;
  try
    St.Owner := AOwner;
    St.Done := False;
    St.Accepted := False;
    St.DetectedFmt := ADetected;

    Wnd := CreateWindowEx(WS_EX_DLGMODALFRAME, OPT_CLASS_NAME, 'LogViewer Options',
      WS_POPUP or WS_CAPTION or WS_SYSMENU,
      CW_USEDEFAULT, CW_USEDEFAULT, 436, 384,
      AOwner, 0, hInstance, St);
    St.Wnd := Wnd;

    CreateOptionControls(St);
    ApplyNormalDialogFont(St);
    FillFromSettings(St);

    if AOwner <> 0 then
      EnableWindow(AOwner, False);

    GetWindowRect(Wnd, RW);
    if AOwner <> 0 then
      GetWindowRect(AOwner, RO)
    else
      SystemParametersInfo(SPI_GETWORKAREA, 0, @RO, 0);
    X := RO.Left + ((RO.Right - RO.Left) - (RW.Right - RW.Left)) div 2;
    Y := RO.Top + ((RO.Bottom - RO.Top) - (RW.Bottom - RW.Top)) div 2;
    SetWindowPos(Wnd, 0, X, Y, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);

    ShowWindow(Wnd, SW_SHOW);
    UpdateWindow(Wnd);

    while (not St.Done) and GetMessage(Msg, 0, 0, 0) do
    begin
      if (Wnd = 0) or (not IsDialogMessage(Wnd, Msg)) then
      begin
        TranslateMessage(Msg);
        DispatchMessage(Msg);
      end;
    end;

    if AOwner <> 0 then
    begin
      EnableWindow(AOwner, True);
      SetActiveWindow(AOwner);
    end;
    Result := St.Accepted;
  finally
    St.Free;
  end;
end;

end.
