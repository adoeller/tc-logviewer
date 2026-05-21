unit uLogModel;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, uLogTypes;

type
  TLogList = class
  private
    FItems    : TLogEntryArray;
    FCount    : Integer;
    FCapacity : Integer;
    FRawBuf   : AnsiString;   // gesamter Rohtext aller Zeilen in einem Puffer
    FRawUsed  : Integer;      // genutzte Bytes in FRawBuf
    function GetItem(Index: Integer): TLogEntry;
    procedure Grow;
  public
    constructor Create;
    procedure ReserveRaw(AFileSize: Int64);
    function  AppendRaw(ABuf: PAnsiChar; ALen: Integer): Integer;
    function  RawPtr(AOffset: Integer): PAnsiChar; inline;
    function  RawStr(AOffset, ALen: Integer): string; inline;
    function  PrepareAdd: Integer;
    procedure CommitAdd; inline;
    function  Slot(AIndex: Integer): PLogEntry; inline;
    procedure Clear;
    procedure EnsureCapacity(ACount: Integer);
    property Count    : Integer       read FCount;
    property Items[Index: Integer]: TLogEntry read GetItem; default;
    property RawItems : TLogEntryArray read FItems;
    property RawBufUsed : Integer     read FRawUsed;
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
  FRawBuf  := '';
  FRawUsed := 0;
end;

procedure TLogList.ReserveRaw(AFileSize: Int64);
begin
  // Puffer wiederverwenden wenn gross genug, sonst wachsen
  if AFileSize + 1 > Length(FRawBuf) then
    SetLength(FRawBuf, AFileSize + 1);
  FRawUsed := 0;
end;

function TLogList.AppendRaw(ABuf: PAnsiChar; ALen: Integer): Integer;
begin
  // Puffer bei Tail-Eintraegen ggf. vergroessern
  if FRawUsed + ALen + 1 > Length(FRawBuf) then
    SetLength(FRawBuf, Max(Length(FRawBuf) * 2, FRawUsed + ALen + 65536));
  Result := FRawUsed;
  if ALen > 0 then
    Move(ABuf^, FRawBuf[FRawUsed + 1], ALen);
  Inc(FRawUsed, ALen);
end;

function TLogList.RawPtr(AOffset: Integer): PAnsiChar;
begin
  Result := PAnsiChar(@FRawBuf[AOffset + 1]);
end;

function TLogList.RawStr(AOffset, ALen: Integer): string;
begin
  SetString(Result, PAnsiChar(@FRawBuf[AOffset + 1]), ALen);
end;

procedure TLogList.Grow;
begin
  if FCapacity < 65536 then
    FCapacity := FCapacity * 2
  else
    FCapacity := FCapacity + 65536;
  SetLength(FItems, FCapacity);
end;

function TLogList.PrepareAdd: Integer;
begin
  if FCount >= FCapacity then Grow;
  Result := FCount;
end;

procedure TLogList.CommitAdd; inline;
begin
  Inc(FCount);
end;

function TLogList.Slot(AIndex: Integer): PLogEntry;
begin
  Result := @FItems[AIndex];
end;

{ Clear: O(1) da TLogEntry keine Managed-Felder hat.
  FRawBuf bleibt allokiert fuer Wiederverwendung bei naechster Datei. }
procedure TLogList.Clear;
begin
  FCount    := 0;
  FCapacity := INITIAL_CAPACITY;
  SetLength(FItems, FCapacity);   // kein Finalizer-Loop – unmanaged Record
  FRawUsed  := 0;                 // Puffer-Inhalt einfach vergessen
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

end.
