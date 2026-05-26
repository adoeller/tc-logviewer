unit uSettings;

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, IniFiles, uLogTypes, uWLXTypes;

const
  MAX_COLOR_STRINGS = 20;
  NO_COLOR_OVERRIDE: COLORREF = COLORREF($FFFFFFFF);

type
  TThemeMode = (tmAuto, tmLight, tmDark);

  TColorStringRule = record
    Pattern: string;
    Color: COLORREF;
    FgColor: COLORREF;
    Enabled: Boolean;
    UseLevel: Boolean;
    Level: TLogLevel;
  end;

  TThemeColors = record
    BgColor: COLORREF;
    FgColor: COLORREF;
    ErrBg: COLORREF;
    ErrFg: COLORREF;
    WarnBg: COLORREF;
    WarnFg: COLORREF;
    InfoBg: COLORREF;
    InfoFg: COLORREF;
    DebugBg: COLORREF;
    DebugFg: COLORREF;
    TraceBg: COLORREF;
    TraceFg: COLORREF;
    CustomBg: COLORREF;
    CustomFg: COLORREF;
  end;

  TAppSettings = record
    ShowLineNumbers: Boolean;
    LineNumberWidth: Integer;
    WordWrap: Boolean;
    ShowHorzScrollbar: Boolean;
    FontName: string;
    FontSize: Integer;

    ThemeMode: TThemeMode;
    LightColors: TThemeColors;
    DarkColors: TThemeColors;

    BgColor: COLORREF;
    FgColor: COLORREF;
    ErrBg: COLORREF;
    ErrFg: COLORREF;
    WarnBg: COLORREF;
    WarnFg: COLORREF;
    InfoBg: COLORREF;
    InfoFg: COLORREF;
    DebugBg: COLORREF;
    DebugFg: COLORREF;
    TraceBg: COLORREF;
    TraceFg: COLORREF;
    CustomBg: COLORREF;
    CustomFg: COLORREF;

    ColorRules: array[0..MAX_COLOR_STRINGS - 1] of TColorStringRule;
    ColorRuleCount: Integer;

    AutoDetectFormat: Boolean;
    ForceFormat: TLogFormat;
    CustomFormat: TCustomFormatConfig;

    TailEnabled: Boolean;
    TailIntervalMs: Integer;
    CloseOnEscInLister: Boolean;

    WinLeft: Integer;
    WinTop: Integer;
    WinWidth: Integer;
    WinHeight: Integer;
    WinMaximized: Boolean;
    LastDir: string;
  end;

var
  AppSettings: TAppSettings;

procedure DefaultSettings;
procedure LoadSettings;
procedure SaveSettings;
function SystemIsDarkMode: Boolean;
function IsDarkModeActive: Boolean;
procedure ApplyThemeColors;

implementation

uses
  Math
  {$IFDEF WINDOWS}
  , Registry
  {$ENDIF}
  ;

function IniPath: string;
begin
  if GPluginDir <> '' then
    Result := IncludeTrailingPathDelimiter(GPluginDir) + 'LogViewer.ini'
  else
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'LogViewer.ini';
end;

function SystemIsDarkMode: Boolean;
{$IFDEF WINDOWS}
var
  Reg: TRegistry;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') then
    begin
      try
        if Reg.ValueExists('AppsUseLightTheme') then
          Result := Reg.ReadInteger('AppsUseLightTheme') = 0;
      except
        Result := False;
      end;
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function IsDarkModeActive: Boolean;
begin
  case AppSettings.ThemeMode of
    tmDark: Result := True;
    tmLight: Result := False;
  else
    Result := SystemIsDarkMode;
  end;
end;

procedure ApplyThemeColors;
var
  C: TThemeColors;
begin
  if IsDarkModeActive then
    C := AppSettings.DarkColors
  else
    C := AppSettings.LightColors;

  AppSettings.BgColor := C.BgColor;
  AppSettings.FgColor := C.FgColor;
  AppSettings.ErrBg := C.ErrBg;
  AppSettings.ErrFg := C.ErrFg;
  AppSettings.WarnBg := C.WarnBg;
  AppSettings.WarnFg := C.WarnFg;
  AppSettings.InfoBg := C.InfoBg;
  AppSettings.InfoFg := C.InfoFg;
  AppSettings.DebugBg := C.DebugBg;
  AppSettings.DebugFg := C.DebugFg;
  AppSettings.TraceBg := C.TraceBg;
  AppSettings.TraceFg := C.TraceFg;
  AppSettings.CustomBg := C.CustomBg;
  AppSettings.CustomFg := C.CustomFg;
