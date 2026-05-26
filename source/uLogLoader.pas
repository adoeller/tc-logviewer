unit uLogLoader;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, uLogTypes, uLogModel, uLogParser, uSettings;

type
  TLoadedLog = class
  private
    FLog: TLogList;
    FFormat: TLogFormat;
    FFileSize: Int64;
    FMaxVisibleChars: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function LoadFromFile(const AFilename: string): Boolean;
    property Log: TLogList read FLog;
    property Format: TLogFormat read FFormat;
    property FileSize: Int64 read FFileSize;
    property MaxVisibleChars: Integer read FMaxVisibleChars;
  end;

implementation

const
  READ_BUF_SIZE = 131072;
  DETECT_LINES = 50;

constructor TLoadedLog.Create;
begin
  inherited Create;
  FLog := TLogList.Create;
  FFormat := lfUnknown;
  FFileSize := 0;
  FMaxVisibleChars := 0;
end;

destructor TLoadedLog.Destroy;
begin
  FLog.Free;
  inherited Destroy;
end;

function TLoadedLog.LoadFromFile(const AFilename: string): Boolean;
var
  FS: TFileStream;
  RawBuf: array[0..READ_BUF_SIZE - 1] of Byte;
  BytesRead: Integer;
  P: Integer;
  LineNo: Integer;
  Line: string;
  Carry: AnsiString;
  CarryLen: Integer;
  Lines: TStringArray;
  DetectDone: Boolean;
  LineStart: Integer;
  LineEnd: Integer;
  LFileSize: Int64;
  EstLines: Integer;
  Idx: Integer;

  procedure EmitLine(ABuf: PAnsiChar; ALen: Integer); inline;
  var
    RawOff: Integer;
  begin
    if (ALen > 0) and (ABuf[ALen - 1] = #13) then
      Dec(ALen);
    Inc(LineNo);

    if ALen > FMaxVisibleChars then
      FMaxVisibleChars := ALen;

    RawOff := FLog.AppendRaw(ABuf, ALen);

    if (not DetectDone) and (LineNo <= DETECT_LINES) then
    begin
      SetString(Line, ABuf, ALen);
      Lines[LineNo - 1] := Line;
    end;

    if (not DetectDone) and (LineNo = DETECT_LINES) then
    begin
      if AppSettings.AutoDetectFormat then
        FFormat := TLogParser.DetectFormat(Lines)
      else
        FFormat := AppSettings.ForceFormat;
      DetectDone := True;
      SetLength(Lines, 0);
      Line := '';
    end;

    Idx := FLog.PrepareAdd;
    if DetectDone and (Line = '') then
      SetString(Line, ABuf, ALen);
    TLogParser.ParseLine(Line, LineNo, FFormat, FLog.Slot(Idx)^);
    FLog.Slot(Idx)^.RawOffset := RawOff;
    FLog.Slot(Idx)^.RawLen := ALen;
    FLog.CommitAdd;
    Line := '';
  end;

begin
  Result := False;
  FLog.Clear;
  FFileSize := 0;
  FFormat := lfUnknown;
  FMaxVisibleChars := 0;

  try
    FS := TFileStream.Create(AFilename, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;

  try
    LFileSize := FS.Size;
    EstLines := LFileSize div 80 + 1024;
    FLog.EnsureCapacity(EstLines + EstLines div 10 + 256);
    FLog.ReserveRaw(LFileSize);

    SetLength(Lines, DETECT_LINES);
    LineNo := 0;
    DetectDone := False;
    Carry := '';
    CarryLen := 0;

    if not AppSettings.AutoDetectFormat then
    begin
      FFormat := AppSettings.ForceFormat;
      DetectDone := True;
      SetLength(Lines, 0);
    end;

    repeat
      BytesRead := FS.Read(RawBuf[0], READ_BUF_SIZE);
      if BytesRead = 0 then
        Break;

      LineStart := 0;
      for P := 0 to BytesRead - 1 do
      begin
        if RawBuf[P] = 10 then
        begin
          LineEnd := P;
          if CarryLen > 0 then
          begin
            SetLength(Carry, CarryLen + (LineEnd - LineStart));
            if LineEnd > LineStart then
              Move(RawBuf[LineStart], Carry[CarryLen + 1], LineEnd - LineStart);
            EmitLine(PAnsiChar(Carry), CarryLen + (LineEnd - LineStart));
            Carry := '';
            CarryLen := 0;
          end
          else
            EmitLine(@PAnsiChar(@RawBuf[0])[LineStart], LineEnd - LineStart);
          LineStart := P + 1;
        end;
      end;

      if LineStart < BytesRead then
      begin
        SetLength(Carry, CarryLen + (BytesRead - LineStart));
        Move(RawBuf[LineStart], Carry[CarryLen + 1], BytesRead - LineStart);
        CarryLen := CarryLen + (BytesRead - LineStart);
      end;
    until BytesRead < READ_BUF_SIZE;

    if CarryLen > 0 then
      EmitLine(PAnsiChar(Carry), CarryLen);

    if not DetectDone then
    begin
      if AppSettings.AutoDetectFormat then
      begin
        SetLength(Lines, Min(LineNo, DETECT_LINES));
        FFormat := TLogParser.DetectFormat(Lines);
        SetLength(Lines, 0);
      end
      else
        FFormat := AppSettings.ForceFormat;
    end;

    FFileSize := LFileSize;
    Result := True;
  finally
    FS.Free;
  end;
end;

end.
