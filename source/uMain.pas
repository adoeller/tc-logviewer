unit uMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  Menus, StdCtrls, ComCtrls, ExtCtrls, Buttons, LCLIntf, LCLType,
  Clipbrd, Spin, Math,
  DateTimePicker,
  uLogTypes, uLogModel, uLogParser, uLogFilter,
  uSettings, uFormats, uTailWatcher, uOptionsDlg, uLogView;

type

  TfrmMain = class(TForm)
  private
    MainMenu1     : TMainMenu;
    mniDatei      : TMenuItem;
    mniBearbeiten : TMenuItem;
    mniCopyLine   : TMenuItem;
    mniCopyAll    : TMenuItem;
    mniAnsicht    : TMenuItem;
    mniLineNr     : TMenuItem;
    mniWordWrap   : TMenuItem;
    mniOptionen   : TMenuItem;
    mniSuchen     : TMenuItem;
    mniFilter     : TMenuItem;
    mniNavi       : TMenuItem;
    mniNextErr    : TMenuItem;
    mniPrevErr    : TMenuItem;
    mniTail       : TMenuItem;
    mniTailToggle : TMenuItem;
    pnlToolbar     : TPanel;
    chkTailBtn     : TCheckBox;
    chkFollowBtn   : TCheckBox;
    edtQuickSearch : TEdit;
    btnClearSearch : TSpeedButton;
    lblQuickSearch : TLabel;
    FFollowTail    : Boolean;
    lbLog         : TLogView;
    sbStatus      : TStatusBar;
    sbpMain       : TStatusPanel;   // Dateiname + Zeilen
    sbpEWI        : TStatusPanel;   // E/W/I Counts (fett je nach neuestem)
    FLastStatTime : TDateTime;      // Zeitpunkt des zuletzt geaenderten Zählers
    OpenDialog    : TOpenDialog;
    PopupMenu1    : TPopupMenu;
    mniPopCopy    : TMenuItem;
    mniPopCopyAll : TMenuItem;
    FTail         : TTailWatcher;
    FLog          : TLogList;
    FFilter       : TFilterSpec;
    FFileName     : string;
    FFileSize     : Int64;
    FFiltered     : TLogEntryArray;
    FFilteredCount: Integer;
    FFilteredDirect: Boolean;   // True = FFiltered zeigt direkt auf FLog.RawItems
    FECount       : Integer;
    FWCount       : Integer;
    FICount       : Integer;
    FLastETime    : TDateTime;
    FLastWTime    : TDateTime;
    FLastITime    : TDateTime;
    FDetectedFmt  : TLogFormat;
    FCurrentFmt   : TLogFormat;
    FSearchText   : string;
    FSepLineX     : Integer;
    FMaxLineWidth : Integer;
    FCachedCharW  : Integer;   // Pixel-Breite eines Zeichens (gecacht aus DrawItem)
    FResizeTimer  : TTimer;
    FFilterTimer  : TTimer;   // 100ms Debounce fuer QuickSearch   // gecachte X-Position der Trennlinie (-1 = neu berechnen)

    procedure BuildUI;
    procedure ResetStats;
    function GetFileSizeByName(const AFilename: string): Int64;
    procedure UpdateStatsForEntry(const AEntry: TLogEntry);
    procedure RecalcStatsFrom(const AStartIdx: Integer);
    procedure ApplyAppSettings;
    procedure ApplyThemeToUI;
    procedure LoadFile(const AFilename: string);
    procedure UpdateStatus;
    procedure ApplyFilterAndRefresh;
    procedure GotoError(AForward: Boolean);
    procedure GotoLineNumber(ALine: Integer);
    procedure ShowSearchDialog;
    procedure SearchText(AForward: Boolean);
    procedure ShowFilterDialog;
    procedure ShowGotoDateDialog;
    procedure ShowGotoLineDialog;
    procedure CopySelectedLine;
    procedure CopyAllVisible;
    procedure OnTailNewLine(const ALine: string; ALineNo: Integer);
    function  FormatLogLine(AIndex: Integer): string;
    function  ColorForLine(AIndex: Integer): TColor;
    function  FgColorForLine(AIndex: Integer): TColor;

    procedure DoOeffnen(Sender: TObject);
    procedure DoBeenden(Sender: TObject);
    procedure DoLineNr(Sender: TObject);
    procedure DoWordWrap(Sender: TObject);
    procedure DoOptionen(Sender: TObject);
    procedure DoSucheDlg(Sender: TObject);
    procedure DoSearchNext(Sender: TObject);
    procedure DoSearchPrev(Sender: TObject);
    procedure DoSucheReset(Sender: TObject);
    procedure DoNextErr(Sender: TObject);
    procedure DoPrevErr(Sender: TObject);
    procedure DoGotoDate(Sender: TObject);
    procedure DoGotoLine(Sender: TObject);
    procedure DoFilterDlg(Sender: TObject);
    procedure DoFilterReset(Sender: TObject);
    procedure DoTailToggle(Sender: TObject);
    procedure DoFollowTailToggle(Sender: TObject);
    procedure GotoLevel(AForward: Boolean; ALevel: TLogLevel);
    procedure DoPrevWarn(Sender: TObject);
    procedure DoNextWarn(Sender: TObject);
    procedure DoPrevInfo(Sender: TObject);
    procedure DoNextInfo(Sender: TObject);
    procedure DoCopyLine(Sender: TObject);
    procedure DoCopyAll(Sender: TObject);
    procedure DoQuickSearch(Sender: TObject);
    procedure DoClearSearch(Sender: TObject);
    procedure lbLogDrawItem(Control: TWinControl; Index: Integer;
      ARect: TRect; State: TOwnerDrawState);
    procedure lbLogMeasureItem(Control: TWinControl; Index: Integer;
      var AHeight: Integer);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormResizeHandler(Sender: TObject);
    procedure ResizeTimerFired(Sender: TObject);
    procedure FilterTimerFired(Sender: TObject);
    procedure sbStatusDrawPanel(StatusBar: TStatusBar; Panel: TStatusPanel;
      const Rect: TRect);
    procedure sbStatusResize(Sender: TObject);
    procedure PositionQuickSearch;
    procedure DisableFollowTemp;
    procedure ScrollToEndCurrent;
    procedure UpdateHorzScrollbar;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  frmMain: TfrmMain;

implementation

const
  READ_BUF_SIZE = 131072;   // 128 KB I/O-Puffer

{ TfrmMain }

procedure TfrmMain.DisableFollowTemp;
begin
  FFollowTail := False;
  chkFollowBtn.Checked := False;
end;

procedure TfrmMain.ScrollToEndCurrent;
begin
  if FFollowTail and (FFilteredCount > 0) then
  begin
    lbLog.ScrollToEnd;
  end;
end;

// Hintergrundfarbe aus Level-Einstellungen
function LevelColor(ALevel: TLogLevel): TColor;
begin
  case ALevel of
    lError : Result := AppSettings.ColError;
    lWarn  : Result := AppSettings.ColWarn;
    lInfo  : Result := AppSettings.ColInfo;
    lDebug : Result := AppSettings.ColDebug;
    lTrace : Result := AppSettings.ColTrace;
  else
    Result := AppSettings.ColCustom;
  end;
end;

// Vordergrundfarbe aus Level-Einstellungen
function LevelFgColor(ALevel: TLogLevel): TColor;
begin
  case ALevel of
    lError : Result := AppSettings.FgError;
    lWarn  : Result := AppSettings.FgWarn;
    lInfo  : Result := AppSettings.FgInfo;
    lDebug : Result := AppSettings.FgDebug;
    lTrace : Result := AppSettings.FgTrace;
  else
    Result := AppSettings.FgCustom;
  end;
end;

// Erzeugt den Anzeigetext fuer eine Zeile – nur bei Bedarf (sichtbare Zeilen)
function TfrmMain.FormatLogLine(AIndex: Integer): string;
var
  NumStr : string;
  Pad    : Integer;
  RawS   : string;
begin
  if (AIndex < 0) or (AIndex >= FFilteredCount) then
  begin Result := ''; Exit; end;
  RawS := FLog.RawStr(FFiltered[AIndex].RawOffset, FFiltered[AIndex].RawLen);
  if AppSettings.ShowLineNumbers then
  begin
    NumStr := IntToStr(FFiltered[AIndex].LineNo);
    Pad := AppSettings.LineNumberWidth - Length(NumStr);
    if Pad > 0 then
      Result := StringOfChar(' ', Pad) + NumStr + '  ' + RawS
    else
      Result := NumStr + '  ' + RawS;
  end
  else
    Result := RawS;