end;

procedure DefaultLightColors(out C: TThemeColors);
begin
  C.BgColor := GetSysColor(COLOR_WINDOW);
  C.FgColor := GetSysColor(COLOR_WINDOWTEXT);
  C.ErrBg := $00AAAAFF;
  C.WarnBg := $0000AAFF;
  C.InfoBg := $0000FFFF;
  C.DebugBg := $00F0F0F0;
  C.TraceBg := $00FFE8D0;
  C.CustomBg := $00E1FFFF;
  C.ErrFg := $00000000;
  C.WarnFg := $00000000;
  C.InfoFg := $00000000;
  C.DebugFg := $00000000;
  C.TraceFg := $00000000;
  C.CustomFg := $00000000;
end;

procedure DefaultDarkColors(out C: TThemeColors);
begin
  C.BgColor := $00282828;
  C.FgColor := $00D4D4D4;
  C.ErrBg := $00102040;
  C.WarnBg := $00103848;
  C.InfoBg := $00184040;
  C.DebugBg := $00383838;
  C.TraceBg := $00403028;
  C.CustomBg := $00303030;
  C.ErrFg := $00AAAAFF;
  C.WarnFg := $0080CCFF;
  C.InfoFg := $0080FFFF;
  C.DebugFg := $00C0C0C0;
  C.TraceFg := $00D0C0A0;
  C.CustomFg := $00C0C0C0;
end;

procedure DefaultColorRules;
var
  I: Integer;
begin
  AppSettings.ColorRuleCount := 0;
  for I := 0 to MAX_COLOR_STRINGS - 1 do
  begin
    AppSettings.ColorRules[I].Pattern := '';
    AppSettings.ColorRules[I].Color := AppSettings.BgColor;
    AppSettings.ColorRules[I].FgColor := NO_COLOR_OVERRIDE;
    AppSettings.ColorRules[I].Enabled := True;
    AppSettings.ColorRules[I].UseLevel := False;
    AppSettings.ColorRules[I].Level := lCustom;
  end;
end;

procedure DefaultSettings;
begin
  AppSettings.ShowLineNumbers := True;
  AppSettings.LineNumberWidth := 5;
  AppSettings.WordWrap := False;
  AppSettings.ShowHorzScrollbar := False;
  AppSettings.FontName := 'Courier New';
  AppSettings.FontSize := 9;

  AppSettings.ThemeMode := tmAuto;
  DefaultLightColors(AppSettings.LightColors);
  DefaultDarkColors(AppSettings.DarkColors);
  ApplyThemeColors;
  DefaultColorRules;

  AppSettings.AutoDetectFormat := True;
  AppSettings.ForceFormat := lfPlain;

  AppSettings.CustomFormat.Mode := cfmDelimiter;
  AppSettings.CustomFormat.Delimiter := '|';
  AppSettings.CustomFormat.FieldCount := 4;
  AppSettings.CustomFormat.FieldRoles[0] := cfrTimestamp;
  AppSettings.CustomFormat.FieldRoles[1] := cfrLevel;
  AppSettings.CustomFormat.FieldRoles[2] := cfrSource;
  AppSettings.CustomFormat.FieldRoles[3] := cfrIgnore;
  AppSettings.CustomFormat.FieldRoles[4] := cfrIgnore;
  AppSettings.CustomFormat.FieldRoles[5] := cfrIgnore;
  AppSettings.CustomFormat.FieldRoles[6] := cfrIgnore;
  AppSettings.CustomFormat.FieldRoles[7] := cfrIgnore;
  AppSettings.CustomFormat.TSStart := 0;
  AppSettings.CustomFormat.TSLen := 0;
  AppSettings.CustomFormat.LvlStart := 0;
  AppSettings.CustomFormat.LvlLen := 0;
  AppSettings.CustomFormat.SrcStart := 0;
  AppSettings.CustomFormat.SrcLen := 0;
  AppSettings.CustomFormat.TimestampFmt := 'YYYY-MM-DD hh:nn:ss';

  AppSettings.TailEnabled := False;
  AppSettings.TailIntervalMs := 1000;
  AppSettings.CloseOnEscInLister := True;

  AppSettings.WinLeft := 100;
  AppSettings.WinTop := 80;
  AppSettings.WinWidth := 960;
  AppSettings.WinHeight := 650;
  AppSettings.WinMaximized := False;
  AppSettings.LastDir := '';
