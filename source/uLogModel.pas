unit uLogModel;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, uLogTypes, uLogParser;

type
  TLogList = class
  private
    FItems    : TLogEntryArray;
    FCount    : Integer;
    FCapacity : Integer;
    function GetItem(Index: Integer): TLogEntry;
    procedure SetItem(Index: Integer; const Value: TLogEntry);
    procedure Grow;
  public
    constructor Create;
    procedure Add(const AEntry: TLogEntry);
    function  PrepareAdd: Integer;    // ensures capacity, returns index
    procedure CommitAdd; inline;      // increments count
    function  Slot(AIndex: Integer): PLogEntry; inline;
    procedure Clear;
    procedure TrimToSize;
    procedure EnsureCapacity(ACount: Integer);
    property Count    : Integer read FCount;
    property Items[Index: Integer]: TLogEntry read GetItem write SetItem; default;
    property RawItems : TLogEntryArray read FItems;
  end;

implementation

const
  INITIAL_CAPACITY = 4096;

constructor TLogList.Create;
begin
  inherited Create;
  FCount    := 0;
  FCapacity := INITIAL_CAPACITY;
  SetLength(FItems, FCapacity);
end;

procedure TLogList.Grow;
begin
  if FCapacity < 65536 then
    FCapacity := FCapacity * 2
  else
    FCapacity := FCapacity + 65536;
  SetLength(FItems, FCapacity);
end;

procedure TLogList.Add(const AEntry: TLogEntry);
begin
  if FCount >= FCapacity then Grow;
  FItems[FCount] := AEntry;
  Inc(FCount);
end;

function TLogList.PrepareAdd: Integer;
begin
  if FCount >= FCapacity then Grow;
  Result := FCount;
end;

procedure TLogList.CommitAdd;
begin
  Inc(FCount);
end;

function TLogList.Slot(AIndex: Integer): PLogEntry;
begin
  Result := @FItems[AIndex];
end;

procedure TLogList.Clear;
begin
  FCount    := 0;
  FCapacity := INITIAL_CAPACITY;
  SetLength(FItems, FCapacity);
end;

procedure TLogList.TrimToSize;
begin
  SetLength(FItems, FCount);
  FCapacity := FCount;
end;

procedure TLogList.EnsureCapacity(ACount: Integer);
begin
  if ACount > FCapacity then
  begin
    FCapacity := ACount;
    SetLength(FItems, FCapacity);
  end;
end;

function TLogList.GetItem(Index: Integer): TLogEntry;
begin
  Result := FItems[Index];
end;

procedure TLogList.SetItem(Index: Integer; const Value: TLogEntry);
begin
  FItems[Index] := Value;
end;

end.
