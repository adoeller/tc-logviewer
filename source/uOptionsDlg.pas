unit uOptionsDlg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, Spin, ColorBox, ComCtrls,
  uSettings, uLogTypes
  {$IFDEF WINDOWS}, Windows{$ENDIF};

{$IFDEF WINDOWS}
function SetWindowTheme(hwnd: HWND; pszSubAppName: PWideChar;
  pszSubIdList: PWideChar): HRESULT; stdcall;
  external 'uxtheme.dll' name 'SetWindowTheme';
{$ENDIF}

type
  TfrmOptions = class(TForm)
  private
    PageCtrl       : TPageControl;
    pnlBottom      : TPanel;
    // Tab 1: Ansicht
    tabAnsicht     : TTabSheet;
    pnlView        : TPanel;       // alClient-Panel im Tab
    chkLineNumbers : TCheckBox;
    spnLineWidth   : TSpinEdit;
    lblLineWidth   : TLabel;
    chkWordWrap    : TCheckBox;
    cmbFontName    : TComboBox;
    btnPickFont    : TButton;
    lblFontPreview : TLabel;
    spnFontSize    : TSpinEdit;
    rgThemeMode    : TRadioGroup;
    // Tab 2: Farben
    tabFarben      : TTabSheet;
    pnlColors      : TPanel;
    rgColorTheme   : TRadioGroup;
    cbError        : TColorBox;
    cbWarn         : TColorBox;
    cbInfo         : TColorBox;
    cbDebug        : TColorBox;
    cbTrace        : TColorBox;
    cbCustom       : TColorBox;
    cbFgError      : TColorBox;
    cbFgWarn       : TColorBox;
    cbFgInfo       : TColorBox;
    cbFgDebug      : TColorBox;
    cbFgTrace      : TColorBox;
    cbFgCustom     : TColorBox;
    // Tab 3: Farb-Strings
    tabFarbStrings : TTabSheet;
    pnlRules       : TPanel;
    lbRules        : TListBox;
    edtPattern     : TEdit;
    cbRuleColor    : TColorBox;
    cbRuleFgColor  : TColorBox;
    chkRuleEnabled : TCheckBox;
    chkUseLevel    : TCheckBox;
    cmbRuleLevel   : TComboBox;
    btnRuleAdd     : TButton;
    btnRuleUpdate  : TButton;
    btnRuleDelete  : TButton;
    // Tab 4: Format
    tabFormat      : TTabSheet;
    pnlFormat      : TPanel;
    chkAutoDetect  : TCheckBox;
    cmbForceFormat : TComboBox;
    lblDetected    : TLabel;
    // Custom Format controls
    grpCustom      : TGroupBox;
    rgCfMode       : TRadioGroup;
    // Delimiter mode
    lblCfDelim     : TLabel;
    edtCfDelim     : TEdit;
    lblCfFields    : TLabel;
    cmbCfRoles     : array[0..MAX_CUSTOM_FIELDS-1] of TComboBox;
    lblCfFieldNo   : array[0..MAX_CUSTOM_FIELDS-1] of TLabel;
    // Position mode
    lblCfTS        : TLabel;
    spnCfTSStart   : TSpinEdit;
    lblCfTSLen     : TLabel;
    spnCfTSLen     : TSpinEdit;
    lblCfLvl       : TLabel;
    spnCfLvlStart  : TSpinEdit;
    lblCfLvlLen    : TLabel;
    spnCfLvlLen    : TSpinEdit;
    lblCfSrc       : TLabel;
    spnCfSrcStart  : TSpinEdit;
    lblCfSrcLen    : TLabel;
    spnCfSrcLen    : TSpinEdit;
    // Common
    lblCfTSFmt     : TLabel;
    edtCfTSFmt     : TEdit;
    // Tab 5: Tail
    tabTail        : TTabSheet;
    pnlTail        : TPanel;
    chkTail        : TCheckBox;
    spnTailMs      : TSpinEdit;
    // Buttons
    btnOK          : TButton;
    btnCancel      : TButton;

    FEditLight     : TThemeColors;
    FEditDark      : TThemeColors;

    procedure BuildUI;
    procedure LoadFromSettings;
    procedure SaveToSettings;
    procedure ApplyDarkModeToDialog;
    procedure ThemeControl(AControl: TControl; ABg, AFg, ABgEdit: TColor);
    procedure RefreshRuleList;
    procedure lbRulesClick(Sender: TObject);
    procedure BtnRuleAddClick(Sender: TObject);
    procedure BtnRuleUpdateClick(Sender: TObject);
    procedure BtnRuleDeleteClick(Sender: TObject);
    procedure chkAutoDetectChange(Sender: TObject);
    procedure DoFormatChange(Sender: TObject);
    procedure DoCfModeChange(Sender: TObject);
    procedure UpdateCustomVisible;
    procedure DoFontChanged(Sender: TObject);
    procedure DoBtnPickFont(Sender: TObject);
    procedure DoColorThemeSwitch(Sender: TObject);
    procedure SaveColorBoxesToSet(var C: TThemeColors);
    procedure LoadColorBoxesFromSet(const C: TThemeColors);
  public
    constructor Create(AOwner: TComponent); override;
    class function Execute(AOwner: TComponent): Boolean;
    class function ExecuteWithDetected(AOwner: TComponent;
      ADetected: TLogFormat): Boolean;
  end;

implementation

