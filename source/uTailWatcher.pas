unit uTailWatcher;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ExtCtrls;

type
  TNewLineEvent = procedure(const ALine: string; ALineNo: Integer) of object;

  TTailWatcher = class
  private
    FTimer      : TTimer;
    FFileName   : string;
    FLastSize   : Int64;
    FLastLineNo : Integer;
    FOnNewLine  : TNewLineEvent;
    FActive     : Boolean;
    FPartial    : string;       // unvollstaendige letzte Zeile aus vorigem Tick
    procedure TimerTick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const AFileName: string; ALastLineNo: Integer;
      AIntervalMs: Integer);
    procedure Stop;
    property OnNewLine : TNewLineEvent read FOnNewLine write FOnNewLine;
    property Active    : Boolean       read FActive;
  end;

implementation

constructor TTailWatcher.Create;
begin
  inherited Create;
  FTimer         := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;
  FLastSize      := 0;
  FLastLineNo    := 0;
  FActive        := False;
  FPartial       := '';
end;

destructor TTailWatcher.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

procedure TTailWatcher.Start(const AFileName: string; ALastLineNo: Integer;
  AIntervalMs: Integer);
var
  SR: TSearchRec;
begin
  FFileName       := AFileName;
  FLastLineNo     := ALastLineNo;
  FLastSize       := 0;
  FPartial        := '';
  if FindFirst(AFileName, faAnyFile, SR) = 0 then
  begin
    FLastSize := SR.Size;
    FindClose(SR);
  end;
  FTimer.Interval := AIntervalMs;
  FTimer.Enabled  := True;
  FActive         := True;
end;

procedure TTailWatcher.Stop;
begin
  FTimer.Enabled := False;
  FActive        := False;
end;

procedure TTailWatcher.TimerTick(Sender: TObject);
var
  SR      : TSearchRec;
  NewSize : Int64;
  FS      : TFileStream;
  Buf     : RawByteString;
  Delta   : Int64;
  S       : string;
  P, LineStart: Integer;
begin
  if FFileName = '' then Exit;
  Buf := '';   // suppress uninitialized hint; SetLength fills before use

  // Aktuelle Dateigroesse ermitteln
  NewSize := 0;
  if FindFirst(FFileName, faAnyFile, SR) = 0 then
  begin
    NewSize := SR.Size;
    FindClose(SR);
  end;
  if NewSize <= FLastSize then Exit;

  Delta := NewSize - FLastSize;

  // Datei oeffnen mit Shared-Read (auch bei gelockten Dateien)
  try
    FS := TFileStream.Create(FFileName, fmOpenRead or fmShareDenyNone);
  except
    Exit;   // Datei gerade nicht lesbar, naechsten Tick abwarten
  end;
  try
    // Zum letzten bekannten Offset springen, nur neue Bytes lesen
    FS.Position := FLastSize;
    SetLength(Buf, Delta);
    FS.ReadBuffer(Buf[1], Delta);
  finally
    FS.Free;
  end;

  FLastSize := NewSize;

  // Ggf. Restzeile vom letzten Tick voranstellen
  S := FPartial + string(Buf);
  FPartial := '';

  // Zeilenweise aufteilen und ausgeben
  LineStart := 1;
  for P := 1 to Length(S) do
  begin
    if S[P] = #10 then
    begin
      // Zeile extrahieren (CR vor LF entfernen)
      if (P > LineStart) and (S[P - 1] = #13) then
        Buf := Copy(S, LineStart, P - LineStart - 1)
      else
        Buf := Copy(S, LineStart, P - LineStart);
      Inc(FLastLineNo);
      if Assigned(FOnNewLine) then
        FOnNewLine(string(Buf), FLastLineNo);
      LineStart := P + 1;
    end;
  end;

  // Unvollstaendige letzte Zeile fuer naechsten Tick aufheben
  if LineStart <= Length(S) then
    FPartial := Copy(S, LineStart, MaxInt);
end;

end.
