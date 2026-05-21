unit uSettings;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, IniFiles, Graphics, uLogTypes
  {$IFDEF WINDOWS}, Registry{$ENDIF};

const
  MAX_COLOR_STRINGS = 20;

type
  TThemeMode = (tmSystem, tmLight, tmDark);

  TColorStringRule = record
    Pattern    : string;
    Color      : TColor;       // Hintergrundfarbe
    FgColor    : TColor;       // Vordergrundfarbe (clDefault = automatisch)
    Enabled    : Boolean;
    UseLevel   : Boolean;      // True = Level-Klasse setzen
    Level      : TLogLevel;
  end;

  { Farbset fuer ein Theme (Light oder Dark) }
  TThemeColors = record
    ColError  : TColor;
    ColWarn   : TColor;
    ColInfo   : TColor;
    ColDebug  : TColor;
    ColTrace  : TColor;
    ColCustom : TColor;
    FgError   : TColor;
    FgWarn    : TColor;
    FgInfo    : TColor;
    FgDebug   : TColor;
    FgTrace   : TColor;
    FgCustom  : TColor;
    // UI-Chrome-Farben
    BgDefault : TColor;   // Hintergrund fuer ListBox etc.
    FgDefault : TColor;   // Standard-Vordergrundfarbe
    BgToolbar : TColor;
    BgStatus  : TColor;
    FgStatus  : TColor;
  end;

  TAppSettings = record
    // Ansicht
    ShowLineNumbers   : Boolean;
    LineNumberWidth   : Integer;
    WordWrap          : Boolean;
    FontName          : string;
    FontSize          : Integer;
    // Theme
    ThemeMode         : TThemeMode;
    LightColors       : TThemeColors;
    DarkColors        : TThemeColors;
    // Die "aktiven" Farben - werden bei ApplyThemeColors gesetzt
    ColError          : TColor;
    ColWarn           : TColor;
    ColInfo           : TColor;
    ColDebug          : TColor;
    ColTrace          : TColor;
    ColCustom         : TColor;
    FgError           : TColor;
    FgWarn            : TColor;
    FgInfo            : TColor;
    FgDebug           : TColor;
    FgTrace           : TColor;
    FgCustom          : TColor;
    BgDefault         : TColor;
    FgDefault         : TColor;
    BgToolbar         : TColor;
    BgStatus          : TColor;
    FgStatus          : TColor;
    // Benutzerdefinierte Farb-String-Regeln
    ColorRules        : array[0..MAX_COLOR_STRINGS-1] of TColorStringRule;
    ColorRuleCount    : Integer;
    // Logformat
    AutoDetectFormat  : Boolean;
    ForceFormat       : TLogFormat;
    CustomFormat      : TCustomFormatConfig;
    // Tail
    TailEnabled       : Boolean;
    TailIntervalMs    : Integer;
    // Fenster
    WinLeft           : Integer;
    WinTop            : Integer;
    WinWidth          : Integer;
    WinHeight         : Integer;
    WinMaximized      : Boolean;
    // zuletzt geoeffneter Ordner
    LastDir           : string;
  end;

var
  AppSettings: TAppSettings;

procedure LoadSettings;
procedure SaveSettings;
procedure DefaultSettings;
function  SystemIsDarkMode: Boolean;
function  IsDarkModeActive: Boolean;
procedure ApplyThemeColors;

implementation

function IniPath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'LogViewer.ini';
end;

{ Erkennt den Windows-Darkmode ueber die Registry }
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
    tmDark  : Result := True;
    tmLight : Result := False;
  else
    Result := SystemIsDarkMode;
  end;
end;

{ Kopiert das aktive Farbset in die "aktiven" Felder }
procedure ApplyThemeColors;
var
  C: TThemeColors;
begin
  if IsDarkModeActive then
    C := AppSettings.DarkColors
  else
    C := AppSettings.LightColors;

  AppSettings.ColError  := C.ColError;
  AppSettings.ColWarn   := C.ColWarn;
  AppSettings.ColInfo   := C.ColInfo;
  AppSettings.ColDebug  := C.ColDebug;
  AppSettings.ColTrace  := C.ColTrace;
  AppSettings.ColCustom := C.ColCustom;
  AppSettings.FgError   := C.FgError;
  AppSettings.FgWarn    := C.FgWarn;
  AppSettings.FgInfo    := C.FgInfo;
  AppSettings.FgDebug   := C.FgDebug;
  AppSettings.FgTrace   := C.FgTrace;
  AppSettings.FgCustom  := C.FgCustom;
  AppSettings.BgDefault := C.BgDefault;
  AppSettings.FgDefault := C.FgDefault;
  AppSettings.BgToolbar := C.BgToolbar;
  AppSettings.BgStatus  := C.BgStatus;
  AppSettings.FgStatus  := C.FgStatus;