{ Erzeugt ein rahmenloses Panel das die gesamte Tab-Flaeche ausfuellt }
function MakeTabPanel(AOwner: TComponent; ATab: TTabSheet): TPanel;
begin
  Result            := TPanel.Create(AOwner);
  Result.Parent     := ATab;
  Result.Align      := alClient;
  Result.BevelOuter := bvNone;
  Result.ParentColor := False;   // eigene Farbe behalten
  Result.Color      := ATab.Color;
end;

constructor TfrmOptions.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildUI;
  LoadFromSettings;
  ApplyDarkModeToDialog;
end;

procedure TfrmOptions.BuildUI;
var
  y      : Integer;
  i      : Integer;
  FmtIdx : TLogFormat;

  function L(AParent: TWinControl; const AText: string;
    AX, AY: Integer): TLabel;
  begin
    Result         := TLabel.Create(Self);
    Result.Parent  := AParent;
    Result.Left    := AX; Result.Top := AY;
    Result.Caption := AText;
  end;

  function CB(AParent: TWinControl; AX, AY: Integer): TColorBox;
  begin
    Result        := TColorBox.Create(Self);
    Result.Parent := AParent;
    Result.Left   := AX; Result.Top := AY;
    Result.Width  := 150; Result.Height := 22;
    Result.Style  := Result.Style + [cbCustomColor];
  end;