end;

function ReadColor(Ini: TIniFile; const Section, Key: string; Default: COLORREF): COLORREF;
begin
  Result := COLORREF(Ini.ReadInteger(Section, Key, Integer(Default)));
end;

procedure LoadThemeColors(Ini: TIniFile; const Section: string; var C: TThemeColors);
begin
  C.BgColor := ReadColor(Ini, Section, 'BgColor',
    ReadColor(Ini, Section, 'BgDefault', C.BgColor));
  C.FgColor := ReadColor(Ini, Section, 'FgColor',
    ReadColor(Ini, Section, 'FgDefault', C.FgColor));

  C.ErrBg := ReadColor(Ini, Section, 'ErrBg',
    ReadColor(Ini, Section, 'Error', C.ErrBg));
  C.WarnBg := ReadColor(Ini, Section, 'WarnBg',
    ReadColor(Ini, Section, 'Warn', C.WarnBg));
  C.InfoBg := ReadColor(Ini, Section, 'InfoBg',
    ReadColor(Ini, Section, 'Info', C.InfoBg));
  C.DebugBg := ReadColor(Ini, Section, 'DebugBg',
    ReadColor(Ini, Section, 'Debug', C.DebugBg));
  C.TraceBg := ReadColor(Ini, Section, 'TraceBg',
    ReadColor(Ini, Section, 'Trace', C.TraceBg));
  C.CustomBg := ReadColor(Ini, Section, 'CustomBg',
    ReadColor(Ini, Section, 'Custom', C.CustomBg));

  C.ErrFg := ReadColor(Ini, Section, 'ErrFg',
    ReadColor(Ini, Section, 'FgError', C.ErrFg));
  C.WarnFg := ReadColor(Ini, Section, 'WarnFg',
    ReadColor(Ini, Section, 'FgWarn', C.WarnFg));
  C.InfoFg := ReadColor(Ini, Section, 'InfoFg',
    ReadColor(Ini, Section, 'FgInfo', C.InfoFg));
  C.DebugFg := ReadColor(Ini, Section, 'DebugFg',
    ReadColor(Ini, Section, 'FgDebug', C.DebugFg));
  C.TraceFg := ReadColor(Ini, Section, 'TraceFg',
    ReadColor(Ini, Section, 'FgTrace', C.TraceFg));
  C.CustomFg := ReadColor(Ini, Section, 'CustomFg',
    ReadColor(Ini, Section, 'FgCustom', C.CustomFg));
end;

