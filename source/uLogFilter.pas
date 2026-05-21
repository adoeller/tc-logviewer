unit uLogFilter;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, uLogTypes, uLogModel;

type
  TFilterSpec = class
  private
    FLogList   : TLogList;
    FText      : string;
    FTextLower : string;
    FLevels    : TLevelSet;
    procedure SetText(const V: string);
  public
    constructor Create(ALogList: TLogList);
    procedure Reset;
    property Text    : string    read FText    write SetText;
    property Levels  : TLevelSet read FLevels  write FLevels;
    property LogList : TLogList  read FLogList write FLogList;
    function IsActive: Boolean;
    function Matches(const AEntry: TLogEntry): Boolean;
    function Apply(const AList: TLogList; out ACount: Integer): TLogEntryArray;
  end;

const
  AllLevels : TLevelSet = [lError, lWarn, lInfo, lDebug, lTrace, lCustom];

implementation

constructor TFilterSpec.Create(ALogList: TLogList);
begin
  inherited Create;
  FLogList := ALogList;
  FLevels  := AllLevels;
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
var
  RawS : string;
begin
  Result := AEntry.Level in FLevels;
  if Result and (FTextLower <> '') then
  begin
    if Assigned(FLogList) then
      RawS := FLogList.RawStr(AEntry.RawOffset, AEntry.RawLen)
    else
      RawS := '';
    Result := Pos(FTextLower, LowerCase(RawS)) > 0;
  end;
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

  if not IsActive then
  begin
    Result := Arr;
    ACount := N;
    Exit;
  end;

  cnt := 0;
  for i := 0 to N - 1 do
    if Matches(Arr[i]) then Inc(cnt);

  SetLength(Result, cnt);
  ACount := cnt;

  cnt := 0;
  for i := 0 to N - 1 do
    if Matches(Arr[i]) then
    begin
      Result[cnt] := Arr[i];
      Inc(cnt);
    end;
end;

end.