begin
  Caption     := 'Settings – LogViewer';
  Width       := 495;
  Height      := 465;
  Position    := poScreenCenter;
  BorderStyle := bsSizeable;

  // -- Unterer Bereich: OK / Cancel ------------------------------------
  pnlBottom            := TPanel.Create(Self);
  pnlBottom.Parent     := Self;
  pnlBottom.Align      := alBottom;
  pnlBottom.Height     := 38;
  pnlBottom.BevelOuter := bvNone;

  btnOK             := TButton.Create(Self);
  btnOK.Parent      := pnlBottom;
  btnOK.Width       := 85;  btnOK.Height := 28;
  btnOK.Top         := 5;
  btnOK.Left        := pnlBottom.Width - 2 * 85 - 16;
  btnOK.Caption     := 'OK';
  btnOK.ModalResult := mrOk; btnOK.Default := True;
  btnOK.Anchors     := [akRight, akBottom];

  btnCancel             := TButton.Create(Self);
  btnCancel.Parent      := pnlBottom;
  btnCancel.Width       := 85; btnCancel.Height := 28;
  btnCancel.Top         := 5;
  btnCancel.Left        := pnlBottom.Width - 85 - 8;
  btnCancel.Caption     := 'Cancel';
  btnCancel.ModalResult := mrCancel; btnCancel.Cancel := True;
  btnCancel.Anchors     := [akRight, akBottom];

  // -- PageControl fuellt den Rest -------------------------------------
  PageCtrl         := TPageControl.Create(Self);
  PageCtrl.Parent  := Self;
  PageCtrl.Align   := alClient;

  // == Tab 1: Ansicht ===================================================
  tabAnsicht             := TTabSheet.Create(PageCtrl);
  tabAnsicht.Parent      := PageCtrl;
  tabAnsicht.PageControl := PageCtrl;
  tabAnsicht.Caption     := 'View';
  pnlView := MakeTabPanel(Self, tabAnsicht);
  y := 12;

  chkLineNumbers         := TCheckBox.Create(Self);
  chkLineNumbers.Parent  := pnlView;
  chkLineNumbers.Left    := 10; chkLineNumbers.Top := y;
  chkLineNumbers.Caption := 'Show Line Numbers';
  chkLineNumbers.Width   := 200;

  lblLineWidth          := TLabel.Create(Self);
  lblLineWidth.Parent   := pnlView;
  lblLineWidth.Caption  := 'Digits:';
  lblLineWidth.Left     := 220; lblLineWidth.Top := y + 3;

  spnLineWidth          := TSpinEdit.Create(Self);
  spnLineWidth.Parent   := pnlView;
  spnLineWidth.Left     := 268; spnLineWidth.Top := y;
  spnLineWidth.Width    := 50;  spnLineWidth.Height := 22;
  spnLineWidth.MinValue := 1;   spnLineWidth.MaxValue := 9;
  Inc(y, 28);

  chkWordWrap         := TCheckBox.Create(Self);
  chkWordWrap.Parent  := pnlView;
  chkWordWrap.Left    := 10; chkWordWrap.Top := y;
  chkWordWrap.Caption := 'Word Wrap (saved, no effect on ListBox currently)';
  chkWordWrap.Width   := 380;
  Inc(y, 36);

  L(pnlView, 'Font:', 10, y + 3);
  cmbFontName          := TComboBox.Create(Self);
  cmbFontName.Parent   := pnlView;
  cmbFontName.Left     := 130; cmbFontName.Top := y;
  cmbFontName.Width    := 200; cmbFontName.Style := csDropDown;
  cmbFontName.Items.Assign(Screen.Fonts);
  cmbFontName.OnChange := @DoFontChanged;
  btnPickFont          := TButton.Create(Self);
  btnPickFont.Parent   := pnlView;
  btnPickFont.Left     := 338; btnPickFont.Top := y;
  btnPickFont.Width    := 28; btnPickFont.Height := 22;
  btnPickFont.Caption  := '...';
  btnPickFont.OnClick  := @DoBtnPickFont;
  Inc(y, 30);

  L(pnlView, 'Font Size:', 10, y + 3);
  spnFontSize          := TSpinEdit.Create(Self);
  spnFontSize.Parent   := pnlView;
  spnFontSize.Left     := 130; spnFontSize.Top := y;
  spnFontSize.Width    := 70;
  spnFontSize.MinValue := 6; spnFontSize.MaxValue := 32;
  spnFontSize.OnChange := @DoFontChanged;
  Inc(y, 36);

  lblFontPreview          := TLabel.Create(Self);
  lblFontPreview.Parent   := pnlView;
  lblFontPreview.Left     := 10; lblFontPreview.Top := y;
  lblFontPreview.Width    := 440; lblFontPreview.Height := 30;
  lblFontPreview.Caption  := 'AaBbCcDdEe 1234 #@!  The quick brown fox';
  lblFontPreview.AutoSize := False;
  lblFontPreview.WordWrap := True;
  Inc(y, 36);

  rgThemeMode           := TRadioGroup.Create(Self);
  rgThemeMode.Parent    := pnlView;
  rgThemeMode.Left      := 10; rgThemeMode.Top := y;
  rgThemeMode.Width     := 440; rgThemeMode.Height := 80;
  rgThemeMode.Caption   := 'Appearance';
  rgThemeMode.Items.Add('Follow system setting');
  rgThemeMode.Items.Add('Always light');
  rgThemeMode.Items.Add('Always dark');
  rgThemeMode.ItemIndex := 0;

  // == Tab 2: Farben ====================================================
  tabFarben             := TTabSheet.Create(PageCtrl);
  tabFarben.Parent      := PageCtrl;
  tabFarben.PageControl := PageCtrl;
  tabFarben.Caption     := 'Colors';
  pnlColors := MakeTabPanel(Self, tabFarben);

  rgColorTheme           := TRadioGroup.Create(Self);
  rgColorTheme.Parent    := pnlColors;
  rgColorTheme.Left      := 10; rgColorTheme.Top := 4;
  rgColorTheme.Width     := 440; rgColorTheme.Height := 42;
  rgColorTheme.Caption   := 'Edit colors for';
  rgColorTheme.Columns   := 2;
  rgColorTheme.Items.Add('Light theme');
  rgColorTheme.Items.Add('Dark theme');
  rgColorTheme.ItemIndex := 0;
  rgColorTheme.OnClick   := @DoColorThemeSwitch;

  y := 52;
  L(pnlColors, 'Level',      10, y);
  L(pnlColors, 'Background', 130, y);
  L(pnlColors, 'Foreground', 305, y);
  Inc(y, 22);
  L(pnlColors, 'ERROR:', 10, y + 2);
  cbError    := CB(pnlColors, 130, y);
  cbFgError  := CB(pnlColors, 305, y);
  Inc(y, 28);
  L(pnlColors, 'WARN:', 10, y + 2);
  cbWarn     := CB(pnlColors, 130, y);
  cbFgWarn   := CB(pnlColors, 305, y);
  Inc(y, 28);
  L(pnlColors, 'INFO:', 10, y + 2);
  cbInfo     := CB(pnlColors, 130, y);
  cbFgInfo   := CB(pnlColors, 305, y);
  Inc(y, 28);
  L(pnlColors, 'DEBUG:', 10, y + 2);
  cbDebug    := CB(pnlColors, 130, y);
  cbFgDebug  := CB(pnlColors, 305, y);
  Inc(y, 28);
  L(pnlColors, 'TRACE:', 10, y + 2);
  cbTrace    := CB(pnlColors, 130, y);
  cbFgTrace  := CB(pnlColors, 305, y);
  Inc(y, 28);
  L(pnlColors, 'Other:', 10, y + 2);
  cbCustom   := CB(pnlColors, 130, y);
  cbFgCustom := CB(pnlColors, 305, y);

  // == Tab 3: Farb-Strings ==============================================
  tabFarbStrings             := TTabSheet.Create(PageCtrl);
  tabFarbStrings.Parent      := PageCtrl;
  tabFarbStrings.PageControl := PageCtrl;
  tabFarbStrings.Caption     := 'Color Rules';
  pnlRules := MakeTabPanel(Self, tabFarbStrings);

  lbRules           := TListBox.Create(Self);
  lbRules.Parent    := pnlRules;
  lbRules.Left      := 5; lbRules.Top := 5;
  lbRules.Width     := 410; lbRules.Height := 130;
  lbRules.OnClick   := @lbRulesClick;

  L(pnlRules, 'Pattern (substring):', 5, 143);
  edtPattern        := TEdit.Create(Self);
  edtPattern.Parent := pnlRules;
  edtPattern.Left   := 160; edtPattern.Top := 140;
  edtPattern.Width  := 200;

  L(pnlRules, 'Background:', 5, 170);
  cbRuleColor        := TColorBox.Create(Self);
  cbRuleColor.Parent := pnlRules;
  cbRuleColor.Left   := 160; cbRuleColor.Top := 167;
  cbRuleColor.Width  := 155;
  cbRuleColor.Style  := cbRuleColor.Style + [cbCustomColor, cbSystemColors];
  L(pnlRules, 'Foreground:', 320, 170);
  cbRuleFgColor        := TColorBox.Create(Self);
  cbRuleFgColor.Parent := pnlRules;
  cbRuleFgColor.Left   := 395; cbRuleFgColor.Top := 167;
  cbRuleFgColor.Width  := 80;
  cbRuleFgColor.Style  := cbRuleFgColor.Style + [cbCustomColor, cbSystemColors];

  chkUseLevel         := TCheckBox.Create(Self);
  chkUseLevel.Parent  := pnlRules;
  chkUseLevel.Left    := 5; chkUseLevel.Top := 196;
  chkUseLevel.Caption := 'Assign level class instead of color:';
  chkUseLevel.Width   := 220;

  cmbRuleLevel        := TComboBox.Create(Self);
  cmbRuleLevel.Parent := pnlRules;
  cmbRuleLevel.Left   := 230; cmbRuleLevel.Top := 194;
  cmbRuleLevel.Width  := 130; cmbRuleLevel.Style := csDropDownList;
  cmbRuleLevel.Items.Add('ERROR');
  cmbRuleLevel.Items.Add('WARN');
  cmbRuleLevel.Items.Add('INFO');
  cmbRuleLevel.Items.Add('DEBUG');
  cmbRuleLevel.Items.Add('TRACE');
  cmbRuleLevel.Items.Add('Other');
  cmbRuleLevel.ItemIndex := 0;

  chkRuleEnabled         := TCheckBox.Create(Self);
  chkRuleEnabled.Parent  := pnlRules;
  chkRuleEnabled.Left    := 5; chkRuleEnabled.Top := 222;
  chkRuleEnabled.Caption := 'Enabled';
  chkRuleEnabled.Checked := True;

  btnRuleAdd           := TButton.Create(Self);
  btnRuleAdd.Parent    := pnlRules;
  btnRuleAdd.Left      := 5;   btnRuleAdd.Top := 248;
  btnRuleAdd.Width     := 90;  btnRuleAdd.Caption := 'Add';
  btnRuleAdd.OnClick   := @BtnRuleAddClick;

  btnRuleUpdate         := TButton.Create(Self);
  btnRuleUpdate.Parent  := pnlRules;
  btnRuleUpdate.Left    := 105; btnRuleUpdate.Top := 248;
  btnRuleUpdate.Width   := 90;  btnRuleUpdate.Caption := 'Update';
  btnRuleUpdate.OnClick := @BtnRuleUpdateClick;

  btnRuleDelete         := TButton.Create(Self);
  btnRuleDelete.Parent  := pnlRules;
  btnRuleDelete.Left    := 205; btnRuleDelete.Top := 248;
  btnRuleDelete.Width   := 90;  btnRuleDelete.Caption := 'Delete';
  btnRuleDelete.OnClick := @BtnRuleDeleteClick;

  // == Tab 4: Format ====================================================
  tabFormat             := TTabSheet.Create(PageCtrl);
  tabFormat.Parent      := PageCtrl;
  tabFormat.PageControl := PageCtrl;
  tabFormat.Caption     := 'Format';
  pnlFormat := MakeTabPanel(Self, tabFormat);

  chkAutoDetect         := TCheckBox.Create(Self);
  chkAutoDetect.Parent  := pnlFormat;
  chkAutoDetect.Left    := 10; chkAutoDetect.Top := 8;
  chkAutoDetect.Caption := 'Auto-detect format';
  chkAutoDetect.Width   := 280;
  chkAutoDetect.OnChange := @chkAutoDetectChange;

  L(pnlFormat, 'Forced Format:', 10, 34);
  cmbForceFormat        := TComboBox.Create(Self);
  cmbForceFormat.Parent := pnlFormat;
  cmbForceFormat.Left   := 130; cmbForceFormat.Top := 30;
  cmbForceFormat.Width  := 220; cmbForceFormat.Style := csDropDownList;
  cmbForceFormat.OnChange := @DoFormatChange;
  for FmtIdx := Low(TLogFormat) to High(TLogFormat) do
    cmbForceFormat.Items.Add(LogFormatNames[FmtIdx]);

  lblDetected         := TLabel.Create(Self);
  lblDetected.Parent  := pnlFormat;
  lblDetected.Left    := 10; lblDetected.Top := 60;
  lblDetected.Caption := 'Detected format: -';
  lblDetected.Width   := 360;

  // -- Custom Format GroupBox -------------------------------------------
  grpCustom            := TGroupBox.Create(Self);
  grpCustom.Parent     := pnlFormat;
  grpCustom.Left       := 5; grpCustom.Top := 78;
  grpCustom.Width      := 450; grpCustom.Height := 251;
  grpCustom.Caption    := 'Custom format definition';

  rgCfMode             := TRadioGroup.Create(Self);
  rgCfMode.Parent      := grpCustom;
  rgCfMode.Left        := 8; rgCfMode.Top := 14;
  rgCfMode.Width       := 200; rgCfMode.Height := 42;
  rgCfMode.Columns     := 2;
  rgCfMode.Caption     := 'Mode';
  rgCfMode.Items.Add('Delimiter');
  rgCfMode.Items.Add('Position');
  rgCfMode.ItemIndex   := 0;
  rgCfMode.OnClick     := @DoCfModeChange;

  // Delimiter controls
  lblCfDelim           := L(grpCustom, 'Delimiter:', 220, 28);
  edtCfDelim           := TEdit.Create(Self);
  edtCfDelim.Parent    := grpCustom;
  edtCfDelim.Left      := 290; edtCfDelim.Top := 24;
  edtCfDelim.Width     := 30;  edtCfDelim.MaxLength := 1;

  lblCfFields          := L(grpCustom, 'Field roles:', 8, 62);
  for i := 0 to MAX_CUSTOM_FIELDS - 1 do
  begin
    lblCfFieldNo[i]          := L(grpCustom, IntToStr(i + 1) + ':', 8 + i * 54, 78);
    cmbCfRoles[i]            := TComboBox.Create(Self);
    cmbCfRoles[i].Parent     := grpCustom;
    cmbCfRoles[i].Left       := 8 + i * 54;
    cmbCfRoles[i].Top        := 94;
    cmbCfRoles[i].Width      := 50;
    cmbCfRoles[i].Style      := csDropDownList;
    cmbCfRoles[i].Items.Add('--');
    cmbCfRoles[i].Items.Add('TS');
    cmbCfRoles[i].Items.Add('Lvl');
    cmbCfRoles[i].Items.Add('Src');
    cmbCfRoles[i].Items.Add('Thr');
    cmbCfRoles[i].ItemIndex  := 0;
  end;

  // Position controls
  lblCfTS              := L(grpCustom, 'Timestamp  Start:', 8, 62);
  spnCfTSStart         := TSpinEdit.Create(Self);
  spnCfTSStart.Parent  := grpCustom;
  spnCfTSStart.Left    := 130; spnCfTSStart.Top := 58;
  spnCfTSStart.Width   := 55; spnCfTSStart.MinValue := 0; spnCfTSStart.MaxValue := 999;
  lblCfTSLen           := L(grpCustom, 'Len:', 192, 62);
  spnCfTSLen           := TSpinEdit.Create(Self);
  spnCfTSLen.Parent    := grpCustom;
  spnCfTSLen.Left      := 220; spnCfTSLen.Top := 58;
  spnCfTSLen.Width     := 55; spnCfTSLen.MinValue := 0; spnCfTSLen.MaxValue := 50;

  lblCfLvl             := L(grpCustom, 'Level         Start:', 8, 86);
  spnCfLvlStart        := TSpinEdit.Create(Self);
  spnCfLvlStart.Parent := grpCustom;
  spnCfLvlStart.Left   := 130; spnCfLvlStart.Top := 82;
  spnCfLvlStart.Width  := 55; spnCfLvlStart.MinValue := 0; spnCfLvlStart.MaxValue := 999;
  lblCfLvlLen          := L(grpCustom, 'Len:', 192, 86);
  spnCfLvlLen          := TSpinEdit.Create(Self);
  spnCfLvlLen.Parent   := grpCustom;
  spnCfLvlLen.Left     := 220; spnCfLvlLen.Top := 82;
  spnCfLvlLen.Width    := 55; spnCfLvlLen.MinValue := 0; spnCfLvlLen.MaxValue := 50;

  lblCfSrc             := L(grpCustom, 'Source       Start:', 8, 110);
  spnCfSrcStart        := TSpinEdit.Create(Self);
  spnCfSrcStart.Parent := grpCustom;
  spnCfSrcStart.Left   := 130; spnCfSrcStart.Top := 106;
  spnCfSrcStart.Width  := 55; spnCfSrcStart.MinValue := 0; spnCfSrcStart.MaxValue := 999;
  lblCfSrcLen          := L(grpCustom, 'Len:', 192, 110);
  spnCfSrcLen          := TSpinEdit.Create(Self);
  spnCfSrcLen.Parent   := grpCustom;
  spnCfSrcLen.Left     := 220; spnCfSrcLen.Top := 106;
  spnCfSrcLen.Width    := 55; spnCfSrcLen.MinValue := 0; spnCfSrcLen.MaxValue := 50;

  // Timestamp format (both modes)
  lblCfTSFmt           := L(grpCustom, 'Timestamp format:', 8, 140);
  edtCfTSFmt           := TEdit.Create(Self);
  edtCfTSFmt.Parent    := grpCustom;
  edtCfTSFmt.Left      := 130; edtCfTSFmt.Top := 136;
  edtCfTSFmt.Width     := 200;
  L(grpCustom, 'e.g. YYYY/MM/DD hh:nn:ss.zzz', 8, 162);

  // == Tab 5: Tail ======================================================
  tabTail             := TTabSheet.Create(PageCtrl);
  tabTail.Parent      := PageCtrl;
  tabTail.PageControl := PageCtrl;
  tabTail.Caption     := 'Tail';
  pnlTail := MakeTabPanel(Self, tabTail);

  chkTail         := TCheckBox.Create(Self);
  chkTail.Parent  := pnlTail;
  chkTail.Left    := 10; chkTail.Top := 14;
  chkTail.Caption := 'Enable tail when opening a file';
  chkTail.Width   := 320;

  L(pnlTail, 'Check interval (ms):', 10, 50);
  spnTailMs          := TSpinEdit.Create(Self);
  spnTailMs.Parent   := pnlTail;
  spnTailMs.Left     := 155; spnTailMs.Top := 46;
  spnTailMs.Width    := 90;
  spnTailMs.MinValue := 200; spnTailMs.MaxValue := 30000;