procedure SaveThemeColors(Ini: TIniFile; const Section: string; const C: TThemeColors);
begin
  Ini.WriteInteger(Section, 'BgColor', Integer(C.BgColor));
  Ini.WriteInteger(Section, 'FgColor', Integer(C.FgColor));
  Ini.WriteInteger(Section, 'ErrBg', Integer(C.ErrBg));
  Ini.WriteInteger(Section, 'WarnBg', Integer(C.WarnBg));
  Ini.WriteInteger(Section, 'InfoBg', Integer(C.InfoBg));
  Ini.WriteInteger(Section, 'DebugBg', Integer(C.DebugBg));
  Ini.WriteInteger(Section, 'TraceBg', Integer(C.TraceBg));
  Ini.WriteInteger(Section, 'CustomBg', Integer(C.CustomBg));
  Ini.WriteInteger(Section, 'ErrFg', Integer(C.ErrFg));
  Ini.WriteInteger(Section, 'WarnFg', Integer(C.WarnFg));
  Ini.WriteInteger(Section, 'InfoFg', Integer(C.InfoFg));
  Ini.WriteInteger(Section, 'DebugFg', Integer(C.DebugFg));
  Ini.WriteInteger(Section, 'TraceFg', Integer(C.TraceFg));
  Ini.WriteInteger(Section, 'CustomFg', Integer(C.CustomFg));

  Ini.WriteInteger(Section, 'Error', Integer(C.ErrBg));
  Ini.WriteInteger(Section, 'Warn', Integer(C.WarnBg));
  Ini.WriteInteger(Section, 'Info', Integer(C.InfoBg));
  Ini.WriteInteger(Section, 'Debug', Integer(C.DebugBg));
  Ini.WriteInteger(Section, 'Trace', Integer(C.TraceBg));
  Ini.WriteInteger(Section, 'Custom', Integer(C.CustomBg));
  Ini.WriteInteger(Section, 'FgError', Integer(C.ErrFg));
  Ini.WriteInteger(Section, 'FgWarn', Integer(C.WarnFg));
  Ini.WriteInteger(Section, 'FgInfo', Integer(C.InfoFg));
  Ini.WriteInteger(Section, 'FgDebug', Integer(C.DebugFg));
  Ini.WriteInteger(Section, 'FgTrace', Integer(C.TraceFg));
  Ini.WriteInteger(Section, 'FgCustom', Integer(C.CustomFg));
  Ini.WriteInteger(Section, 'BgDefault', Integer(C.BgColor));
  Ini.WriteInteger(Section, 'FgDefault', Integer(C.FgColor));
end;

procedure LoadSettings;
var
  Ini: TIniFile;
  I, N, V: Integer;
  Sec: string;