end;

constructor TfrmMain.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  LoadSettings;
  FLog          := TLogList.Create;
  FFilter       := TFilterSpec.Create(FLog);
  FTail         := TTailWatcher.Create;
  FTail.OnNewLine := @OnTailNewLine;
  FFileName     := '';
  FFileSize     := 0;
  FFiltered     := nil;
  FFilteredCount := 0;
  FFilteredDirect := False;
  FDetectedFmt  := lfPlain;
  FCurrentFmt   := lfPlain;
  FFollowTail   := True;
  FSearchText   := '';
  FSepLineX     := -1;
  FLastStatTime := 0;
  FMaxLineWidth := 0;
  FCachedCharW  := 0;
  FResizeTimer          := TTimer.Create(Self);
  FResizeTimer.Interval := 500;
  FResizeTimer.Enabled  := False;
  FResizeTimer.OnTimer  := @ResizeTimerFired;
  FFilterTimer          := TTimer.Create(Self);
  FFilterTimer.Interval := 100;
  FFilterTimer.Enabled  := False;
  FFilterTimer.OnTimer  := @FilterTimerFired;
  BuildUI;
  ApplyAppSettings;
  if ParamCount > 0 then
    LoadFile(ParamStr(1));
  // Wenn Follow beim Start aktiv: direkt ans Ende springen
  if FFollowTail and (FFilteredCount > 0) then
  begin
    lbLog.ScrollToEnd;
  end;
end;

destructor TfrmMain.Destroy;
begin
  FTail.Stop;
  AppSettings.WinLeft      := Left;
  AppSettings.WinTop       := Top;
  AppSettings.WinWidth     := Width;
  AppSettings.WinHeight    := Height;
  AppSettings.WinMaximized := WindowState = wsMaximized;
  SaveSettings;
  FTail.Free;
  FFilter.Free;
  FLog.Free;
  inherited Destroy;
end;

procedure TfrmMain.BuildUI;
var
  i : Integer;

  function AddMnu(AParent: TMenuItem; const ACaption: string;
    AEvent: TNotifyEvent; AShortcut: TShortCut = 0): TMenuItem;
  begin
    Result          := TMenuItem.Create(Self);
    Result.Caption  := ACaption;
    Result.OnClick  := AEvent;
    Result.ShortCut := AShortcut;
    AParent.Add(Result);
  end;

  function AddSep(AParent: TMenuItem): TMenuItem;
  begin
    Result         := TMenuItem.Create(Self);
    Result.Caption := '-';
    AParent.Add(Result);
  end;

  procedure MakeBtn(const ACaption: string; AEvent: TNotifyEvent;
    ALeft, AWidth: Integer);
  var B: TButton;
  begin
    B         := TButton.Create(Self);
    B.Parent  := pnlToolbar;
    B.Caption := ACaption;
    B.Left    := ALeft; B.Top := 3;
    B.Width   := AWidth; B.Height := 25;
    B.OnClick := AEvent;
  end;

begin
  Caption  := 'LogViewer';
  Width    := AppSettings.WinWidth;
  Height   := AppSettings.WinHeight;
  Left     := AppSettings.WinLeft;
  Top      := AppSettings.WinTop;
  if AppSettings.WinMaximized then WindowState := wsMaximized;
  ShowHint := True;
  OnClose  := @FormClose;
  OnResize := @FormResizeHandler;

  MainMenu1        := TMainMenu.Create(Self);
  MainMenu1.Parent := Self;

  mniDatei := TMenuItem.Create(MainMenu1); mniDatei.Caption := '&File';
  MainMenu1.Items.Add(mniDatei);
  AddMnu(mniDatei, '&Open...', @DoOeffnen, ShortCut(Ord('O'),[ssCtrl]));
  AddSep(mniDatei);
  AddMnu(mniDatei, '&Exit', @DoBeenden);

  mniBearbeiten := TMenuItem.Create(MainMenu1); mniBearbeiten.Caption := '&Edit';
  MainMenu1.Items.Add(mniBearbeiten);
  AddMnu(mniBearbeiten, 'Copy &Line',       @DoCopyLine, ShortCut(Ord('C'),[ssCtrl]));
  AddMnu(mniBearbeiten, 'Copy &All Visible', @DoCopyAll);

  mniAnsicht := TMenuItem.Create(MainMenu1); mniAnsicht.Caption := '&View';
  MainMenu1.Items.Add(mniAnsicht);
  mniLineNr   := AddMnu(mniAnsicht, '&Line Numbers', @DoLineNr);
  mniLineNr.Checked := AppSettings.ShowLineNumbers;
  mniWordWrap := AddMnu(mniAnsicht, '&Word Wrap',  @DoWordWrap);
  mniWordWrap.Checked := AppSettings.WordWrap;
  AddSep(mniAnsicht);
  AddMnu(mniAnsicht, '&Options...', @DoOptionen);

  mniSuchen := TMenuItem.Create(MainMenu1); mniSuchen.Caption := '&Search';
  MainMenu1.Items.Add(mniSuchen);
  AddMnu(mniSuchen, '&Find...',         @DoSucheDlg,    ShortCut(Ord('F'),[ssCtrl]));
  AddMnu(mniSuchen, 'Find &Next',       @DoSearchNext,  ShortCut(VK_F3,[]));
  AddMnu(mniSuchen, 'Find &Previous',   @DoSearchPrev,  ShortCut(VK_F3,[ssShift]));
  AddSep(mniSuchen);
  AddMnu(mniSuchen, 'Clear &Find',      @DoSucheReset,  ShortCut(Ord('F'),[ssCtrl,ssShift]));

  mniFilter := TMenuItem.Create(MainMenu1); mniFilter.Caption := 'F&ilter';
  MainMenu1.Items.Add(mniFilter);
  AddMnu(mniFilter, '&Filter...',      @DoFilterDlg,  ShortCut(Ord('L'),[ssCtrl]));
  AddMnu(mniFilter, 'Clear Fi&lter', @DoFilterReset);

  mniNavi := TMenuItem.Create(MainMenu1); mniNavi.Caption := '&Navigate';
  MainMenu1.Items.Add(mniNavi);
  mniNextErr := AddMnu(mniNavi, 'Next &Error',  @DoNextErr, ShortCut(VK_F5,[]));
  mniPrevErr := AddMnu(mniNavi, 'Prev E&rror', @DoPrevErr, ShortCut(VK_F5,[ssShift]));
  AddSep(mniNavi);
  AddMnu(mniNavi, 'Go to &Date/Time...', @DoGotoDate, ShortCut(Ord('D'),[ssCtrl]));
  AddMnu(mniNavi, 'Go to &Line...',  @DoGotoLine, ShortCut(Ord('G'),[ssCtrl]));

  mniTail := TMenuItem.Create(MainMenu1); mniTail.Caption := '&Tail';
  MainMenu1.Items.Add(mniTail);
  mniTailToggle := AddMnu(mniTail, 'Toggle &Tail', @DoTailToggle, ShortCut(VK_F6,[]));

  Menu := MainMenu1;

  pnlToolbar            := TPanel.Create(Self);
  pnlToolbar.Parent     := Self;
  pnlToolbar.Align      := alTop;
  pnlToolbar.Height     := 32;
  pnlToolbar.BevelOuter := bvNone;

  MakeBtn('Open',   @DoOeffnen,    2,  60);
  MakeBtn('Search', @DoSucheDlg,  66,  55);
  MakeBtn('<E',     @DoPrevErr,  125,  30);
  MakeBtn('E>',     @DoNextErr,  158,  30);
  MakeBtn('<W',     @DoPrevWarn, 192,  30);
  MakeBtn('W>',     @DoNextWarn, 225,  30);
  MakeBtn('<I',     @DoPrevInfo, 259,  30);
  MakeBtn('I>',     @DoNextInfo, 292,  30);

  // Tooltips auf den Buttons setzen (Controls sind direkte Kinder von pnlToolbar)
  with pnlToolbar do
  begin
    TButton(Controls[0]).Hint := 'Open log file  (Ctrl+O)';
    TButton(Controls[1]).Hint := 'Find text in log  (Ctrl+F)';
    TButton(Controls[2]).Hint := 'Previous ERROR  (Shift+F5)';
    TButton(Controls[3]).Hint := 'Next ERROR  (F5)';
    TButton(Controls[4]).Hint := 'Previous WARN';
    TButton(Controls[5]).Hint := 'Next WARN';
    TButton(Controls[6]).Hint := 'Previous INFO';
    TButton(Controls[7]).Hint := 'Next INFO';
    for i := 0 to 7 do
      TButton(Controls[i]).ShowHint := True;
  end;

  chkTailBtn            := TCheckBox.Create(Self);
  chkTailBtn.Parent     := pnlToolbar;
  chkTailBtn.Caption    := 'Tail';
  chkTailBtn.Left       := 330; chkTailBtn.Top := 6;
  chkTailBtn.Width      := 55;
  chkTailBtn.Checked    := AppSettings.TailEnabled;
  chkTailBtn.OnClick    := @DoTailToggle;
  chkTailBtn.Hint       := 'Watch file for new lines  (F6)';
  chkTailBtn.ShowHint   := True;

  chkFollowBtn          := TCheckBox.Create(Self);
  chkFollowBtn.Parent   := pnlToolbar;
  chkFollowBtn.Caption  := 'Follow';
  chkFollowBtn.Left     := 392; chkFollowBtn.Top := 6;
  chkFollowBtn.Width    := 65;
  chkFollowBtn.Checked  := True;
  chkFollowBtn.OnClick  := @DoFollowTailToggle;
  chkFollowBtn.Hint     := 'Auto-scroll to newest line during tail';
  chkFollowBtn.ShowHint := True;

  MakeBtn('Options', @DoOptionen, 465, 70);
  TButton(pnlToolbar.Controls[pnlToolbar.ControlCount - 1]).Hint     := 'Open settings dialog';
  TButton(pnlToolbar.Controls[pnlToolbar.ControlCount - 1]).ShowHint := True;

  lblQuickSearch          := TLabel.Create(Self);
  lblQuickSearch.Parent   := pnlToolbar;
  lblQuickSearch.Top      := 8;
  lblQuickSearch.Caption  := 'Filter:';
  lblQuickSearch.Anchors  := [akRight, akTop];

  edtQuickSearch          := TEdit.Create(Self);
  edtQuickSearch.Parent   := pnlToolbar;
  edtQuickSearch.Top      := 4;
  edtQuickSearch.Width    := 162;
  edtQuickSearch.Height   := 22;
  edtQuickSearch.Anchors  := [akRight, akTop];
  edtQuickSearch.OnChange := @DoQuickSearch;
  edtQuickSearch.Hint     := 'Filter visible lines by text  (Ctrl+L)';
  edtQuickSearch.ShowHint := True;

  btnClearSearch         := TSpeedButton.Create(Self);
  btnClearSearch.Parent  := pnlToolbar;
  btnClearSearch.Caption := 'x';
  btnClearSearch.Width   := 18;
  btnClearSearch.Height  := 18;
  btnClearSearch.Top     := 5;
  btnClearSearch.Flat    := True;
  btnClearSearch.Anchors := [akRight, akTop];
  btnClearSearch.OnClick := @DoClearSearch;
  btnClearSearch.Hint    := 'Clear filter  (Ctrl+Shift+F)';
  btnClearSearch.ShowHint := True;

  lbLog                  := TLogView.Create(Self);
  lbLog.Parent           := Self;
  lbLog.Align            := alClient;
  lbLog.Color            := AppSettings.BgDefault;
  lbLog.Font.Name        := AppSettings.FontName;
  lbLog.Font.Size        := AppSettings.FontSize;
  lbLog.OnDrawItem       := @lbLogDrawItem;
  lbLog.OnMeasureItem    := @lbLogMeasureItem;

  PopupMenu1        := TPopupMenu.Create(Self);
  mniPopCopy        := TMenuItem.Create(PopupMenu1);
  mniPopCopy.Caption:= 'Copy selected line(s)';
  mniPopCopy.OnClick:= @DoCopyLine;
  PopupMenu1.Items.Add(mniPopCopy);
  mniPopCopyAll         := TMenuItem.Create(PopupMenu1);
  mniPopCopyAll.Caption := 'Copy all visible';
  mniPopCopyAll.OnClick := @DoCopyAll;
  PopupMenu1.Items.Add(mniPopCopyAll);
  lbLog.PopupMenu := PopupMenu1;

  sbStatus             := TStatusBar.Create(Self);
  sbStatus.Parent      := Self;
  sbStatus.Align       := alBottom;
  sbStatus.SimplePanel := False;
  sbStatus.Hint        := 'Logfile and last Error/Warn/Info';
  sbStatus.ShowHint    := True;

  sbpMain          := sbStatus.Panels.Add;
  sbpMain.Width    := 600;
  sbpMain.Style    := psText;
  sbpMain.Text     := 'Ready';

  sbpEWI           := sbStatus.Panels.Add;
  sbpEWI.Width     := 310;
  sbpEWI.Style     := psOwnerDraw;
  sbStatus.OnDrawPanel := @sbStatusDrawPanel;
  sbStatus.OnResize    := @sbStatusResize;

  OpenDialog         := TOpenDialog.Create(Self);
  OpenDialog.Filter  := 'Log Files|*.log;*.txt;*.csv;*.json|JSON|*.json|All Files|*.*';
  OpenDialog.Options := OpenDialog.Options + [ofFileMustExist];

  PositionQuickSearch;