end;

{ Rekursiv ein Control und alle Kinder einfaerben }
procedure TfrmOptions.ThemeControl(AControl: TControl;
  ABg, AFg, ABgEdit: TColor);
var
  i        : Integer;
  WinCtrl  : TWinControl;
  BtnBg    : TColor;
begin
  AControl.Font.Color := AFg;

  // Buttons bekommen einen deutlich dunkleren Hintergrund
  BtnBg := ABgEdit;  // gleich dunkel wie Edit-Felder

  if (AControl is TEdit) or (AControl is TSpinEdit)
     or (AControl is TComboBox) or (AControl is TListBox) then
  begin
    if AControl is TEdit      then TEdit(AControl).Color      := ABgEdit;
    if AControl is TSpinEdit  then TSpinEdit(AControl).Color  := ABgEdit;
    if AControl is TComboBox  then TComboBox(AControl).Color  := ABgEdit;
    if AControl is TListBox   then TListBox(AControl).Color   := ABgEdit;
  end
  else if AControl is TPanel then
    TPanel(AControl).Color := ABg
  else if AControl is TGroupBox then
    TGroupBox(AControl).Color := ABg
  else if AControl is TRadioGroup then
    TRadioGroup(AControl).Color := ABg
  else if AControl is TButton then
  begin
    TButton(AControl).Color := BtnBg;
    TButton(AControl).Font.Color := AFg;
  end;

  // Kinder durchlaufen
  if AControl is TWinControl then
  begin
    WinCtrl := TWinControl(AControl);
    for i := 0 to WinCtrl.ControlCount - 1 do
      ThemeControl(WinCtrl.Controls[i], ABg, AFg, ABgEdit);
  end;