end;

procedure DefaultLightColors(out C: TThemeColors);
begin
  C.ColError  := $00AAAAFF;  // helles Rot
  C.ColWarn   := $0000AAFF;  // helles Orange
  C.ColInfo   := $0000FFFF;  // helles Gelb
  C.ColDebug  := $00F0F0F0;  // helles Grau
  C.ColTrace  := $00FFE8D0;  // helles Blau
  C.ColCustom := clInfoBk;
  C.FgError   := clBlack;
  C.FgWarn    := clBlack;
  C.FgInfo    := clBlack;
  C.FgDebug   := clBlack;
  C.FgTrace   := clBlack;
  C.FgCustom  := clBlack;
  C.BgDefault := clWindow;
  C.FgDefault := clWindowText;
  C.BgToolbar := clBtnFace;
  C.BgStatus  := clBtnFace;
  C.FgStatus  := clBtnText;
end;

procedure DefaultDarkColors(out C: TThemeColors);
begin
  C.ColError  := $00102040;  // dunkles Rot
  C.ColWarn   := $00103848;  // dunkles Orange
  C.ColInfo   := $00184040;  // dunkles Gelb/Olive
  C.ColDebug  := $00383838;  // dunkles Grau
  C.ColTrace  := $00403028;  // dunkles Blau
  C.ColCustom := $00303030;
  C.FgError   := $00AAAAFF;  // helles Rot als Schrift
  C.FgWarn    := $0080CCFF;  // helles Orange als Schrift
  C.FgInfo    := $0080FFFF;  // helles Gelb als Schrift
  C.FgDebug   := $00C0C0C0;  // Silber
  C.FgTrace   := $00D0C0A0;  // helles Beige
  C.FgCustom  := $00C0C0C0;
  C.BgDefault := $00282828;  // Hintergrund ListBox/Edits
  C.FgDefault := $00D4D4D4;  // helles Grau
  C.BgToolbar := $003A3A3A;  // Hintergrund Toolbar/Tabs/Form
  C.BgStatus  := $00007ACC;  // blaue Statusleiste
  C.FgStatus  := $00FFFFFF;
end;

procedure DefaultSettings;
begin
  AppSettings.ShowLineNumbers  := True;
  AppSettings.LineNumberWidth  := 5;
  AppSettings.WordWrap         := False;
  AppSettings.FontName         := 'Courier New';
  AppSettings.FontSize         := 9;
  AppSettings.ThemeMode        := tmSystem;

  DefaultLightColors(AppSettings.LightColors);
  DefaultDarkColors(AppSettings.DarkColors);

  AppSettings.ColorRuleCount   := 0;
  AppSettings.AutoDetectFormat := True;
  AppSettings.ForceFormat      := lfPlain;
  // Custom Format Defaults
  AppSettings.CustomFormat.Mode         := cfmDelimiter;
  AppSettings.CustomFormat.Delimiter    := '|';
  AppSettings.CustomFormat.FieldCount   := 4;
  AppSettings.CustomFormat.FieldRoles[0] := cfrTimestamp;
  AppSettings.CustomFormat.FieldRoles[1] := cfrLevel;
  AppSettings.CustomFormat.FieldRoles[2] := cfrSource;
  AppSettings.CustomFormat.FieldRoles[3] := cfrIgnore;
  AppSettings.CustomFormat.TSStart      := 0;
  AppSettings.CustomFormat.TSLen        := 0;
  AppSettings.CustomFormat.LvlStart     := 0;
  AppSettings.CustomFormat.LvlLen       := 0;
  AppSettings.CustomFormat.SrcStart     := 0;
  AppSettings.CustomFormat.SrcLen       := 0;
  AppSettings.CustomFormat.TimestampFmt := 'YYYY-MM-DD hh:nn:ss';
  AppSettings.TailEnabled      := False;
  AppSettings.TailIntervalMs   := 1000;
  AppSettings.WinLeft          := 100;
  AppSettings.WinTop           := 80;
  AppSettings.WinWidth         := 960;
  AppSettings.WinHeight        := 650;
  AppSettings.WinMaximized     := False;
  AppSettings.LastDir          := '';

  ApplyThemeColors;
end;

procedure LoadThemeColors(Ini: TIniFile; const Section: string;
  var C: TThemeColors);