end;

{ Wendet die Theme-Farben auf alle UI-Elemente an }
procedure TfrmMain.ApplyThemeToUI;
var
  i : Integer;
begin
  // Formular-Hintergrund
  Color := AppSettings.BgToolbar;

  // Toolbar
  pnlToolbar.Color      := AppSettings.BgToolbar;
  pnlToolbar.Font.Color := AppSettings.FgDefault;

  // Checkboxen auf der Toolbar
  chkTailBtn.Font.Color   := AppSettings.FgDefault;
  chkFollowBtn.Font.Color := AppSettings.FgDefault;
  lblQuickSearch.Font.Color := AppSettings.FgDefault;

  // Quick-Search Edit
  edtQuickSearch.Color      := AppSettings.BgDefault;
  edtQuickSearch.Font.Color := AppSettings.FgDefault;

  // Toolbar-Buttons: dunkler als die Toolbar
  for i := 0 to pnlToolbar.ControlCount - 1 do
    if pnlToolbar.Controls[i] is TButton then
    begin
      TButton(pnlToolbar.Controls[i]).Color      := AppSettings.BgDefault;
      TButton(pnlToolbar.Controls[i]).Font.Color  := AppSettings.FgDefault;
    end;

  // ListBox
  lbLog.Color      := AppSettings.BgDefault;
  lbLog.Font.Color := AppSettings.FgDefault;

  // StatusBar
  sbStatus.Color      := AppSettings.BgStatus;
  sbStatus.Font.Color := AppSettings.FgStatus;
  sbStatus.Invalidate;
end;

procedure TfrmMain.ApplyAppSettings;
begin
  ApplyThemeColors;
  lbLog.Font.Name     := AppSettings.FontName;
  lbLog.Font.Size     := AppSettings.FontSize;
  mniLineNr.Checked   := AppSettings.ShowLineNumbers;
  mniWordWrap.Checked := AppSettings.WordWrap;
  FSepLineX    := -1;
  FCachedCharW := 0;
  ApplyThemeToUI;
  lbLog.UpdateFont;
  UpdateHorzScrollbar;
end;


function TfrmMain.GetFileSizeByName(const AFilename: string): Int64;
var SR: TSearchRec;
begin
  Result := 0;
  if (AFilename <> '') and (FindFirst(AFilename, faAnyFile, SR) = 0) then
  begin
    Result := SR.Size;
    FindClose(SR);
  end;
end;

procedure TfrmMain.ResetStats;
begin
  FECount := 0; FWCount := 0; FICount := 0;
  FLastETime := 0; FLastWTime := 0; FLastITime := 0;
end;

procedure TfrmMain.UpdateStatsForEntry(const AEntry: TLogEntry);
begin
  case AEntry.Level of
    lError: begin Inc(FECount); if AEntry.TimeStamp > FLastETime then FLastETime := AEntry.TimeStamp; end;
    lWarn : begin Inc(FWCount); if AEntry.TimeStamp > FLastWTime then FLastWTime := AEntry.TimeStamp; end;
    lInfo : begin Inc(FICount); if AEntry.TimeStamp > FLastITime then FLastITime := AEntry.TimeStamp; end;
  end;
end;

procedure TfrmMain.RecalcStatsFrom(const AStartIdx: Integer);
var
  i: Integer;
begin
  if AStartIdx <= 0 then ResetStats;
  for i := Max(0, AStartIdx) to FFilteredCount - 1 do
    UpdateStatsForEntry(FFiltered[i]);
end;

procedure TfrmMain.LoadFile(const AFilename: string);
const
  DETECT_LINES  = 50;