end;

{ Faerbt das gesamte Einstellungsfenster passend zum aktiven Theme }
procedure TfrmOptions.ApplyDarkModeToDialog;
var
  ABg, AFg, ABgEdit : TColor;
begin
  if not IsDarkModeActive then
    Exit;

  ABg     := AppSettings.DarkColors.BgToolbar;
  AFg     := AppSettings.DarkColors.FgDefault;
  ABgEdit := AppSettings.DarkColors.BgDefault;

  Color := ABg;
  Font.Color := AFg;

  // Native Windows-Theme auf Tab-Reitern deaktivieren
  {$IFDEF WINDOWS}
  PageCtrl.Handle;
  SetWindowTheme(PageCtrl.Handle, ' ', ' ');
  {$ENDIF}

  // Die alClient-Panels in jedem Tab uebernehmen die Hintergrundfarbe
  // zuverlaessig, da sie normale TPanels sind (kein natives Tab-Painting)
  ThemeControl(Self, ABg, AFg, ABgEdit);
end;

{ Laedt die ColorBoxen aus einem TThemeColors-Record }
procedure TfrmOptions.LoadColorBoxesFromSet(const C: TThemeColors);
begin
  cbError.Selected    := C.ColError;
  cbWarn.Selected     := C.ColWarn;
  cbInfo.Selected     := C.ColInfo;
  cbDebug.Selected    := C.ColDebug;
  cbTrace.Selected    := C.ColTrace;
  cbCustom.Selected   := C.ColCustom;
  cbFgError.Selected  := C.FgError;
  cbFgWarn.Selected   := C.FgWarn;
  cbFgInfo.Selected   := C.FgInfo;
  cbFgDebug.Selected  := C.FgDebug;
  cbFgTrace.Selected  := C.FgTrace;
  cbFgCustom.Selected := C.FgCustom;