begin
  C.ColError  := TColor(Ini.ReadInteger(Section, 'Error',     Integer(C.ColError)));
  C.ColWarn   := TColor(Ini.ReadInteger(Section, 'Warn',      Integer(C.ColWarn)));
  C.ColInfo   := TColor(Ini.ReadInteger(Section, 'Info',      Integer(C.ColInfo)));
  C.ColDebug  := TColor(Ini.ReadInteger(Section, 'Debug',     Integer(C.ColDebug)));
  C.ColTrace  := TColor(Ini.ReadInteger(Section, 'Trace',     Integer(C.ColTrace)));
  C.ColCustom := TColor(Ini.ReadInteger(Section, 'Custom',    Integer(C.ColCustom)));
  C.FgError   := TColor(Ini.ReadInteger(Section, 'FgError',   Integer(C.FgError)));
  C.FgWarn    := TColor(Ini.ReadInteger(Section, 'FgWarn',    Integer(C.FgWarn)));
  C.FgInfo    := TColor(Ini.ReadInteger(Section, 'FgInfo',    Integer(C.FgInfo)));
  C.FgDebug   := TColor(Ini.ReadInteger(Section, 'FgDebug',   Integer(C.FgDebug)));
  C.FgTrace   := TColor(Ini.ReadInteger(Section, 'FgTrace',   Integer(C.FgTrace)));
  C.FgCustom  := TColor(Ini.ReadInteger(Section, 'FgCustom',  Integer(C.FgCustom)));
  C.BgDefault := TColor(Ini.ReadInteger(Section, 'BgDefault', Integer(C.BgDefault)));
  C.FgDefault := TColor(Ini.ReadInteger(Section, 'FgDefault', Integer(C.FgDefault)));
  C.BgToolbar := TColor(Ini.ReadInteger(Section, 'BgToolbar', Integer(C.BgToolbar)));
  C.BgStatus  := TColor(Ini.ReadInteger(Section, 'BgStatus',  Integer(C.BgStatus)));
  C.FgStatus  := TColor(Ini.ReadInteger(Section, 'FgStatus',  Integer(C.FgStatus)));
end;

procedure SaveThemeColors(Ini: TIniFile; const Section: string;
  const C: TThemeColors);
begin
  Ini.WriteInteger(Section, 'Error',     Integer(C.ColError));
  Ini.WriteInteger(Section, 'Warn',      Integer(C.ColWarn));
  Ini.WriteInteger(Section, 'Info',      Integer(C.ColInfo));
  Ini.WriteInteger(Section, 'Debug',     Integer(C.ColDebug));
  Ini.WriteInteger(Section, 'Trace',     Integer(C.ColTrace));
  Ini.WriteInteger(Section, 'Custom',    Integer(C.ColCustom));
  Ini.WriteInteger(Section, 'FgError',   Integer(C.FgError));
  Ini.WriteInteger(Section, 'FgWarn',    Integer(C.FgWarn));
  Ini.WriteInteger(Section, 'FgInfo',    Integer(C.FgInfo));
  Ini.WriteInteger(Section, 'FgDebug',   Integer(C.FgDebug));
  Ini.WriteInteger(Section, 'FgTrace',   Integer(C.FgTrace));
  Ini.WriteInteger(Section, 'FgCustom',  Integer(C.FgCustom));
  Ini.WriteInteger(Section, 'BgDefault', Integer(C.BgDefault));
  Ini.WriteInteger(Section, 'FgDefault', Integer(C.FgDefault));
  Ini.WriteInteger(Section, 'BgToolbar', Integer(C.BgToolbar));
  Ini.WriteInteger(Section, 'BgStatus',  Integer(C.BgStatus));
  Ini.WriteInteger(Section, 'FgStatus',  Integer(C.FgStatus));
end;

procedure LoadSettings;
var
  Ini  : TIniFile;
  i, N : Integer;
  Sec  : string;