begin
  DefaultSettings;
  if not FileExists(IniPath) then
    Exit;

  Ini := TIniFile.Create(IniPath);
  try
    AppSettings.ShowLineNumbers := Ini.ReadBool('View', 'ShowLineNumbers', AppSettings.ShowLineNumbers);
    AppSettings.LineNumberWidth := EnsureRange(Ini.ReadInteger('View', 'LineNumWidth', AppSettings.LineNumberWidth), 1, 9);
    AppSettings.WordWrap := Ini.ReadBool('View', 'WordWrap', AppSettings.WordWrap);
    AppSettings.ShowHorzScrollbar := Ini.ReadBool('View', 'HorzScrollbar', AppSettings.ShowHorzScrollbar);
    AppSettings.FontName := Trim(Ini.ReadString('View', 'FontName', AppSettings.FontName));
    if AppSettings.FontName = '' then
      AppSettings.FontName := 'Courier New';
    AppSettings.FontSize := EnsureRange(Ini.ReadInteger('View', 'FontSize', AppSettings.FontSize), 6, 36);

    V := Ini.ReadInteger('Theme', 'Mode', Integer(AppSettings.ThemeMode));
    if (V < Ord(Low(TThemeMode))) or (V > Ord(High(TThemeMode))) then
      V := Ord(tmAuto);
    AppSettings.ThemeMode := TThemeMode(V);

    if Ini.SectionExists('ColorsLight') then
      LoadThemeColors(Ini, 'ColorsLight', AppSettings.LightColors)
    else if Ini.SectionExists('Colors') then
      LoadThemeColors(Ini, 'Colors', AppSettings.LightColors);

    if Ini.SectionExists('ColorsDark') then
      LoadThemeColors(Ini, 'ColorsDark', AppSettings.DarkColors);

    N := EnsureRange(Ini.ReadInteger('ColorRules', 'Count', 0), 0, MAX_COLOR_STRINGS);
    AppSettings.ColorRuleCount := 0;
    for I := 0 to N - 1 do
    begin
      Sec := 'ColorRule' + IntToStr(I);
      AppSettings.ColorRules[I].Pattern := Trim(Ini.ReadString(Sec, 'Pattern', ''));
      AppSettings.ColorRules[I].Color := ReadColor(Ini, Sec, 'Color', AppSettings.BgColor);
      AppSettings.ColorRules[I].FgColor := ReadColor(Ini, Sec, 'FgColor', NO_COLOR_OVERRIDE);
      AppSettings.ColorRules[I].Enabled := Ini.ReadBool(Sec, 'Enabled', True);
      AppSettings.ColorRules[I].UseLevel := Ini.ReadBool(Sec, 'UseLevel', False);
      V := Ini.ReadInteger(Sec, 'Level', Integer(lCustom));
      if (V < Ord(Low(TLogLevel))) or (V > Ord(High(TLogLevel))) then
        V := Ord(lCustom);
      AppSettings.ColorRules[I].Level := TLogLevel(V);
      if AppSettings.ColorRules[I].Pattern <> '' then
        Inc(AppSettings.ColorRuleCount);
    end;

    AppSettings.AutoDetectFormat := Ini.ReadBool('Format', 'AutoDetect', AppSettings.AutoDetectFormat);
    V := Ini.ReadInteger('Format', 'ForceFormat', Integer(AppSettings.ForceFormat));
    if (V >= Ord(Low(TLogFormat))) and (V <= Ord(High(TLogFormat))) then
      AppSettings.ForceFormat := TLogFormat(V);

    with AppSettings.CustomFormat do
    begin
      V := Ini.ReadInteger('CustomFormat', 'Mode', Integer(Mode));
      if (V >= Ord(Low(TCustomFormatMode))) and (V <= Ord(High(TCustomFormatMode))) then
        Mode := TCustomFormatMode(V);
      Delimiter := Char(Ini.ReadInteger('CustomFormat', 'Delimiter', Integer(Delimiter)));
      FieldCount := EnsureRange(Ini.ReadInteger('CustomFormat', 'FieldCount', FieldCount), 1, MAX_CUSTOM_FIELDS);
      for I := 0 to MAX_CUSTOM_FIELDS - 1 do
      begin
        V := Ini.ReadInteger('CustomFormat', 'Field' + IntToStr(I), Integer(FieldRoles[I]));
        if (V >= Ord(Low(TCustomFieldRole))) and (V <= Ord(High(TCustomFieldRole))) then
          FieldRoles[I] := TCustomFieldRole(V)
        else
          FieldRoles[I] := cfrIgnore;
      end;
      TSStart := Ini.ReadInteger('CustomFormat', 'TSStart', TSStart);
      TSLen := Ini.ReadInteger('CustomFormat', 'TSLen', TSLen);
      LvlStart := Ini.ReadInteger('CustomFormat', 'LvlStart', LvlStart);
      LvlLen := Ini.ReadInteger('CustomFormat', 'LvlLen', LvlLen);
      SrcStart := Ini.ReadInteger('CustomFormat', 'SrcStart', SrcStart);
      SrcLen := Ini.ReadInteger('CustomFormat', 'SrcLen', SrcLen);
      TimestampFmt := Trim(Ini.ReadString('CustomFormat', 'TimestampFmt', TimestampFmt));
      if TimestampFmt = '' then
        TimestampFmt := 'YYYY-MM-DD hh:nn:ss';
    end;

    AppSettings.TailEnabled := Ini.ReadBool('Tail', 'Enabled', AppSettings.TailEnabled);
    AppSettings.TailIntervalMs := EnsureRange(Ini.ReadInteger('Tail', 'IntervalMs', AppSettings.TailIntervalMs), 200, 30000);
    AppSettings.CloseOnEscInLister := Ini.ReadBool('View', 'CloseOnEscInLister', AppSettings.CloseOnEscInLister);

    AppSettings.WinLeft := Ini.ReadInteger('Window', 'Left', AppSettings.WinLeft);
    AppSettings.WinTop := Ini.ReadInteger('Window', 'Top', AppSettings.WinTop);
    AppSettings.WinWidth := Ini.ReadInteger('Window', 'Width', AppSettings.WinWidth);
    AppSettings.WinHeight := Ini.ReadInteger('Window', 'Height', AppSettings.WinHeight);
    AppSettings.WinMaximized := Ini.ReadBool('Window', 'Maximized', AppSettings.WinMaximized);
    AppSettings.LastDir := Ini.ReadString('Files', 'LastDir', AppSettings.LastDir);
  finally
    Ini.Free;
  end;

  ApplyThemeColors;
end;

procedure SaveSettings;
var
  Ini: TIniFile;
  I: Integer;
  Sec: string;