end;

{ Speichert die ColorBoxen in ein TThemeColors-Record }
procedure TfrmOptions.SaveColorBoxesToSet(var C: TThemeColors);
begin
  C.ColError  := cbError.Selected;
  C.ColWarn   := cbWarn.Selected;
  C.ColInfo   := cbInfo.Selected;
  C.ColDebug  := cbDebug.Selected;
  C.ColTrace  := cbTrace.Selected;
  C.ColCustom := cbCustom.Selected;
  C.FgError   := cbFgError.Selected;
  C.FgWarn    := cbFgWarn.Selected;
  C.FgInfo    := cbFgInfo.Selected;
  C.FgDebug   := cbFgDebug.Selected;
  C.FgTrace   := cbFgTrace.Selected;
  C.FgCustom  := cbFgCustom.Selected;
end;

procedure TfrmOptions.DoColorThemeSwitch(Sender: TObject);
begin
  if rgColorTheme.ItemIndex = 0 then
  begin
    SaveColorBoxesToSet(FEditDark);
    LoadColorBoxesFromSet(FEditLight);
  end
  else
  begin
    SaveColorBoxesToSet(FEditLight);
    LoadColorBoxesFromSet(FEditDark);
  end;
end;

procedure TfrmOptions.LoadFromSettings;
var
  i : Integer;