begin
  DefaultSettings;
  if not FileExists(IniPath) then Exit;
  Ini := TIniFile.Create(IniPath);
  try
    AppSettings.ShowLineNumbers  := Ini.ReadBool   ('View',   'ShowLineNumbers', AppSettings.ShowLineNumbers);
    AppSettings.LineNumberWidth  := Ini.ReadInteger('View',   'LineNumWidth',    5);
    if AppSettings.LineNumberWidth < 1 then AppSettings.LineNumberWidth := 1;
    if AppSettings.LineNumberWidth > 9 then AppSettings.LineNumberWidth := 9;
    AppSettings.WordWrap         := Ini.ReadBool   ('View',   'WordWrap',        AppSettings.WordWrap);
    AppSettings.FontName         := Ini.ReadString ('View',   'FontName',        AppSettings.FontName);
    AppSettings.FontSize         := Ini.ReadInteger('View',   'FontSize',        AppSettings.FontSize);

    AppSettings.ThemeMode := TThemeMode(Ini.ReadInteger('Theme', 'Mode',
      Integer(tmSystem)));

    // Migration: alte INI ohne Theme-Sektionen -> Light-Farben aus [Colors]
    if Ini.SectionExists('ColorsLight') then
      LoadThemeColors(Ini, 'ColorsLight', AppSettings.LightColors)
    else if Ini.SectionExists('Colors') then
      LoadThemeColors(Ini, 'Colors', AppSettings.LightColors);

    if Ini.SectionExists('ColorsDark') then
      LoadThemeColors(Ini, 'ColorsDark', AppSettings.DarkColors);

    N := Ini.ReadInteger('ColorRules', 'Count', 0);
    AppSettings.ColorRuleCount := 0;
    for i := 0 to N - 1 do
    begin
      if i >= MAX_COLOR_STRINGS then Break;
      Sec := 'ColorRule' + IntToStr(i);
      AppSettings.ColorRules[i].Pattern  := Ini.ReadString (Sec, 'Pattern', '');
      AppSettings.ColorRules[i].Color    := TColor(Ini.ReadInteger(Sec, 'Color',
        Integer(clWindowText)));
      AppSettings.ColorRules[i].Enabled  := Ini.ReadBool   (Sec, 'Enabled', True);
      AppSettings.ColorRules[i].UseLevel := Ini.ReadBool   (Sec, 'UseLevel', False);
      AppSettings.ColorRules[i].Level    := TLogLevel(Ini.ReadInteger(Sec, 'Level',
        Integer(lCustom)));
      AppSettings.ColorRules[i].FgColor  := TColor(Ini.ReadInteger(Sec, 'FgColor',
        Integer(clDefault)));
      if AppSettings.ColorRules[i].Pattern <> '' then
        Inc(AppSettings.ColorRuleCount);
    end;

    AppSettings.AutoDetectFormat := Ini.ReadBool   ('Format', 'AutoDetect',
      AppSettings.AutoDetectFormat);
    AppSettings.ForceFormat      := TLogFormat(Ini.ReadInteger('Format',
      'ForceFormat', Integer(AppSettings.ForceFormat)));

    // Custom Format
    with AppSettings.CustomFormat do
    begin
      Mode         := TCustomFormatMode(Ini.ReadInteger('CustomFormat', 'Mode', Integer(Mode)));
      Delimiter    := Char(Ini.ReadInteger('CustomFormat', 'Delimiter', Integer(Delimiter)));
      FieldCount   := Ini.ReadInteger('CustomFormat', 'FieldCount', FieldCount);
      if FieldCount > MAX_CUSTOM_FIELDS then FieldCount := MAX_CUSTOM_FIELDS;
      for i := 0 to MAX_CUSTOM_FIELDS - 1 do
        FieldRoles[i] := TCustomFieldRole(Ini.ReadInteger('CustomFormat',
          'Field' + IntToStr(i), Integer(FieldRoles[i])));
      TSStart      := Ini.ReadInteger('CustomFormat', 'TSStart',  TSStart);
      TSLen        := Ini.ReadInteger('CustomFormat', 'TSLen',    TSLen);
      LvlStart     := Ini.ReadInteger('CustomFormat', 'LvlStart', LvlStart);
      LvlLen       := Ini.ReadInteger('CustomFormat', 'LvlLen',   LvlLen);
      SrcStart     := Ini.ReadInteger('CustomFormat', 'SrcStart', SrcStart);
      SrcLen       := Ini.ReadInteger('CustomFormat', 'SrcLen',   SrcLen);
      TimestampFmt := Ini.ReadString ('CustomFormat', 'TimestampFmt', TimestampFmt);
    end;

    AppSettings.TailEnabled    := Ini.ReadBool   ('Tail', 'Enabled',
      AppSettings.TailEnabled);
    AppSettings.TailIntervalMs := Ini.ReadInteger('Tail', 'IntervalMs',
      AppSettings.TailIntervalMs);

    AppSettings.WinLeft      := Ini.ReadInteger('Window', 'Left',
      AppSettings.WinLeft);
    AppSettings.WinTop       := Ini.ReadInteger('Window', 'Top',
      AppSettings.WinTop);
    AppSettings.WinWidth     := Ini.ReadInteger('Window', 'Width',
      AppSettings.WinWidth);
    AppSettings.WinHeight    := Ini.ReadInteger('Window', 'Height',
      AppSettings.WinHeight);
    AppSettings.WinMaximized := Ini.ReadBool   ('Window', 'Maximized',
      AppSettings.WinMaximized);
    AppSettings.LastDir      := Ini.ReadString ('Files',  'LastDir',
      AppSettings.LastDir);
  finally
    Ini.Free;
  end;

  ApplyThemeColors;