begin
  ApplyThemeColors;
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteBool('View', 'ShowLineNumbers', AppSettings.ShowLineNumbers);
    Ini.WriteInteger('View', 'LineNumWidth', AppSettings.LineNumberWidth);
    Ini.WriteBool('View', 'WordWrap', AppSettings.WordWrap);
    Ini.WriteBool('View', 'HorzScrollbar', AppSettings.ShowHorzScrollbar);
    Ini.WriteString('View', 'FontName', AppSettings.FontName);
    Ini.WriteInteger('View', 'FontSize', AppSettings.FontSize);

    Ini.WriteInteger('Theme', 'Mode', Integer(AppSettings.ThemeMode));
    SaveThemeColors(Ini, 'ColorsLight', AppSettings.LightColors);
    SaveThemeColors(Ini, 'ColorsDark', AppSettings.DarkColors);
    if IsDarkModeActive then
      SaveThemeColors(Ini, 'Colors', AppSettings.DarkColors)
    else
      SaveThemeColors(Ini, 'Colors', AppSettings.LightColors);

    Ini.WriteInteger('ColorRules', 'Count', AppSettings.ColorRuleCount);
    for I := 0 to AppSettings.ColorRuleCount - 1 do
    begin
      Sec := 'ColorRule' + IntToStr(I);
      Ini.WriteString(Sec, 'Pattern', AppSettings.ColorRules[I].Pattern);
      Ini.WriteInteger(Sec, 'Color', Integer(AppSettings.ColorRules[I].Color));
      Ini.WriteInteger(Sec, 'FgColor', Integer(AppSettings.ColorRules[I].FgColor));
      Ini.WriteBool(Sec, 'Enabled', AppSettings.ColorRules[I].Enabled);
      Ini.WriteBool(Sec, 'UseLevel', AppSettings.ColorRules[I].UseLevel);
      Ini.WriteInteger(Sec, 'Level', Integer(AppSettings.ColorRules[I].Level));
    end;

    Ini.WriteBool('Format', 'AutoDetect', AppSettings.AutoDetectFormat);
    Ini.WriteInteger('Format', 'ForceFormat', Integer(AppSettings.ForceFormat));

    with AppSettings.CustomFormat do
    begin
      Ini.WriteInteger('CustomFormat', 'Mode', Integer(Mode));
      Ini.WriteInteger('CustomFormat', 'Delimiter', Integer(Delimiter));
      Ini.WriteInteger('CustomFormat', 'FieldCount', FieldCount);
      for I := 0 to MAX_CUSTOM_FIELDS - 1 do
        Ini.WriteInteger('CustomFormat', 'Field' + IntToStr(I), Integer(FieldRoles[I]));
      Ini.WriteInteger('CustomFormat', 'TSStart', TSStart);
      Ini.WriteInteger('CustomFormat', 'TSLen', TSLen);
      Ini.WriteInteger('CustomFormat', 'LvlStart', LvlStart);
      Ini.WriteInteger('CustomFormat', 'LvlLen', LvlLen);
      Ini.WriteInteger('CustomFormat', 'SrcStart', SrcStart);
      Ini.WriteInteger('CustomFormat', 'SrcLen', SrcLen);
      Ini.WriteString('CustomFormat', 'TimestampFmt', TimestampFmt);
    end;

    Ini.WriteBool('Tail', 'Enabled', AppSettings.TailEnabled);
    Ini.WriteInteger('Tail', 'IntervalMs', AppSettings.TailIntervalMs);
    Ini.WriteBool('View', 'CloseOnEscInLister', AppSettings.CloseOnEscInLister);

    Ini.WriteInteger('Window', 'Left', AppSettings.WinLeft);
    Ini.WriteInteger('Window', 'Top', AppSettings.WinTop);
    Ini.WriteInteger('Window', 'Width', AppSettings.WinWidth);
    Ini.WriteInteger('Window', 'Height', AppSettings.WinHeight);
    Ini.WriteBool('Window', 'Maximized', AppSettings.WinMaximized);
    Ini.WriteString('Files', 'LastDir', AppSettings.LastDir);
  finally
    Ini.Free;
  end;
end;

initialization
  DefaultSettings;

end.