begin
  rgThemeMode.ItemIndex  := Integer(AppSettings.ThemeMode);
  chkLineNumbers.Checked := AppSettings.ShowLineNumbers;
  spnLineWidth.Value     := AppSettings.LineNumberWidth;
  chkWordWrap.Checked    := AppSettings.WordWrap;
  cmbFontName.Text       := AppSettings.FontName;
  lblFontPreview.Font.Name := AppSettings.FontName;
  lblFontPreview.Font.Size := AppSettings.FontSize;
  spnFontSize.Value      := AppSettings.FontSize;

  FEditLight := AppSettings.LightColors;
  FEditDark  := AppSettings.DarkColors;
  rgColorTheme.ItemIndex := 0;
  LoadColorBoxesFromSet(FEditLight);

  RefreshRuleList;

  chkAutoDetect.Checked     := AppSettings.AutoDetectFormat;
  cmbForceFormat.ItemIndex  := Integer(AppSettings.ForceFormat);
  cmbForceFormat.Enabled    := not AppSettings.AutoDetectFormat;

  // Custom format
  rgCfMode.ItemIndex := Integer(AppSettings.CustomFormat.Mode);
  if AppSettings.CustomFormat.Delimiter <> #0 then
    edtCfDelim.Text := AppSettings.CustomFormat.Delimiter
  else
    edtCfDelim.Text := '|';
  for i := 0 to MAX_CUSTOM_FIELDS - 1 do
    cmbCfRoles[i].ItemIndex := Integer(AppSettings.CustomFormat.FieldRoles[i]);
  spnCfTSStart.Value  := AppSettings.CustomFormat.TSStart;
  spnCfTSLen.Value    := AppSettings.CustomFormat.TSLen;
  spnCfLvlStart.Value := AppSettings.CustomFormat.LvlStart;
  spnCfLvlLen.Value   := AppSettings.CustomFormat.LvlLen;
  spnCfSrcStart.Value := AppSettings.CustomFormat.SrcStart;
  spnCfSrcLen.Value   := AppSettings.CustomFormat.SrcLen;
  edtCfTSFmt.Text     := AppSettings.CustomFormat.TimestampFmt;
  UpdateCustomVisible;

  chkTail.Checked   := AppSettings.TailEnabled;
  spnTailMs.Value   := AppSettings.TailIntervalMs;
end;

procedure TfrmOptions.RefreshRuleList;
var
  i : Integer;
  S : string;
begin
  lbRules.Items.Clear;
  for i := 0 to AppSettings.ColorRuleCount - 1 do
  begin
    S := AppSettings.ColorRules[i].Pattern;
    if AppSettings.ColorRules[i].UseLevel then
    begin
      case AppSettings.ColorRules[i].Level of
        lError  : S := S + '  ->  ERROR';
        lWarn   : S := S + '  ->  WARN';
        lInfo   : S := S + '  ->  INFO';
        lDebug  : S := S + '  ->  DEBUG';
        lTrace  : S := S + '  ->  TRACE';
      else
        S := S + '  ->  Other';
      end;
    end;
    if not AppSettings.ColorRules[i].Enabled then
      S := '[off] ' + S;
    lbRules.Items.Add(S);
  end;
end;

procedure TfrmOptions.lbRulesClick(Sender: TObject);
var
  i: Integer;
begin
  i := lbRules.ItemIndex;
  if (i < 0) or (i >= AppSettings.ColorRuleCount) then Exit;
  edtPattern.Text        := AppSettings.ColorRules[i].Pattern;
  cbRuleColor.Selected   := AppSettings.ColorRules[i].Color;
  cbRuleFgColor.Selected := AppSettings.ColorRules[i].FgColor;
  chkRuleEnabled.Checked := AppSettings.ColorRules[i].Enabled;
  chkUseLevel.Checked    := AppSettings.ColorRules[i].UseLevel;
  cmbRuleLevel.ItemIndex := Integer(AppSettings.ColorRules[i].Level);
end;

procedure TfrmOptions.BtnRuleAddClick(Sender: TObject);
var
  i: Integer;
begin
  if Trim(edtPattern.Text) = '' then Exit;
  if AppSettings.ColorRuleCount >= MAX_COLOR_STRINGS then Exit;
  i := AppSettings.ColorRuleCount;
  AppSettings.ColorRules[i].Pattern  := Trim(edtPattern.Text);
  AppSettings.ColorRules[i].Color    := cbRuleColor.Selected;
  AppSettings.ColorRules[i].FgColor  := cbRuleFgColor.Selected;
  AppSettings.ColorRules[i].Enabled  := chkRuleEnabled.Checked;
  AppSettings.ColorRules[i].UseLevel := chkUseLevel.Checked;
  AppSettings.ColorRules[i].Level    := TLogLevel(cmbRuleLevel.ItemIndex);
  Inc(AppSettings.ColorRuleCount);
  RefreshRuleList;
end;

procedure TfrmOptions.BtnRuleUpdateClick(Sender: TObject);
var
  i: Integer;
begin
  i := lbRules.ItemIndex;
  if (i < 0) or (i >= AppSettings.ColorRuleCount) then Exit;
  AppSettings.ColorRules[i].Pattern  := Trim(edtPattern.Text);
  AppSettings.ColorRules[i].Color    := cbRuleColor.Selected;
  AppSettings.ColorRules[i].FgColor  := cbRuleFgColor.Selected;
  AppSettings.ColorRules[i].Enabled  := chkRuleEnabled.Checked;
  AppSettings.ColorRules[i].UseLevel := chkUseLevel.Checked;
  AppSettings.ColorRules[i].Level    := TLogLevel(cmbRuleLevel.ItemIndex);
  RefreshRuleList;
end;

procedure TfrmOptions.BtnRuleDeleteClick(Sender: TObject);
var
  i, j: Integer;
begin
  i := lbRules.ItemIndex;
  if (i < 0) or (i >= AppSettings.ColorRuleCount) then Exit;
  for j := i to AppSettings.ColorRuleCount - 2 do
    AppSettings.ColorRules[j] := AppSettings.ColorRules[j + 1];
  Dec(AppSettings.ColorRuleCount);
  RefreshRuleList;
end;

procedure TfrmOptions.chkAutoDetectChange(Sender: TObject);
begin
  cmbForceFormat.Enabled := not chkAutoDetect.Checked;
  UpdateCustomVisible;
end;

procedure TfrmOptions.DoFormatChange(Sender: TObject);
begin
  UpdateCustomVisible;
