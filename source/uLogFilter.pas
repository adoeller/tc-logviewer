unit uLogFilter;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, uLogTypes, uLogModel, uLogParser;

type
  TFilterSpec = class
  private
    FText      : string;
    FTextLower : string;        // gecachte Lowercase-Version von FText
    FLevels    : TLevelSet;
    procedure SetText(const V: string);
  public
    constructor Create;
    procedure Reset;
    property Text   : string    read FText   write SetText;
    property Levels : TLevelSet read FLevels write FLevels;
    function IsActive: Boolean;
    function Matches(const AEntry: TLogEntry): Boolean;
    function Apply(const AList: TLogList; out ACount: Integer): TLogEntryArray;
  end;

const
  AllLevels : TLevelSet = [lError, lWarn, lInfo, lDebug, lTrace, lCustom];

implementation

constructor TFilterSpec.Create;
begin
  inherited Create;
  FLevels := AllLevels;
end;

procedure TFilterSpec.SetText(const V: string);
begin
  FText      := V;
  FTextLower := LowerCase(V);
end;

procedure TFilterSpec.Reset;
begin
  SetText('');
  FLevels := AllLevels;
end;

function TFilterSpec.IsActive: Boolean;
begin
  Result := (FTextLower <> '') or (FLevels <> AllLevels);
end;

function TFilterSpec.Matches(const AEntry: TLogEntry): Boolean;
begin
  Result := (AEntry.Level in FLevels);
  if Result and (FTextLower <> '') then
    Result := Pos(FTextLower, LowerCase(AEntry.Raw)) > 0;
end;

function TFilterSpec.Apply(const AList: TLogList;
  out ACount: Integer): TLogEntryArray;
var
  Arr   : TLogEntryArray;
  N, i  : Integer;
  cnt   : Integer;
begin
  N   := AList.Count;
  Arr := AList.RawItems;

  // Fast-Path: kein Filter aktiv → Direkt-Referenz, keine Kopie
  if not IsActive then
  begin
    Result := Arr;
    ACount := N;
    Exit;
  end;

  // Pass 1: Treffer zaehlen
  cnt := 0;
  for i := 0 to N - 1 do
    if Matches(Arr[i]) then Inc(cnt);

  SetLength(Result, cnt);
  ACount := cnt;

  // Pass 2: kopieren
  cnt := 0;
  for i := 0 to N - 1 do
    if Matches(Arr[i]) then
    begin
      Result[cnt] := Arr[i];
      Inc(cnt);
    end;
end;

end.