var
  FS         : TFileStream;
  RawBuf     : array[0..READ_BUF_SIZE - 1] of Byte;
  BytesRead  : Integer;
  P          : Integer;
  LineNo     : Integer;
  Line       : string;
  Carry      : AnsiString;   // Bytes der unvollst. letzten Zeile eines Blocks
  CarryLen   : Integer;
  Lines      : TStringArray;
  FileSize   : Int64;
  EstLines   : Integer;
  idx        : Integer;
  DetectDone : Boolean;
  LineStart  : Integer;
  LineEnd    : Integer;

  procedure EmitLine(ABuf: PAnsiChar; ALen: Integer); inline;
  var
    RawOff : Integer;
  begin
    if (ALen > 0) and (ABuf[ALen - 1] = #13) then Dec(ALen);
    Inc(LineNo);

    // Rohzeile einmalig in zentralen Puffer schreiben – kein String-Objekt
    RawOff := FLog.AppendRaw(ABuf, ALen);

    // Erste DETECT_LINES als String fuer Format-Erkennung (kurzlebig)
    if (not DetectDone) and (LineNo <= DETECT_LINES) then
    begin
      SetString(Line, ABuf, ALen);
      Lines[LineNo - 1] := Line;
    end;

    if (not DetectDone) and (LineNo = DETECT_LINES) then
    begin
      if AppSettings.AutoDetectFormat then
        FDetectedFmt := TLogParser.DetectFormat(Lines)
      else
        FDetectedFmt := AppSettings.ForceFormat;
      FCurrentFmt := FDetectedFmt;
      DetectDone  := True;
      SetLength(Lines, 0);
      Line := '';
    end;

    idx := FLog.PrepareAdd;
    // Fuer den Parser einen kurzlebigen String erzeugen (wird direkt freigegeben)
    if DetectDone and (Line = '') then
      SetString(Line, ABuf, ALen);
    TLogParser.ParseLine(Line, LineNo, FCurrentFmt, FLog.Slot(idx)^);
    // Offset und Laenge vom Puffer setzen (ParseLine setzt diese Felder nicht mehr)
    FLog.Slot(idx)^.RawOffset := RawOff;
    FLog.Slot(idx)^.RawLen    := ALen;
    FLog.CommitAdd;
    Line := '';
  end;

begin
  FTail.Stop;
  mniTailToggle.Checked := False;
  FFileName     := AFilename;
  FFileSize     := 0;
  FFiltered     := nil;
  FFilteredCount:= 0;
  FFilteredDirect := False;
  lbLog.Clear;
  FLog.Clear;
  FFilter.Reset;
  edtQuickSearch.Text := '';

  try
    FS := TFileStream.Create(AFilename, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    FileSize := FS.Size;
    EstLines := FileSize div 80 + 1024;
    FLog.EnsureCapacity(EstLines + EstLines div 10 + 256);
    FLog.ReserveRaw(FileSize);
    FFilter.LogList := FLog;

    SetLength(Lines, DETECT_LINES);
    LineNo     := 0;
    DetectDone := False;
    Carry      := '';
    CarryLen   := 0;
    RawBuf[0]  := 0;   // suppress uninitialized hint; FS.Read fills buffer before use
    // Format-Default falls Datei < 50 Zeilen
    if not AppSettings.AutoDetectFormat then
    begin
      FDetectedFmt := AppSettings.ForceFormat;
      FCurrentFmt  := FDetectedFmt;
      DetectDone   := True;
      SetLength(Lines, 0);
    end;

    repeat
      BytesRead := FS.Read(RawBuf[0], READ_BUF_SIZE);
      if BytesRead = 0 then Break;

      LineStart := 0;
      for P := 0 to BytesRead - 1 do
      begin
        if RawBuf[P] = 10 then  // LF gefunden
        begin
          LineEnd := P;         // exklusiv (ohne LF)
          if CarryLen > 0 then
          begin
            // Carry + neues Segment zusammenfuehren
            SetLength(Carry, CarryLen + (LineEnd - LineStart));
            if LineEnd > LineStart then
              Move(RawBuf[LineStart], Carry[CarryLen + 1], LineEnd - LineStart);
            EmitLine(PAnsiChar(Carry), CarryLen + (LineEnd - LineStart));
            Carry    := '';
            CarryLen := 0;
          end
          else
            EmitLine(@PAnsiChar(@RawBuf[0])[LineStart], LineEnd - LineStart);
          LineStart := P + 1;
        end;
      end;

      // Rest-Bytes ohne LF in Carry aufnehmen
      if LineStart < BytesRead then
      begin
        SetLength(Carry, CarryLen + (BytesRead - LineStart));
        Move(RawBuf[LineStart], Carry[CarryLen + 1], BytesRead - LineStart);
        CarryLen := CarryLen + (BytesRead - LineStart);
      end;
    until BytesRead < READ_BUF_SIZE;

    // Letzte Zeile ohne LF am Dateiende
    if CarryLen > 0 then
      EmitLine(PAnsiChar(Carry), CarryLen);

    // Format erkennen falls Datei weniger als 50 Zeilen hatte
    if not DetectDone then
    begin
      if AppSettings.AutoDetectFormat then
      begin
        SetLength(Lines, Min(LineNo, DETECT_LINES));
        FDetectedFmt := TLogParser.DetectFormat(Lines);
        SetLength(Lines, 0);
      end
      else
        FDetectedFmt := AppSettings.ForceFormat;
      FCurrentFmt := FDetectedFmt;
    end;

  finally
    FS.Free;
  end;

  FFileSize := GetFileSizeByName(AFilename);

  AppSettings.LastDir   := ExtractFileDir(AFilename);
  OpenDialog.InitialDir := AppSettings.LastDir;
  Caption := 'LogViewer – ' + ExtractFileName(AFilename)
           + '  [' + LogFormatNames[FCurrentFmt] + ']';

  ApplyFilterAndRefresh;
  UpdateStatus;
  ScrollToEndCurrent;

  if AppSettings.TailEnabled then
  begin
    FTail.Start(AFilename, FLog.Count, AppSettings.TailIntervalMs);
    mniTailToggle.Checked := True;
    chkTailBtn.Checked    := True;
  end
  else
  begin
    mniTailToggle.Checked := False;
    chkTailBtn.Checked    := False;
  end;
end;

procedure TfrmMain.UpdateStatus;
var
  sLines : string;
begin
  if FFilteredCount = FLog.Count then
    sLines := Format('Lines: %d', [FLog.Count])
  else
    sLines := Format('Lines: %d  |  Visible: %d', [FLog.Count, FFilteredCount]);

  sbpMain.Text := Format('%s  |  %s  |  %s Byte  |  Format: %s',
    [ExtractFileName(FFileName), sLines,
     FormatFloat('#,##0', FFileSize),
     LogFormatNames[FCurrentFmt]]);

  // Neuesten Timestamp der drei Zähler ermitteln
  FLastStatTime := 0;
  if FLastETime > FLastStatTime then FLastStatTime := FLastETime;
  if FLastWTime > FLastStatTime then FLastStatTime := FLastWTime;
  if FLastITime > FLastStatTime then FLastStatTime := FLastITime;

  sbStatus.Invalidate;   // triggers sbStatusDrawPanel
end;

procedure TfrmMain.sbStatusResize(Sender: TObject);
begin
  // sbpMain nimmt den ganzen Rest links, sbpEWI bleibt fix rechts
  if sbStatus.ClientWidth > sbpEWI.Width + 40 then
    sbpMain.Width := sbStatus.ClientWidth - sbpEWI.Width
  else
    sbpMain.Width := 40;
end;

procedure TfrmMain.sbStatusDrawPanel(StatusBar: TStatusBar;
  Panel: TStatusPanel; const Rect: TRect);
var
  Cvs        : TCanvas;
  sE, sW, sI : string;
  TotalW, X, Y : Integer;

  function PartWidth(const S: string; Bold: Boolean): Integer;
  begin
    if Bold then Cvs.Font.Style := [fsBold] else Cvs.Font.Style := [];
    Result := Cvs.TextWidth(S);
  end;

begin
  if Panel <> sbpEWI then Exit;
  Cvs := StatusBar.Canvas;
  Cvs.Brush.Color := StatusBar.Color;
  Cvs.FillRect(Rect);
  Cvs.Font.Assign(StatusBar.Font);

  if FLastETime > 0 then sE := Format('E: %d (%s)', [FECount, FormatDateTime('hh:nn:ss', FLastETime)])
  else                     sE := Format('E: %d (-)',  [FECount]);
  if FLastWTime > 0 then sW := Format('W: %d (%s)', [FWCount, FormatDateTime('hh:nn:ss', FLastWTime)])
  else                     sW := Format('W: %d (-)',  [FWCount]);
  if FLastITime > 0 then sI := Format('I: %d (%s)', [FICount, FormatDateTime('hh:nn:ss', FLastITime)])
  else                     sI := Format('I: %d (-)',  [FICount]);

  // Gesamtbreite messen für rechtsbündige Startposition
  TotalW :=
    PartWidth(sE, (FLastStatTime > 0) and (FLastETime = FLastStatTime)) +
    PartWidth('  ', False) +
    PartWidth(sW, (FLastStatTime > 0) and (FLastWTime = FLastStatTime)) +
    PartWidth('  ', False) +
    PartWidth(sI, (FLastStatTime > 0) and (FLastITime = FLastStatTime));

  X := Rect.Right - TotalW - 4;
  if X < Rect.Left + 2 then X := Rect.Left + 2;
  Y := Rect.Top + (Rect.Bottom - Rect.Top - Cvs.TextHeight('A')) div 2;

  if (FLastStatTime > 0) and (FLastETime = FLastStatTime) then
    Cvs.Font.Style := [fsBold] else Cvs.Font.Style := [];
  Cvs.TextOut(X, Y, sE); X := Cvs.PenPos.X;

  Cvs.Font.Style := [];
  Cvs.TextOut(X, Y, '  '); X := Cvs.PenPos.X;

  if (FLastStatTime > 0) and (FLastWTime = FLastStatTime) then
    Cvs.Font.Style := [fsBold] else Cvs.Font.Style := [];
  Cvs.TextOut(X, Y, sW); X := Cvs.PenPos.X;

  Cvs.Font.Style := [];
  Cvs.TextOut(X, Y, '  '); X := Cvs.PenPos.X;

  if (FLastStatTime > 0) and (FLastITime = FLastStatTime) then
    Cvs.Font.Style := [fsBold] else Cvs.Font.Style := [];
  Cvs.TextOut(X, Y, sI);
end;

procedure TfrmMain.ApplyFilterAndRefresh;
var
  i  : Integer;
begin
  FFiltered := FFilter.Apply(FLog, FFilteredCount);
  FFilteredDirect := not FFilter.IsActive;

  FECount := 0; FWCount := 0; FICount := 0;
  FLastETime := 0; FLastWTime := 0; FLastITime := 0;
  FMaxLineWidth := 0;

  for i := 0 to FFilteredCount - 1 do
  begin
    case FFiltered[i].Level of
      lError: begin
        Inc(FECount);
        if FFiltered[i].TimeStamp > FLastETime then FLastETime := FFiltered[i].TimeStamp;
      end;
      lWarn: begin
        Inc(FWCount);
        if FFiltered[i].TimeStamp > FLastWTime then FLastWTime := FFiltered[i].TimeStamp;
      end;
      lInfo: begin
        Inc(FICount);
        if FFiltered[i].TimeStamp > FLastITime then FLastITime := FFiltered[i].TimeStamp;
      end;
    end;
    // Maximale Zeilenbreite per Zeichenanzahl schätzen (kein GDI nötig)
    if FFiltered[i].RawLen > FMaxLineWidth then
      FMaxLineWidth := FFiltered[i].RawLen;
  end;

  // Zeichenanzahl → Pixel mit gecachter Breite (sonst 0 ausserhalb Paint)
  if FCachedCharW > 0 then
    FMaxLineWidth := FMaxLineWidth * FCachedCharW
  else
    FMaxLineWidth := FMaxLineWidth * lbLog.Canvas.TextWidth('0');
  if FMaxLineWidth <= 0 then FMaxLineWidth := 0;
  if AppSettings.ShowLineNumbers then
    Inc(FMaxLineWidth, FSepLineX + 4);

  // Eine einzige Win32-Nachricht statt 1M × LB_ADDSTRING
  lbLog.SetCount(FFilteredCount);

  // Nach dem Laden: letzte Zeile unten wenn Follow aktiv
  if FFollowTail and (FFilteredCount > 0) then
  begin
    lbLog.ScrollToEnd;
  end;

  UpdateHorzScrollbar;
  FFileSize := GetFileSizeByName(FFileName);
  UpdateStatus;
end;

// Farb-String-Regeln pruefen; Level-Farbe als Fallback
function TfrmMain.ColorForLine(AIndex: Integer): TColor;
var
  i   : Integer;
  Raw : string;
begin
  if AppSettings.ColorRuleCount > 0 then
  begin
    Raw := FLog.RawStr(FFiltered[AIndex].RawOffset, FFiltered[AIndex].RawLen);
    for i := 0 to AppSettings.ColorRuleCount - 1 do
      if AppSettings.ColorRules[i].Enabled
         and (AppSettings.ColorRules[i].Pattern <> '')
         and (Pos(LowerCase(AppSettings.ColorRules[i].Pattern), LowerCase(Raw)) > 0)
      then
      begin
        if AppSettings.ColorRules[i].UseLevel then
          Result := LevelColor(AppSettings.ColorRules[i].Level)
        else
          Result := AppSettings.ColorRules[i].Color;
        Exit;
      end;
  end;
  Result := LevelColor(FFiltered[AIndex].Level);
end;

function TfrmMain.FgColorForLine(AIndex: Integer): TColor;
var
  i   : Integer;
  Raw : string;
begin
  if AppSettings.ColorRuleCount > 0 then
  begin
    Raw := FLog.RawStr(FFiltered[AIndex].RawOffset, FFiltered[AIndex].RawLen);
    for i := 0 to AppSettings.ColorRuleCount - 1 do
      if AppSettings.ColorRules[i].Enabled
         and (AppSettings.ColorRules[i].Pattern <> '')
         and (Pos(LowerCase(AppSettings.ColorRules[i].Pattern), LowerCase(Raw)) > 0)
      then
      begin
        if AppSettings.ColorRules[i].UseLevel then
          Result := LevelFgColor(AppSettings.ColorRules[i].Level)
        else if AppSettings.ColorRules[i].FgColor = clDefault then
          Result := LevelFgColor(FFiltered[AIndex].Level)
        else
          Result := AppSettings.ColorRules[i].FgColor;
        Exit;
      end;
  end;
  Result := LevelFgColor(FFiltered[AIndex].Level);
end;

procedure TfrmMain.lbLogMeasureItem(Control: TWinControl; Index: Integer;
  var AHeight: Integer);
var
  Cvs      : TCanvas;
  R        : TRect;
  Flags    : Cardinal;
  Line     : string;
  WrapLeft : Integer;
begin
  if Control = nil then ;   // suppress "not used" hint
  Cvs := lbLog.Canvas;
  Cvs.Font.Assign(lbLog.Font);   // sicherstellen dass der richtige Font verwendet wird
  AHeight := Cvs.TextHeight('Agqjy') + 4;  // Ag + Unterlängen + Padding

  if AppSettings.WordWrap and (Index >= 0) and (Index < FFilteredCount) then
  begin
    Line := FormatLogLine(Index);
    WrapLeft := 0;
    if AppSettings.ShowLineNumbers then
    begin
      if FSepLineX < 0 then
        FSepLineX := 2
          + Cvs.TextWidth(StringOfChar('0', AppSettings.LineNumberWidth))
          + Cvs.TextWidth(' ');
      WrapLeft := FSepLineX + 2;
    end;
    // Nur den Text-Teil (nach der Zeilennummer) messen
    R     := Rect(WrapLeft, 0, lbLog.ClientWidth - 2, 32767);
    Flags := DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX;
    if AppSettings.ShowLineNumbers and (WrapLeft > 0) then
      DrawText(Cvs.Handle,
        PChar(Copy(Line, AppSettings.LineNumberWidth + 3, MaxInt)), -1, R, Flags)
    else
      DrawText(Cvs.Handle, PChar(Line), Length(Line), R, Flags);
    AHeight := Max(AHeight, R.Bottom - R.Top + 2);
  end;
end;

procedure TfrmMain.lbLogDrawItem(Control: TWinControl; Index: Integer;
  ARect: TRect; State: TOwnerDrawState);
var
  Cvs    : TCanvas;
  BgCol  : TColor;
  SepCol : TColor;
  BgRGB, FgRGB : TColor;
  TextR  : TRect;
  Flags  : Cardinal;
  Line   : string;
begin
  Cvs := lbLog.Canvas;
  if (Index < 0) or (Index > FFilteredCount - 1) then Exit;

  if (odSelected in State) or lbLog.Selected[Index] then
  begin
    Cvs.Brush.Color := clHighlight;
    Cvs.Font.Color  := clHighlightText;
  end
  else
  begin
    BgCol := ColorForLine(Index);
    Cvs.Brush.Color := BgCol;
    Cvs.Font.Color  := FgColorForLine(Index);
  end;
  Cvs.FillRect(ARect);

  // Zeichenbreite einmalig vom aktiven Canvas cachen
  if FCachedCharW <= 0 then
    FCachedCharW := Max(1, Cvs.TextWidth('0'));

  // Text zeichnen: mit oder ohne Word Wrap
  Line  := FormatLogLine(Index);
  TextR := ARect;
  Inc(TextR.Left, 2);
  Inc(TextR.Top,  1);
  if AppSettings.WordWrap then
  begin
    if AppSettings.ShowLineNumbers and (FSepLineX > 0) then
    begin
      // Zeilennummer ganz links zeichnen (Zeichen 1..LineNumberWidth+2)
      Cvs.Brush.Style := bsClear;
      Cvs.TextOut(TextR.Left, TextR.Top,
        Copy(Line, 1, AppSettings.LineNumberWidth + 2));
      // Logtext ab Zeichen LineNumberWidth+3, mit WordWrap
      TextR.Left  := ARect.Left + FSepLineX + 2;
      TextR.Right := ARect.Right - 2;
      DrawText(Cvs.Handle,
        PChar(Copy(Line, AppSettings.LineNumberWidth + 3, MaxInt)),
        -1, TextR,
        DT_WORDBREAK or DT_NOPREFIX);
      Cvs.Brush.Style := bsSolid;
    end
    else
    begin
      Flags := DT_WORDBREAK or DT_NOPREFIX;
      Cvs.Brush.Style := bsClear;
      DrawText(Cvs.Handle, PChar(Line), Length(Line), TextR, Flags);
      Cvs.Brush.Style := bsSolid;
    end;
  end
  else
    Cvs.TextOut(TextR.Left, TextR.Top, Line);

  // Vertikale Trennlinie zwischen Zeilennummer und Logtext
  if AppSettings.ShowLineNumbers then
  begin
    if FSepLineX < 0 then
      FSepLineX := 2
        + Cvs.TextWidth(StringOfChar('0', AppSettings.LineNumberWidth))
        + Cvs.TextWidth(' ');
    if (odSelected in State) or lbLog.Selected[Index] then
      SepCol := clHighlightText
    else
    begin
      BgRGB := ColorToRGB(AppSettings.BgDefault);
      FgRGB := ColorToRGB(AppSettings.FgDefault);
      SepCol :=
          (((BgRGB and $FF) * 7 + (FgRGB and $FF) * 3) div 10)
        or ((((BgRGB shr 8) and $FF) * 7 + ((FgRGB shr 8) and $FF) * 3) div 10) shl 8
        or ((((BgRGB shr 16) and $FF) * 7 + ((FgRGB shr 16) and $FF) * 3) div 10) shl 16;
    end;
    Cvs.Pen.Color := SepCol;
    Cvs.Pen.Style := psSolid;
    Cvs.Pen.Width := 1;
    Cvs.MoveTo(ARect.Left + FSepLineX, ARect.Top);
    Cvs.LineTo(ARect.Left + FSepLineX, ARect.Bottom);
  end;
end;

procedure TfrmMain.GotoLevel(AForward: Boolean; ALevel: TLogLevel);
var
  i, Start : Integer;
begin
  DisableFollowTemp;
  if FFilteredCount < 1 then Exit;
  if AForward then
  begin
    Start := lbLog.ItemIndex + 1;
    if Start < 0 then Start := 0;
    for i := Start to FFilteredCount - 1 do
      if FFiltered[i].Level = ALevel then
      begin
        lbLog.ItemIndex := i;
        lbLog.TopIndex  := Max(0, i - 5);
        lbLog.Invalidate;
        Exit;
      end;
    sbpMain.Text := 'No further entry found (forward).';
  end
  else
  begin
    Start := lbLog.ItemIndex - 1;
    if Start < 0 then Start := FFilteredCount - 1;
    for i := Start downto 0 do
      if FFiltered[i].Level = ALevel then
      begin
        lbLog.ItemIndex := i;
        lbLog.TopIndex  := Max(0, i - 5);
        lbLog.Invalidate;
        Exit;
      end;
    sbpMain.Text := 'No further entry found (backward).';
  end;
end;

procedure TfrmMain.GotoError(AForward: Boolean);
begin
  DisableFollowTemp;
  GotoLevel(AForward, lError);
end;

procedure TfrmMain.DoPrevWarn(Sender: TObject);  begin GotoLevel(False, lWarn);  end;
procedure TfrmMain.DoNextWarn(Sender: TObject);  begin GotoLevel(True,  lWarn);  end;
procedure TfrmMain.DoPrevInfo(Sender: TObject);  begin GotoLevel(False, lInfo);  end;
procedure TfrmMain.DoNextInfo(Sender: TObject);  begin GotoLevel(True,  lInfo);  end;

procedure TfrmMain.GotoLineNumber(ALine: Integer);
var i: Integer;
begin
  for i := 0 to FFilteredCount - 1 do
    if FFiltered[i].LineNo >= ALine then
    begin
      lbLog.ItemIndex := i; lbLog.TopIndex := i; Exit;
    end;
end;

procedure TfrmMain.ShowSearchDialog;
var
  Dlg : TForm;
  Lbl : TLabel;
  Edt : TEdit;
  BOK, BReset, BCancel: TButton;
begin
  Dlg := TForm.Create(Self);
  try
    Dlg.Caption := 'Find'; Dlg.Width := 340; Dlg.Height := 145;
    Dlg.Position := poScreenCenter; Dlg.BorderStyle := bsDialog;
    Lbl := TLabel.Create(Dlg); Lbl.Parent := Dlg;
    Lbl.Left := 10; Lbl.Top := 12; Lbl.Caption := 'Search term:';
    Edt := TEdit.Create(Dlg); Edt.Parent := Dlg;
    Edt.Left := 10; Edt.Top := 30; Edt.Width := 305; Edt.Text := FSearchText;
    BOK := TButton.Create(Dlg); BOK.Parent := Dlg;
    BOK.Left := 10; BOK.Top := 80; BOK.Width := 85;
    BOK.Caption := 'Find'; BOK.ModalResult := mrOk; BOK.Default := True;
    BReset := TButton.Create(Dlg); BReset.Parent := Dlg;
    BReset.Left := 115; BReset.Top := 80; BReset.Width := 85;
    BReset.Caption := 'Clear'; BReset.ModalResult := mrRetry;
    BCancel := TButton.Create(Dlg); BCancel.Parent := Dlg;
    BCancel.Left := 220; BCancel.Top := 80; BCancel.Width := 85;
    BCancel.Caption := 'Cancel'; BCancel.ModalResult := mrCancel; BCancel.Cancel := True;
    case Dlg.ShowModal of
      mrOk    : begin
                  FSearchText := Edt.Text;
                  if FSearchText <> '' then
                    SearchText(True);
                end;
      mrRetry : begin
                  FSearchText := '';
                  sbpMain.Text := 'Search cleared.';
                end;
    end;
  finally
    Dlg.Free;
  end;
end;

{ Sucht vorwaerts oder rueckwaerts in der sichtbaren Liste (FFiltered) }
procedure TfrmMain.SearchText(AForward: Boolean);
var
  i, Start, Total : Integer;
  Needle          : string;
begin
  if FSearchText = '' then
  begin
    sbpMain.Text := 'No search term set. Press Ctrl+F to enter one.';
    Exit;
  end;
  Total := FFilteredCount;
  if Total = 0 then Exit;

  DisableFollowTemp;
  Needle := LowerCase(FSearchText);

  if AForward then
  begin
    Start := lbLog.ItemIndex + 1;
    if (Start < 0) or (Start >= Total) then Start := 0;
    // ab Start bis Ende
    for i := Start to Total - 1 do
      if Pos(Needle, LowerCase(FLog.RawStr(FFiltered[i].RawOffset, FFiltered[i].RawLen))) > 0 then
      begin
        lbLog.ItemIndex := i;
        lbLog.TopIndex  := Max(0, i - 5);
        lbLog.Invalidate;
        sbpMain.Text := Format('Found: line %d', [FFiltered[i].LineNo]);
        Exit;
      end;
    // Wrap: von 0 bis Start-1
    for i := 0 to Start - 1 do
      if Pos(Needle, LowerCase(FLog.RawStr(FFiltered[i].RawOffset, FFiltered[i].RawLen))) > 0 then
      begin
        lbLog.ItemIndex := i;
        lbLog.TopIndex  := Max(0, i - 5);
        lbLog.Invalidate;
        sbpMain.Text := Format('Found (wrapped): line %d',
          [FFiltered[i].LineNo]);
        Exit;
      end;
  end
  else
  begin
    Start := lbLog.ItemIndex - 1;
    if Start < 0 then Start := Total - 1;
    // ab Start rueckwaerts bis 0
    for i := Start downto 0 do
      if Pos(Needle, LowerCase(FLog.RawStr(FFiltered[i].RawOffset, FFiltered[i].RawLen))) > 0 then
      begin
        lbLog.ItemIndex := i;
        lbLog.TopIndex  := Max(0, i - 5);
        lbLog.Invalidate;
        sbpMain.Text := Format('Found: line %d', [FFiltered[i].LineNo]);
        Exit;
      end;
    // Wrap: von Ende bis Start+1
    for i := Total - 1 downto Start + 1 do
      if Pos(Needle, LowerCase(FLog.RawStr(FFiltered[i].RawOffset, FFiltered[i].RawLen))) > 0 then
      begin
        lbLog.ItemIndex := i;
        lbLog.TopIndex  := Max(0, i - 5);
        lbLog.Invalidate;
        sbpMain.Text := Format('Found (wrapped): line %d',
          [FFiltered[i].LineNo]);
        Exit;
      end;
  end;
  sbpMain.Text := Format('"%s" not found.', [FSearchText]);
end;

procedure TfrmMain.ShowFilterDialog;
var
  Dlg : TForm;
  grp : TGroupBox;
  chkErr, chkWarn, chkInfo, chkDebug, chkTrace, chkCustom: TCheckBox;
  BOK, BCancel: TButton;
begin
  Dlg := TForm.Create(Self);
  try
    Dlg.Caption := 'Filter by Level'; Dlg.Width := 260; Dlg.Height := 290;
    Dlg.Position := poScreenCenter; Dlg.BorderStyle := bsDialog;
    grp := TGroupBox.Create(Dlg); grp.Parent := Dlg;
    grp.Left := 10; grp.Top := 10; grp.Width := 225; grp.Height := 195;
    grp.Caption := 'Visible Levels';

    chkErr := TCheckBox.Create(Dlg); chkErr.Parent := grp;
    chkErr.Left := 10; chkErr.Top := 20; chkErr.Caption := 'ERROR';
    chkErr.Checked := lError in FFilter.Levels;

    chkWarn := TCheckBox.Create(Dlg); chkWarn.Parent := grp;
    chkWarn.Left := 10; chkWarn.Top := 48; chkWarn.Caption := 'WARN';
    chkWarn.Checked := lWarn in FFilter.Levels;

    chkInfo := TCheckBox.Create(Dlg); chkInfo.Parent := grp;
    chkInfo.Left := 10; chkInfo.Top := 76; chkInfo.Caption := 'INFO';
    chkInfo.Checked := lInfo in FFilter.Levels;

    chkDebug := TCheckBox.Create(Dlg); chkDebug.Parent := grp;
    chkDebug.Left := 10; chkDebug.Top := 104; chkDebug.Caption := 'DEBUG';
    chkDebug.Checked := lDebug in FFilter.Levels;

    chkTrace := TCheckBox.Create(Dlg); chkTrace.Parent := grp;
    chkTrace.Left := 10; chkTrace.Top := 132; chkTrace.Caption := 'TRACE';
    chkTrace.Checked := lTrace in FFilter.Levels;

    chkCustom := TCheckBox.Create(Dlg); chkCustom.Parent := grp;
    chkCustom.Left := 10; chkCustom.Top := 160; chkCustom.Caption := 'Other';
    chkCustom.Checked := lCustom in FFilter.Levels;

    BOK := TButton.Create(Dlg); BOK.Parent := Dlg;
    BOK.Left := 20; BOK.Top := 220; BOK.Width := 90;
    BOK.Caption := 'OK'; BOK.ModalResult := mrOk; BOK.Default := True;
    BCancel := TButton.Create(Dlg); BCancel.Parent := Dlg;
    BCancel.Left := 130; BCancel.Top := 220; BCancel.Width := 90;
    BCancel.Caption := 'Cancel'; BCancel.ModalResult := mrCancel; BCancel.Cancel := True;

    if Dlg.ShowModal = mrOk then
    begin
      FFilter.Levels := [];
      if chkErr.Checked    then FFilter.Levels := FFilter.Levels + [lError];
      if chkWarn.Checked   then FFilter.Levels := FFilter.Levels + [lWarn];
      if chkInfo.Checked   then FFilter.Levels := FFilter.Levels + [lInfo];
      if chkDebug.Checked  then FFilter.Levels := FFilter.Levels + [lDebug];
      if chkTrace.Checked  then FFilter.Levels := FFilter.Levels + [lTrace];
      if chkCustom.Checked then FFilter.Levels := FFilter.Levels + [lCustom];
      ApplyFilterAndRefresh;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.ShowGotoDateDialog;
var
  Dlg               : TForm;
  dtpDate, dtpTime  : TDateTimePicker;
  lbl1, lbl2, lbl3  : TLabel;
  BOK, BCancel      : TButton;
  Target            : TDateTime;
  i                 : Integer;
begin
  Dlg := TForm.Create(Self);
  try
    Dlg.Caption := 'Go to Date/Time'; Dlg.Width := 320; Dlg.Height := 190;
    Dlg.Position := poScreenCenter; Dlg.BorderStyle := bsDialog;

    lbl1 := TLabel.Create(Dlg); lbl1.Parent := Dlg;
    lbl1.Left := 10; lbl1.Top := 14; lbl1.Caption := 'Date:';
    dtpDate := TDateTimePicker.Create(Dlg); dtpDate.Parent := Dlg;
    dtpDate.Left := 90; dtpDate.Top := 10; dtpDate.Width := 140;
    dtpDate.Kind := dtkDate; dtpDate.Date := Date;

    lbl2 := TLabel.Create(Dlg); lbl2.Parent := Dlg;
    lbl2.Left := 10; lbl2.Top := 48; lbl2.Caption := 'Time:';
    dtpTime := TDateTimePicker.Create(Dlg); dtpTime.Parent := Dlg;
    dtpTime.Left := 90; dtpTime.Top := 44; dtpTime.Width := 140;
    dtpTime.Kind := dtkTime; dtpTime.Time := 0;

    lbl3 := TLabel.Create(Dlg); lbl3.Parent := Dlg;
    lbl3.Left := 10; lbl3.Top := 80; lbl3.Width := 295;
    lbl3.WordWrap := True;
    lbl3.Caption := 'Jumps to the first log entry whose timestamp is equal' +
      LineEnding + 'to or later than the specified date/time.';

    BOK := TButton.Create(Dlg); BOK.Parent := Dlg;
    BOK.Left := 60; BOK.Top := 125; BOK.Width := 85;
    BOK.Caption := 'Go to'; BOK.ModalResult := mrOk; BOK.Default := True;
    BCancel := TButton.Create(Dlg); BCancel.Parent := Dlg;
    BCancel.Left := 170; BCancel.Top := 125; BCancel.Width := 85;
    BCancel.Caption := 'Cancel'; BCancel.ModalResult := mrCancel; BCancel.Cancel := True;

    if Dlg.ShowModal = mrOk then
    begin
      Target := dtpDate.Date + dtpTime.Time;
      for i := 0 to FFilteredCount - 1 do
        if (FFiltered[i].TimeStamp > 0) and (FFiltered[i].TimeStamp >= Target) then
        begin
          lbLog.ItemIndex := i; lbLog.TopIndex := i;
          Break;
        end;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.ShowGotoLineDialog;
var
  Dlg  : TForm;
  Lbl  : TLabel;
  Spn  : TSpinEdit;
  BOK, BCancel: TButton;
begin
  Dlg := TForm.Create(Self);
  try
    Dlg.Caption := 'Go to Line'; Dlg.Width := 250; Dlg.Height := 120;
    Dlg.Position := poScreenCenter; Dlg.BorderStyle := bsDialog;
    Lbl := TLabel.Create(Dlg); Lbl.Parent := Dlg;
    Lbl.Left := 10; Lbl.Top := 14; Lbl.Caption := 'Line number:';
    Spn := TSpinEdit.Create(Dlg); Spn.Parent := Dlg;
    Spn.Left := 115; Spn.Top := 10; Spn.Width := 90;
    Spn.MinValue := 1; Spn.MaxValue := Max(1, FLog.Count); Spn.Value := 1;
    BOK := TButton.Create(Dlg); BOK.Parent := Dlg;
    BOK.Left := 20; BOK.Top := 60; BOK.Width := 85;
    BOK.Caption := 'OK'; BOK.ModalResult := mrOk; BOK.Default := True;
    BCancel := TButton.Create(Dlg); BCancel.Parent := Dlg;
    BCancel.Left := 135; BCancel.Top := 60; BCancel.Width := 85;
    BCancel.Caption := 'Cancel'; BCancel.ModalResult := mrCancel; BCancel.Cancel := True;
    if Dlg.ShowModal = mrOk then GotoLineNumber(Spn.Value);
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.CopySelectedLine;
var
  SL : TStringList;
  i  : Integer;
begin
  SL := TStringList.Create;
  try
    for i := 0 to FFilteredCount - 1 do
      if lbLog.Selected[i] then
        SL.Add(FLog.RawStr(FFiltered[i].RawOffset, FFiltered[i].RawLen));
    if (SL.Count = 0) and (lbLog.ItemIndex >= 0)
       and (lbLog.ItemIndex <= FFilteredCount - 1) then
      SL.Add(FLog.RawStr(FFiltered[lbLog.ItemIndex].RawOffset, FFiltered[lbLog.ItemIndex].RawLen));
    if SL.Count > 0 then
      Clipboard.AsText := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TfrmMain.CopyAllVisible;
var
  SL : TStringList; i: Integer;
begin
  SL := TStringList.Create;
  try
    for i := 0 to FFilteredCount - 1 do
      SL.Add(FLog.RawStr(FFiltered[i].RawOffset, FFiltered[i].RawLen));
    Clipboard.AsText := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TfrmMain.OnTailNewLine(const ALine: string; ALineNo: Integer);
var
  idx     : Integer;
  P       : PLogEntry;
  RawOff  : Integer;
  Matched : Boolean;
begin
  // Rohzeile in Puffer schreiben
  RawOff := FLog.AppendRaw(PAnsiChar(AnsiString(ALine)), Length(ALine));
  idx := FLog.PrepareAdd;
  TLogParser.ParseLine(ALine, ALineNo, FCurrentFmt, FLog.Slot(idx)^);
  FLog.Slot(idx)^.RawOffset := RawOff;
  FLog.Slot(idx)^.RawLen    := Length(ALine);
  FLog.CommitAdd;
  P := FLog.Slot(idx);

  if FFilteredDirect then
  begin
    FFiltered := FLog.RawItems;
    FFilteredCount := FLog.Count;
    UpdateStatsForEntry(P^);
    lbLog.AppendItem;
    if FFollowTail then
    begin
      lbLog.ScrollToEnd;
    end;
  end
  else
  begin
    Matched := FFilter.Matches(P^);
    if Matched then
    begin
      Inc(FFilteredCount);
      SetLength(FFiltered, FFilteredCount);
      FFiltered[FFilteredCount - 1] := P^;
      UpdateStatsForEntry(P^);
      lbLog.AppendItem;
      if FFollowTail then
        lbLog.ScrollToEnd;
    end;
  end;
  FFileSize := GetFileSizeByName(FFileName);
  UpdateStatus;
end;

procedure TfrmMain.DoOeffnen(Sender: TObject);
begin
  if AppSettings.LastDir <> '' then
    OpenDialog.InitialDir := AppSettings.LastDir;
  if OpenDialog.Execute then
    LoadFile(OpenDialog.FileName);
end;

procedure TfrmMain.DoBeenden(Sender: TObject);     begin Close;              end;
procedure TfrmMain.DoSucheDlg(Sender: TObject);    begin ShowSearchDialog;   end;
procedure TfrmMain.DoSearchNext(Sender: TObject);  begin SearchText(True);   end;
procedure TfrmMain.DoSearchPrev(Sender: TObject);  begin SearchText(False);  end;
procedure TfrmMain.DoFilterDlg(Sender: TObject);   begin ShowFilterDialog;   end;
procedure TfrmMain.DoNextErr(Sender: TObject);      begin GotoError(True);    end;
procedure TfrmMain.DoPrevErr(Sender: TObject);      begin GotoError(False);   end;
procedure TfrmMain.DoGotoDate(Sender: TObject);     begin ShowGotoDateDialog; end;
procedure TfrmMain.DoGotoLine(Sender: TObject);     begin ShowGotoLineDialog; end;
procedure TfrmMain.DoCopyLine(Sender: TObject);     begin CopySelectedLine;   end;
procedure TfrmMain.DoCopyAll(Sender: TObject);      begin CopyAllVisible;     end;

procedure TfrmMain.DoLineNr(Sender: TObject);
begin
  AppSettings.ShowLineNumbers := not AppSettings.ShowLineNumbers;
  mniLineNr.Checked := AppSettings.ShowLineNumbers;
  FSepLineX := -1;
  ApplyFilterAndRefresh;
end;

procedure TfrmMain.DoWordWrap(Sender: TObject);
begin
  AppSettings.WordWrap := not AppSettings.WordWrap;
  mniWordWrap.Checked  := AppSettings.WordWrap;
  UpdateHorzScrollbar;
  lbLog.Invalidate;
end;

procedure TfrmMain.DoOptionen(Sender: TObject);
begin
  if TfrmOptions.ExecuteWithDetected(Self, FDetectedFmt) then
  begin
    ApplyAppSettings;
    if FFileName <> '' then LoadFile(FFileName);
  end;
end;

procedure TfrmMain.DoSucheReset(Sender: TObject);
begin
  FSearchText := '';
  sbpMain.Text := 'Search cleared.';
end;

procedure TfrmMain.DoFilterReset(Sender: TObject);
begin
  FFilter.Reset; edtQuickSearch.Text := ''; ApplyFilterAndRefresh;
end;

procedure TfrmMain.DoTailToggle(Sender: TObject);
begin
  if FTail.Active then
  begin
    FTail.Stop;
    mniTailToggle.Checked  := False;
    chkTailBtn.Checked     := False;
    AppSettings.TailEnabled := False;
  end
  else if FFileName <> '' then
  begin
    FTail.Start(FFileName, FLog.Count, AppSettings.TailIntervalMs);
    mniTailToggle.Checked   := True;
    chkTailBtn.Checked      := True;
    AppSettings.TailEnabled := True;
  end
  else
    chkTailBtn.Checked := False;
end;

procedure TfrmMain.DoFollowTailToggle(Sender: TObject);
begin
  FFollowTail := chkFollowBtn.Checked;
  ScrollToEndCurrent;
end;

procedure TfrmMain.DoQuickSearch(Sender: TObject);
begin
  // Debounce: Timer neu starten, Filter erst nach 100ms Pause anwenden
  FFilterTimer.Enabled := False;
  FFilterTimer.Enabled := True;
end;

procedure TfrmMain.FilterTimerFired(Sender: TObject);
begin
  FFilterTimer.Enabled := False;
  DisableFollowTemp;
  FFilter.Text := edtQuickSearch.Text;
  ApplyFilterAndRefresh;
end;

procedure TfrmMain.DoClearSearch(Sender: TObject);
begin
  DisableFollowTemp;
  edtQuickSearch.Text := '';
  edtQuickSearch.SetFocus;
end;

procedure TfrmMain.PositionQuickSearch;
var
  W : Integer;
begin
  W := pnlToolbar.ClientWidth;
  btnClearSearch.Left  := W - btnClearSearch.Width - 4;
  btnClearSearch.Top   := edtQuickSearch.Top + (edtQuickSearch.Height - btnClearSearch.Height) div 2;
  edtQuickSearch.Left  := btnClearSearch.Left - edtQuickSearch.Width - 2;
  lblQuickSearch.Left  := edtQuickSearch.Left - lblQuickSearch.Width - 6;
end;

procedure TfrmMain.UpdateHorzScrollbar;
begin
  if AppSettings.WordWrap or not AppSettings.ShowHorzScrollbar then
    lbLog.ScrollWidth := 0
  else
    lbLog.ScrollWidth := FMaxLineWidth + 8;
end;

procedure TfrmMain.FormResizeHandler(Sender: TObject);
begin
  PositionQuickSearch;
  UpdateHorzScrollbar;
  if AppSettings.WordWrap then
  begin
    FResizeTimer.Enabled := False;
    FResizeTimer.Enabled := True;
  end;
end;

procedure TfrmMain.ResizeTimerFired(Sender: TObject);
begin
  FResizeTimer.Enabled := False;
  lbLog.Invalidate;   // TLogView remeasures visible lines on next Paint
end;

procedure TfrmMain.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
end;

end.