end;

procedure TfrmOptions.DoCfModeChange(Sender: TObject);
begin
  UpdateCustomVisible;
end;

procedure TfrmOptions.UpdateCustomVisible;
var
  ShowCustom, IsDelim : Boolean;
  i                   : Integer;
begin
  ShowCustom := (not chkAutoDetect.Checked)
    and (cmbForceFormat.ItemIndex = Integer(lfCustom));
  grpCustom.Visible := ShowCustom;
  if not ShowCustom then Exit;

  IsDelim := (rgCfMode.ItemIndex = 0);

  // Delimiter-Controls
  lblCfDelim.Visible  := IsDelim;
  edtCfDelim.Visible  := IsDelim;
  lblCfFields.Visible := IsDelim;
  for i := 0 to MAX_CUSTOM_FIELDS - 1 do
  begin
    lblCfFieldNo[i].Visible := IsDelim;
    cmbCfRoles[i].Visible   := IsDelim;
  end;

  // Position-Controls
  lblCfTS.Visible        := not IsDelim;
  spnCfTSStart.Visible   := not IsDelim;
  lblCfTSLen.Visible     := not IsDelim;
  spnCfTSLen.Visible     := not IsDelim;
  lblCfLvl.Visible       := not IsDelim;
  spnCfLvlStart.Visible  := not IsDelim;
  lblCfLvlLen.Visible    := not IsDelim;
  spnCfLvlLen.Visible    := not IsDelim;
  lblCfSrc.Visible       := not IsDelim;
  spnCfSrcStart.Visible  := not IsDelim;
  lblCfSrcLen.Visible    := not IsDelim;
  spnCfSrcLen.Visible    := not IsDelim;
end;

procedure TfrmOptions.DoFontChanged(Sender: TObject);
begin
  lblFontPreview.Font.Name := cmbFontName.Text;
  lblFontPreview.Font.Size := spnFontSize.Value;
end;

procedure TfrmOptions.DoBtnPickFont(Sender: TObject);
var
  Dlg: TFontDialog;
begin
  Dlg := TFontDialog.Create(Self);
  try
    Dlg.Font.Name := cmbFontName.Text;
    Dlg.Font.Size := spnFontSize.Value;
    if Dlg.Execute then
    begin
      cmbFontName.Text    := Dlg.Font.Name;
      spnFontSize.Value   := Dlg.Font.Size;
      DoFontChanged(nil);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmOptions.SaveToSettings;
var
  i : Integer;
begin
  AppSettings.ThemeMode := TThemeMode(rgThemeMode.ItemIndex);
  AppSettings.ShowLineNumbers := chkLineNumbers.Checked;
  AppSettings.LineNumberWidth := spnLineWidth.Value;
  AppSettings.WordWrap        := chkWordWrap.Checked;
  AppSettings.FontName        := cmbFontName.Text;
  AppSettings.FontSize        := spnFontSize.Value;

  if rgColorTheme.ItemIndex = 0 then
    SaveColorBoxesToSet(FEditLight)
  else
    SaveColorBoxesToSet(FEditDark);

  AppSettings.LightColors := FEditLight;
  AppSettings.DarkColors  := FEditDark;

  AppSettings.AutoDetectFormat := chkAutoDetect.Checked;
  AppSettings.ForceFormat      := TLogFormat(cmbForceFormat.ItemIndex);

  // Custom format
  AppSettings.CustomFormat.Mode := TCustomFormatMode(rgCfMode.ItemIndex);
  if Length(edtCfDelim.Text) > 0 then
    AppSettings.CustomFormat.Delimiter := edtCfDelim.Text[1]
  else
    AppSettings.CustomFormat.Delimiter := '|';
  AppSettings.CustomFormat.FieldCount := MAX_CUSTOM_FIELDS;
  for i := 0 to MAX_CUSTOM_FIELDS - 1 do
    AppSettings.CustomFormat.FieldRoles[i] :=
      TCustomFieldRole(cmbCfRoles[i].ItemIndex);
  AppSettings.CustomFormat.TSStart  := spnCfTSStart.Value;
  AppSettings.CustomFormat.TSLen    := spnCfTSLen.Value;
  AppSettings.CustomFormat.LvlStart := spnCfLvlStart.Value;
  AppSettings.CustomFormat.LvlLen   := spnCfLvlLen.Value;
  AppSettings.CustomFormat.SrcStart := spnCfSrcStart.Value;
  AppSettings.CustomFormat.SrcLen   := spnCfSrcLen.Value;
  AppSettings.CustomFormat.TimestampFmt := edtCfTSFmt.Text;

  AppSettings.TailEnabled    := chkTail.Checked;
  AppSettings.TailIntervalMs := spnTailMs.Value;

  ApplyThemeColors;
end;

class function TfrmOptions.Execute(AOwner: TComponent): Boolean;
begin
  Result := ExecuteWithDetected(AOwner, lfUnknown);
end;

class function TfrmOptions.ExecuteWithDetected(AOwner: TComponent;
  ADetected: TLogFormat): Boolean;
var
  Dlg: TfrmOptions;
begin
  Dlg := TfrmOptions.Create(AOwner);
  try
    if ADetected <> lfUnknown then
      Dlg.lblDetected.Caption := 'Detected format: ' + LogFormatNames[ADetected];
    Result := Dlg.ShowModal = mrOk;
    if Result then
    begin
      Dlg.SaveToSettings;
      SaveSettings;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