end;

procedure SaveSettings;
var
  Ini : TIniFile;
  i   : Integer;
  Sec : string;
begin
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteBool   ('View',   'ShowLineNumbers', AppSettings.ShowLineNumbers);
    Ini.WriteInteger('View',   'LineNumWidth',    AppSettings.LineNumberWidth);
    Ini.WriteBool   ('View',   'WordWrap',        AppSettings.WordWrap);
    Ini.WriteString ('View',   'FontName',        AppSettings.FontName);
    Ini.WriteInteger('View',   'FontSize',        AppSettings.FontSize);

    Ini.WriteInteger('Theme',  'Mode',            Integer(AppSettings.ThemeMode));

    SaveThemeColors(Ini, 'ColorsLight', AppSettings.LightColors);
    SaveThemeColors(Ini, 'ColorsDark',  AppSettings.DarkColors);

    Ini.WriteInteger('ColorRules', 'Count', AppSettings.ColorRuleCount);
    for i := 0 to AppSettings.ColorRuleCount - 1 do
    begin
      Sec := 'ColorRule' + IntToStr(i);
      Ini.WriteString (Sec, 'Pattern',  AppSettings.ColorRules[i].Pattern);
      Ini.WriteInteger(Sec, 'Color',    Integer(AppSettings.ColorRules[i].Color));
      Ini.WriteBool   (Sec, 'Enabled',  AppSettings.ColorRules[i].Enabled);
      Ini.WriteBool   (Sec, 'UseLevel', AppSettings.ColorRules[i].UseLevel);
      Ini.WriteInteger(Sec, 'Level',    Integer(AppSettings.ColorRules[i].Level));
      Ini.WriteInteger(Sec, 'FgColor',  Integer(AppSettings.ColorRules[i].FgColor));
    end;

    Ini.WriteBool   ('Format', 'AutoDetect',  AppSettings.AutoDetectFormat);
    Ini.WriteInteger('Format', 'ForceFormat', Integer(AppSettings.ForceFormat));

    // Custom Format
    with AppSettings.CustomFormat do
    begin
      Ini.WriteInteger('CustomFormat', 'Mode',      Integer(Mode));
      Ini.WriteInteger('CustomFormat', 'Delimiter',  Integer(Delimiter));
      Ini.WriteInteger('CustomFormat', 'FieldCount', FieldCount);
      for i := 0 to MAX_CUSTOM_FIELDS - 1 do
        Ini.WriteInteger('CustomFormat', 'Field' + IntToStr(i), Integer(FieldRoles[i]));
      Ini.WriteInteger('CustomFormat', 'TSStart',  TSStart);
      Ini.WriteInteger('CustomFormat', 'TSLen',    TSLen);
      Ini.WriteInteger('CustomFormat', 'LvlStart', LvlStart);
      Ini.WriteInteger('CustomFormat', 'LvlLen',   LvlLen);
      Ini.WriteInteger('CustomFormat', 'SrcStart', SrcStart);
      Ini.WriteInteger('CustomFormat', 'SrcLen',   SrcLen);
      Ini.WriteString ('CustomFormat', 'TimestampFmt', TimestampFmt);
    end;

    Ini.WriteBool   ('Tail',   'Enabled',    AppSettings.TailEnabled);
    Ini.WriteInteger('Tail',   'IntervalMs', AppSettings.TailIntervalMs);

    Ini.WriteInteger('Window', 'Left',      AppSettings.WinLeft);
    Ini.WriteInteger('Window', 'Top',       AppSettings.WinTop);
    Ini.WriteInteger('Window', 'Width',     AppSettings.WinWidth);
    Ini.WriteInteger('Window', 'Height',    AppSettings.WinHeight);
    Ini.WriteBool   ('Window', 'Maximized', AppSettings.WinMaximized);
    Ini.WriteString ('Files',  'LastDir',   AppSettings.LastDir);
  finally
    Ini.Free;
  end;
end;

end.
