unit uLogParser;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, StrUtils, DateUtils, Math, uLogTypes, uSettings;

type
  TLogParser = class
  public
    class function DetectFormat(const ALines: TStringArray): TLogFormat; static;
    class procedure ParseLine(const ALine: string; ALineNo: Integer;
      AFormat: TLogFormat; out AResult: TLogEntry); static;
  private
    class procedure ParsePlain  (const ALine: string; out AResult: TLogEntry); static;
    class procedure ParseLog4x  (const ALine: string; out AResult: TLogEntry); static;
    class procedure ParseApache (const ALine: string; out AResult: TLogEntry); static;
    class procedure ParseNginx  (const ALine: string; out AResult: TLogEntry); static;
    class procedure ParseSyslog (const ALine: string; out AResult: TLogEntry); static;
    class procedure ParseCSV    (const ALine: string; out AResult: TLogEntry); static;
    class procedure ParseJSON   (const ALine: string; out AResult: TLogEntry); static;
    class procedure ParseIIS    (const ALine: string; out AResult: TLogEntry); static;
    class procedure ParseCustom (const ALine: string; out AResult: TLogEntry); static;
    class function ParseTimestampByFormat(const AValue, AFmt: string;
      out DT: TDateTime): Boolean; static;
    class function LevelFromStr(const S: string): TLogLevel; static;
    class function KeywordScanLevel(const ALine: string;
      const AUpper: string): TLogLevel; static;
    class function IsLog4xTimestamp(const L: string): Boolean; static;
    class function TryParseLog4xDate(const S: string; out DT: TDateTime): Boolean; static;
    class function TryParseBracketDate(const S: string; out DT: TDateTime;
      out PrefixLen: Integer): Boolean; static;
    class function TryParseApacheDate(const S: string; out DT: TDateTime): Boolean; static;
    class function TryParseSyslogDate(const S: string; out DT: TDateTime): Boolean; static;
    class function TryParseIISDate(const D, T: string; out DT: TDateTime): Boolean; static;
  end;

implementation

{ Inline-Helfer: 2 Zeichen ab Position P als Integer, -1 bei Fehler }
function Int2(const S: string; P: Integer): Integer; inline;
var A, B: Integer;
begin
  A := Ord(S[P])   - Ord('0');
  B := Ord(S[P+1]) - Ord('0');
  if (Cardinal(A) <= 9) and (Cardinal(B) <= 9) then
    Result := A * 10 + B
  else
    Result := -1;
end;

{ Inline-Helfer: 4 Zeichen ab Position P als Integer, -1 bei Fehler }
function Int4(const S: string; P: Integer): Integer; inline;
var A, B, C, D: Integer;
begin
  A := Ord(S[P])   - Ord('0');
  B := Ord(S[P+1]) - Ord('0');
  C := Ord(S[P+2]) - Ord('0');
  D := Ord(S[P+3]) - Ord('0');
  if (Cardinal(A) <= 9) and (Cardinal(B) <= 9)
     and (Cardinal(C) <= 9) and (Cardinal(D) <= 9) then
    Result := A * 1000 + B * 100 + C * 10 + D
  else
    Result := -1;
end;

{ Validiert Date/Time-Werte ohne Exception }
function TryEncodeCheck(Y, Mo, D, H, Mi, Sec: Integer;
  out DT: TDateTime): Boolean; inline;
begin
  Result := (Y >= 1) and (Y <= 9999) and (Mo >= 1) and (Mo <= 12)
    and (D >= 1) and (D <= 31) and (H >= 0) and (H <= 23)
    and (Mi >= 0) and (Mi <= 59) and (Sec >= 0) and (Sec <= 59);
  if Result then
  try
    DT := EncodeDateTime(Y, Mo, D, H, Mi, Sec, 0);
  except
    Result := False;
  end;
end;

class function TLogParser.LevelFromStr(const S: string): TLogLevel;
var U: string;
begin
  U := UpperCase(Trim(S));
  if (U = 'ERROR') or (U = 'ERR') or (U = 'FATAL') or (U = 'CRITICAL') or (U = 'CRIT') then
    Result := lError
  else if (U = 'WARN') or (U = 'WARNING') then
    Result := lWarn
  else if (U = 'INFO') or (U = 'INFORMATION') then
    Result := lInfo
  else if (U = 'DEBUG') or (U = 'DBG') then
    Result := lDebug
  else if (U = 'TRACE') or (U = 'VERBOSE') or (U = 'VRB') then
    Result := lTrace
  else
    Result := lCustom;
end;

// Prüft ob eine Zeile mit einem Timestamp beginnt: YYYY-MM-DD oder YYYY/MM/DD
class function TLogParser.IsLog4xTimestamp(const L: string): Boolean;
begin
  Result := (Length(L) >= 19)
    and (L[1] >= '1') and (L[1] <= '2')   // Jahr 1xxx-2xxx
    and ((L[5] = '-') or (L[5] = '/'))
    and ((L[8] = '-') or (L[8] = '/'))
    and ((L[11] = ' ') or (L[11] = 'T'))
    and (L[14] = ':')
    and (L[17] = ':');
end;

class function TLogParser.TryParseLog4xDate(const S: string; out DT: TDateTime): Boolean;
var
  Y, Mo, D, H, Mi, Sec: Integer;
begin
  Result := False;
  if Length(S) < 19 then Exit;
  if not ((S[5] = '-') or (S[5] = '/')) then Exit;
  if not ((S[8] = '-') or (S[8] = '/')) then Exit;
  if not ((S[11] = ' ') or (S[11] = 'T')) then Exit;
  if (S[14] <> ':') or (S[17] <> ':') then Exit;
  Y   := Int4(S, 1);  if Y   < 0 then Exit;
  Mo  := Int2(S, 6);  if Mo  < 0 then Exit;
  D   := Int2(S, 9);  if D   < 0 then Exit;
  H   := Int2(S, 12); if H   < 0 then Exit;
  Mi  := Int2(S, 15); if Mi  < 0 then Exit;
  Sec := Int2(S, 18); if Sec < 0 then Exit;
  Result := TryEncodeCheck(Y, Mo, D, H, Mi, Sec, DT);
end;

class function TLogParser.TryParseApacheDate(const S: string; out DT: TDateTime): Boolean;
const
  Months: array[1..12] of string = (
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
var
  Parts: TStringArray;
  m, i : Integer;
begin
  Result := False;
  Parts := S.Split(['/', ':', ' ']);
  if Length(Parts) < 6 then Exit;
  m := 0;
  for i := 1 to 12 do
    if CompareText(Parts[1], Months[i]) = 0 then begin m := i; Break; end;
  if m = 0 then Exit;
  try
    DT := EncodeDateTime(StrToInt(Parts[2]), m, StrToInt(Parts[0]),
                         StrToInt(Parts[3]), StrToInt(Parts[4]),
                         StrToInt(Parts[5]), 0);
    Result := True;
  except
    Result := False;
  end;
end;

class function TLogParser.TryParseSyslogDate(const S: string; out DT: TDateTime): Boolean;
const
  Months: array[1..12] of string = (
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
var
  Parts : TStringArray;
  m, i  : Integer;
begin
  Result := False;
  Parts  := S.Split([' ']);
  if Length(Parts) < 3 then Exit;
  m := 0;
  for i := 1 to 12 do
    if CompareText(Parts[0], Months[i]) = 0 then begin m := i; Break; end;
  if m = 0 then Exit;
  if Length(Parts[2]) < 8 then Exit;
  try
    DT := EncodeDateTime(YearOf(Now), m, StrToInt(Trim(Parts[1])),
                         StrToInt(Copy(Parts[2],1,2)),
                         StrToInt(Copy(Parts[2],4,2)),
                         StrToInt(Copy(Parts[2],7,2)), 0);
    Result := True;
  except
    Result := False;
  end;
end;

class function TLogParser.TryParseIISDate(const D, T: string; out DT: TDateTime): Boolean;
var
  Y, Mo, Da, H, Mi, Sec: Integer;
begin
  Result := False;
  if (Length(D) < 10) or (Length(T) < 8) then Exit;
  Y   := Int4(D, 1);  if Y   < 0 then Exit;
  Mo  := Int2(D, 6);  if Mo  < 0 then Exit;
  Da  := Int2(D, 9);  if Da  < 0 then Exit;
  H   := Int2(T, 1);  if H   < 0 then Exit;
  Mi  := Int2(T, 4);  if Mi  < 0 then Exit;
  Sec := Int2(T, 7);  if Sec < 0 then Exit;
  Result := TryEncodeCheck(Y, Mo, Da, H, Mi, Sec, DT);
end;

// ── Format-Erkennung ─────────────────────────────────────────────────────────
// Reihenfolge wichtig: Log4x vor IIS testen (beide haben YYYY-MM-DD)

class function TLogParser.DetectFormat(const ALines: TStringArray): TLogFormat;
var
  i, cLog4x, cApache, cNginx, cSyslog, cCSV, cJSON, cIIS: Integer;
  L: string;
  BestCount: Integer;
begin
  cLog4x := 0; cApache := 0; cNginx := 0; cSyslog := 0;
  cCSV   := 0; cJSON   := 0; cIIS   := 0;

  for i := 0 to Min(High(ALines), 49) do
  begin
    L := Trim(ALines[i]);
    if L = '' then Continue;

    // Syslog mit RFC-3164 Priority-Prefix: <nnn> (Ziffern zwischen < und >)
    if (Length(L) >= 4) and (L[1] = '<')
       and (L[2] >= '0') and (L[2] <= '9')
       and (Pos('>', L) >= 3) and (Pos('>', L) <= 5) then
    begin
      Inc(cSyslog);
      Continue;
    end;

    // Log4x / CSV / IIS: alle beginnen mit YYYY-MM-DD oder YYYY/MM/DD
    if IsLog4xTimestamp(L) then
    begin
      // CSV: Komma-getrennte Level-Keywords (,ERROR, oder ,WARN, etc.)
      if (Pos(',ERROR,', L) + Pos(',WARN,', L) + Pos(',INFO,', L) +
          Pos(',DEBUG,', L) + Pos(',TRACE,', L) +
          Pos(',WARNING,', L) + Pos(',FATAL,', L) > 0)
      then
        Inc(cCSV)
      // Log4x: Leerzeichen-getrennte Level-Keywords
      else if (Pos(' ERROR ', L) + Pos(' WARN ', L) + Pos(' INFO ', L) +
          Pos(' DEBUG ', L) + Pos(' TRACE ', L) +
          Pos('[ERROR]', L) + Pos('[WARN]', L) + Pos('[INFO]', L) +
          Pos('[DEBUG]', L) + Pos('[TRACE]', L) +
          Pos('[WARNING]', L) + Pos('[FATAL]', L) > 0)
      then
        Inc(cLog4x)
      else
        // IIS hat auch YYYY-MM-DD aber ohne Level-Wort und ohne Kommas
        Inc(cIIS);
      Continue;
    end;

    // IIS Kommentarzeilen
    if (Length(L) > 0) and (L[1] = '#') then begin Inc(cIIS); Continue; end;

    // Apache: IP - - [DD/Mon/YYYY:
    if (Pos(' - - [', L) > 0) and (Pos('/', L) > 0) then Inc(cApache);

    // Nginx: HTTP-Methode in Anführungszeichen
    if (Pos('"GET ', L) + Pos('"POST ', L) + Pos('"HEAD ', L) + Pos('"PUT ', L) > 0)
       and (Pos(' HTTP/', L) > 0) then Inc(cNginx);

    // Syslog ohne Priority-Prefix: Mon DD HH:MM:SS
    if (Length(L) >= 16) and (L[4] = ' ')
       and (L[7] = ' ')
       and (Pos(':', L) > 0)
       and not ((L[1] >= '0') and (L[1] <= '9'))
    then Inc(cSyslog);

    // JSON
    if (Length(L) > 0) and (L[1] = '{')
       and (Pos('"level"', L) + Pos('"Level"', L) + Pos('"severity"', L) > 0)
    then Inc(cJSON);

    // CSV: Komma-getrennte Felder (>= 3 Kommas = 4 Felder)
    if WordCount(L, [',']) >= 4 then Inc(cCSV);
  end;

  // Bestes Format wählen – Log4x hat Priorität
  Result := lfPlain;
  BestCount := 3;  // Mindestschwelle

  if cLog4x > BestCount  then begin Result := lfLog4x;  BestCount := cLog4x;  end;
  if cJSON   > BestCount then begin Result := lfJSON;    BestCount := cJSON;   end;
  if cApache > BestCount then begin Result := lfApache;  BestCount := cApache; end;
  if cNginx  > BestCount then begin Result := lfNginx;   BestCount := cNginx;  end;
  if cIIS    > BestCount then begin Result := lfIIS;     BestCount := cIIS;    end;
  if cSyslog > BestCount then begin Result := lfSyslog;  BestCount := cSyslog; end;
  if cCSV    > BestCount then begin Result := lfCSV;     BestCount := cCSV;    end;
end;

// ── Log4x Parser – robust für alle gängigen Varianten ───────────────────────
// Unterstützte Formate:
//   2024-01-15 12:34:56,789 [ERROR] (Thread) MyClass - Message
//   2024-01-15 12:34:56.789 ERROR  [Thread] MyClass - Message
//   2024-01-15T12:34:56 INFO  Message
//   2024-01-15 12:34:56 WARN Message

class procedure TLogParser.ParseLog4x(const ALine: string; out AResult: TLogEntry);
var
  Rest, LvlStr: string;
  P1, P2: Integer;
  DT: TDateTime;
begin
  AResult.Format    := lfLog4x;
  AResult.Level     := lCustom;
  AResult.Source    := '';
  AResult.Thread    := '';
  AResult.TimeStamp := 0;

  if not TryParseLog4xDate(ALine, DT) then Exit;
  AResult.TimeStamp := DT;

  // Ab Position 20 weiterlesen (nach YYYY-MM-DD HH:MM:SS)
  Rest := Trim(Copy(ALine, 20, MaxInt));

  // Millisekunden überspringen: ,789 oder .789
  if (Length(Rest) > 3) and ((Rest[1] = ',') or (Rest[1] = '.'))
     and (Rest[2] >= '0') and (Rest[2] <= '9')
  then
    Rest := Trim(Copy(Rest, 5, MaxInt));

  if Rest = '' then Exit;

  // Level extrahieren: [LEVEL] oder LEVEL
  LvlStr := '';
  if Rest[1] = '[' then
  begin
    P2 := Pos(']', Rest);
    if P2 > 1 then
    begin
      LvlStr := Trim(Copy(Rest, 2, P2 - 2));
      Rest   := Trim(Copy(Rest, P2 + 1, MaxInt));
    end;
  end
  else
  begin
    // Wort bis zum ersten Leerzeichen
    P1 := Pos(' ', Rest);
    if P1 > 1 then
    begin
      LvlStr := Trim(Copy(Rest, 1, P1 - 1));
      Rest   := Trim(Copy(Rest, P1 + 1, MaxInt));
    end
    else
      LvlStr := Rest;
  end;
  AResult.Level := LevelFromStr(LvlStr);

  // Optionaler Thread: [Thread] oder (Thread)
  if Length(Rest) > 0 then
  begin
    if (Rest[1] = '[') then
    begin
      P2 := Pos(']', Rest);
      if P2 > 1 then
      begin
        AResult.Thread := Trim(Copy(Rest, 2, P2 - 2));
        Rest := Trim(Copy(Rest, P2 + 1, MaxInt));
      end;
    end
    else if (Rest[1] = '(') then
    begin
      P2 := Pos(')', Rest);
      if P2 > 1 then
      begin
        AResult.Thread := Trim(Copy(Rest, 2, P2 - 2));
        Rest := Trim(Copy(Rest, P2 + 1, MaxInt));
      end;
    end;
  end;

  // " - " als Trenner: Source vor dem Trenner
  P1 := Pos(' - ', Rest);
  if P1 > 0 then
    AResult.Source := Trim(Copy(Rest, 1, P1 - 1));
end;

class procedure TLogParser.ParseApache(const ALine: string; out AResult: TLogEntry);
var
  P1, P2: Integer;
  DateStr, Code: string;
  DT: TDateTime;
begin
  AResult.Format    := lfApache;
  AResult.Level     := lInfo;
  AResult.Source    := '';
  AResult.Thread    := '';
  AResult.TimeStamp := 0;

  P1 := Pos(' ', ALine);
  if P1 > 0 then AResult.Source := Copy(ALine, 1, P1 - 1);

  P1 := Pos('[', ALine);
  P2 := Pos(']', ALine);
  if (P1 > 0) and (P2 > P1) then
  begin
    DateStr := Copy(ALine, P1 + 1, P2 - P1 - 1);
    P1 := Pos(' ', DateStr);
    if P1 > 0 then DateStr := Copy(DateStr, 1, P1 - 1);
    TryParseApacheDate(DateStr, DT);
    AResult.TimeStamp := DT;
  end;

  P1 := Pos('"', ALine);
  P2 := Pos('"', ALine, P1 + 1);
  if (P1 > 0) and (P2 > P1) then
  begin
    Code := Trim(Copy(ALine, P2 + 2, 3));
    if (Length(Code) >= 1) and (Code[1] = '5') then AResult.Level := lError
    else if (Length(Code) >= 1) and (Code[1] = '4') then AResult.Level := lWarn;
  end;
end;

class procedure TLogParser.ParseNginx(const ALine: string; out AResult: TLogEntry);
begin
  ParseApache(ALine, AResult);
  AResult.Format := lfNginx;
end;

class procedure TLogParser.ParseSyslog(const ALine: string; out AResult: TLogEntry);
var
  Parts : TStringArray;
  DT    : TDateTime;
  DateStr, MsgPart, Line: string;
  P     : Integer;
begin
  AResult.Format    := lfSyslog;
  AResult.Level     := lInfo;
  AResult.Source    := '';
  AResult.Thread    := '';
  AResult.TimeStamp := 0;

  // RFC-3164 Priority-Prefix <nnn> entfernen
  Line := ALine;
  Parts := nil;
  if (Length(Line) >= 3) and (Line[1] = '<') then
  begin
    P := Pos('>', Line);
    if (P >= 3) and (P <= 5) then
      Line := Copy(Line, P + 1, MaxInt);
  end;

  Parts := Line.Split([' '], 6);
  if Length(Parts) < 5 then Exit;
  DateStr := Parts[0] + ' ' + Parts[1] + ' ' + Parts[2];
  TryParseSyslogDate(DateStr, DT);
  AResult.TimeStamp := DT;
  AResult.Source    := Parts[3];
  MsgPart := '';
  if Length(Parts) >= 5 then MsgPart := Parts[4];
  if Length(Parts) >= 6 then MsgPart := MsgPart + ' ' + Parts[5];
  if (Pos('error', LowerCase(MsgPart)) > 0) or (Pos('fail', LowerCase(MsgPart)) > 0) then
    AResult.Level := lError
  else if Pos('warn', LowerCase(MsgPart)) > 0 then
    AResult.Level := lWarn
  else if Pos('debug', LowerCase(MsgPart)) > 0 then
    AResult.Level := lDebug;
end;

class procedure TLogParser.ParseCSV(const ALine: string; out AResult: TLogEntry);
  function SplitCSV(const S: string): TStringArray;
  var
    Parts : TStringArray;
    Cur   : string;
    I     : Integer;
    InQ   : Boolean;
  begin
    Parts := nil;
    SetLength(Parts, 0);
    Cur := '';
    InQ := False;
    I := 1;
    while I <= Length(S) do
    begin
      if S[I] = '"' then
      begin
        if InQ and (I < Length(S)) and (S[I+1] = '"') then
        begin
          Cur := Cur + '"';
          Inc(I, 2);
          Continue;
        end;
        InQ := not InQ;
        Inc(I);
        Continue;
      end;
      if (S[I] = ',') and not InQ then
      begin
        SetLength(Parts, Length(Parts) + 1);
        Parts[High(Parts)] := Trim(Cur);
        Cur := '';
        Inc(I);
        Continue;
      end;
      Cur := Cur + S[I];
      Inc(I);
    end;
    SetLength(Parts, Length(Parts) + 1);
    Parts[High(Parts)] := Trim(Cur);
    Result := Parts;
  end;
var
  Fields : TStringArray;
  DT     : TDateTime;
begin
  AResult.Format    := lfCSV;
  AResult.Level     := lCustom;
  AResult.Source    := '';
  AResult.Thread    := '';
  AResult.TimeStamp := 0;
  Fields := SplitCSV(ALine);
  if Length(Fields) = 0 then Exit;
  if not TryParseLog4xDate(Trim(Fields[0]), DT) then
  begin
    try
      DT := StrToTimeDef(Trim(Fields[0]), -1);
      if DT >= 0 then AResult.TimeStamp := DT;
    except end;
  end
  else
    AResult.TimeStamp := DT;
  if Length(Fields) >= 2 then AResult.Level  := LevelFromStr(Trim(Fields[1]));
  if Length(Fields) >= 3 then AResult.Source := Trim(Fields[2]);
end;

class procedure TLogParser.ParseJSON(const ALine: string; out AResult: TLogEntry);
  function JSONValue(const AJSON, AKey: string): string;
  var P1, P2: Integer;
  begin
    Result := '';
    P1 := Pos('"' + AKey + '"', AJSON);
    if P1 = 0 then Exit;
    Inc(P1, Length(AKey) + 2);
    while (P1 <= Length(AJSON)) and (AJSON[P1] in [':', ' ']) do Inc(P1);
    if P1 > Length(AJSON) then Exit;
    if AJSON[P1] = '"' then
    begin
      Inc(P1);
      P2 := Pos('"', AJSON, P1);
      if P2 > P1 then Result := Copy(AJSON, P1, P2 - P1);
    end;
  end;
var
  TS  : string;
  DT  : TDateTime;
begin
  AResult.Format    := lfJSON;
  AResult.Level     := lCustom;
  AResult.Source    := '';
  AResult.Thread    := '';
  AResult.TimeStamp := 0;
  TS := JSONValue(ALine, 'timestamp');
  if TS = '' then TS := JSONValue(ALine, 'time');
  if TS = '' then TS := JSONValue(ALine, '@timestamp');
  if (TS <> '') and TryParseLog4xDate(TS, DT) then AResult.TimeStamp := DT;
  AResult.Level   := LevelFromStr(JSONValue(ALine, 'level'));
  if AResult.Level = lCustom then
    AResult.Level := LevelFromStr(JSONValue(ALine, 'severity'));
  AResult.Source  := JSONValue(ALine, 'logger');
  if AResult.Source = '' then AResult.Source := JSONValue(ALine, 'class');
  AResult.Thread  := JSONValue(ALine, 'thread');
end;

class procedure TLogParser.ParseIIS(const ALine: string; out AResult: TLogEntry);
var
  Fields : TStringArray;
  DT     : TDateTime;
  Code   : string;
begin
  AResult.Format    := lfIIS;
  AResult.Level     := lInfo;
  AResult.Source    := '';
  AResult.Thread    := '';
  AResult.TimeStamp := 0;
  if (Length(ALine) > 0) and (ALine[1] = '#') then Exit;
  Fields := ALine.Split([' ']);
  if Length(Fields) < 2 then Exit;
  if TryParseIISDate(Fields[0], Fields[1], DT) then AResult.TimeStamp := DT;
  if Length(Fields) >= 3 then AResult.Source  := Fields[2];
  if Length(Fields) >= 12 then
  begin
    Code := Fields[11];
    if (Length(Code) >= 1) and (Code[1] = '5') then AResult.Level := lError
    else if (Length(Code) >= 1) and (Code[1] = '4') then AResult.Level := lWarn;
  end;
end;


class function TLogParser.TryParseBracketDate(const S: string; out DT: TDateTime;
  out PrefixLen: Integer): Boolean;
// [MM/DD/YY HH:MM:SS]   = 19 Zeichen  (S[1]='[', S[19]=']')
// [MM/DD/YYYY HH:MM:SS] = 21 Zeichen  (S[1]='[', S[21]=']')
var
  A, B, C, H, Mi, Sec : Integer;
  Y                    : Integer;
  Short                : Boolean;
  Base                 : Integer;  // Offset fuer kurzes/langes Format
begin
  Result    := False;
  PrefixLen := 0;
  if (Length(S) < 19) or (S[1] <> '[') then Exit;

  Short := (S[19] = ']');
  if not Short then
  begin
    if (Length(S) < 21) or (S[21] <> ']') then Exit;
  end;

  // Pruefe Trennzeichen in "[MM/DD/..." ab Position 2
  if (S[4] <> '/') or (S[7] <> '/') then Exit;

  A := Int2(S, 2);  if A < 0 then Exit;  // MM
  B := Int2(S, 5);  if B < 0 then Exit;  // DD

  if Short then
  begin
    C    := Int2(S, 8);  if C < 0 then Exit;
    Base := 10;
    if C < 70 then Y := 2000 + C else Y := 1900 + C;
  end
  else
  begin
    Y    := Int4(S, 8);  if Y < 0 then Exit;
    Base := 12;
  end;

  H   := Int2(S, Base + 1); if H   < 0 then Exit;
  Mi  := Int2(S, Base + 4); if Mi  < 0 then Exit;
  Sec := Int2(S, Base + 7); if Sec < 0 then Exit;

  if not TryEncodeCheck(Y, A, B, H, Mi, Sec, DT) then Exit;
  if Short then PrefixLen := 19 else PrefixLen := 21;
  Result := True;
end;

class procedure TLogParser.ParsePlain(const ALine: string; out AResult: TLogEntry);
var
  LevelStr, Rest : string;
  P1             : Integer;
  DT             : TDateTime;
begin
  AResult.Format    := lfPlain;
  AResult.Level     := lCustom;
  AResult.Source    := '';
  AResult.Thread    := '';
  AResult.TimeStamp := 0;
  if Trim(ALine) = '' then Exit;

  // ── Timestamp erkennen: [MM/DD/YY HH:MM:SS] in eckigen Klammern ─────────
  Rest := TrimLeft(ALine);
  if TryParseBracketDate(Rest, DT, P1) then
  begin
    AResult.TimeStamp := DT;
    // Rest nach "] " auswerten
    Rest := Trim(Copy(Rest, P1 + 1, MaxInt));
    // Level aus erstem Wort (Space oder Tab als Trennzeichen)
    P1 := Pos(' ', Rest);
    if (Pos(#9, Rest) > 0) and ((P1 = 0) or (Pos(#9, Rest) < P1)) then
      P1 := Pos(#9, Rest);
    if P1 > 1 then
      LevelStr := UpperCase(Trim(Copy(Rest, 1, P1 - 1)))
    else
      LevelStr := UpperCase(Trim(Rest));
    if (Length(LevelStr) > 0) and (LevelStr[Length(LevelStr)] = ':') then
      LevelStr := Copy(LevelStr, 1, Length(LevelStr) - 1);
    AResult.Level   := LevelFromStr(LevelStr);
    if AResult.Level = lCustom then
      AResult.Level := KeywordScanLevel(LevelStr, LevelStr);  // bereits UpperCase
    Exit;
  end;

  // ── Timestamp erkennen: YYYY-MM-DD, YYYY/MM/DD oder ISO am Zeilenanfang ──
  if IsLog4xTimestamp(ALine) then
  begin
    if TryParseLog4xDate(ALine, DT) then
    begin
      AResult.TimeStamp := DT;
      // Rest nach Timestamp + optionalen Millisekunden
      Rest := Trim(Copy(ALine, 20, MaxInt));
      if (Length(Rest) > 3) and ((Rest[1] = ',') or (Rest[1] = '.'))
         and (Rest[2] >= '0') and (Rest[2] <= '9') then
        Rest := Trim(Copy(Rest, 5, MaxInt));
      // Erstes Wort des Rests als Level
      P1 := Pos(' ', Rest);
      if P1 > 1 then
        LevelStr := UpperCase(Trim(Copy(Rest, 1, P1 - 1)))
      else
        LevelStr := UpperCase(Trim(Rest));
      AResult.Level   := LevelFromStr(LevelStr);
      Exit;
    end;
  end;

  // ── Nur Zeit am Anfang: HH:MM:SS ────────────────────────────────────────
  if (Length(ALine) >= 8) and (ALine[3] = ':') and (ALine[6] = ':') then
  begin
    try
      DT := StrToTimeDef(Copy(ALine, 1, 8), -1);
      if DT >= 0 then AResult.TimeStamp := DT;
    except end;
    Rest := Trim(Copy(ALine, 9, MaxInt));
  end
  else
    Rest := ALine;

  // ── Erstes Wort als Level ───────────────────────────────────────────────
  P1 := Pos(' ', Rest);
  if P1 > 1 then
    LevelStr := Trim(Copy(Rest, 1, P1 - 1))
  else
    LevelStr := Trim(Rest);

  // Bevorzugt: Keyword in eckigen Klammern, z.B. [INFO] oder [ INFO]
  if (Length(LevelStr) >= 3) and (LevelStr[1] = '[') then
  begin
    P1 := Pos(']', LevelStr);
    if P1 > 2 then
      LevelStr := Trim(Copy(LevelStr, 2, P1 - 2));
  end;

  // "INFO:" / "WARN:" etc. mit Doppelpunkt am Ende
  if (Length(LevelStr) > 0) and (LevelStr[Length(LevelStr)] = ':') then
    LevelStr := Copy(LevelStr, 1, Length(LevelStr) - 1);

  AResult.Level   := LevelFromStr(UpperCase(LevelStr));
end;

class function TLogParser.KeywordScanLevel(const ALine: string;
  const AUpper: string): TLogLevel; static;
// Scannt die komplette Rohzeile nach Level-Keywords + HTTP-Statuscodes
// AUpper ist die vorberechnete UpperCase-Version von ALine
var
  U    : string;
  Code : Integer;
  P    : Integer;
begin
  U := AUpper;

  // ── Standard Log-Level-Keywords ─────────────────────────────────────────
  // ERROR-Klasse: ERROR, ERR, FATAL, CRITICAL, SEVERE
  // EXCEPTION bewusst nicht alleine (kommt in Pfaden/Klassennamen vor)
  if (Pos('ERROR',      U) > 0) or (Pos('FATAL',     U) > 0) or
     (Pos('CRITICAL',   U) > 0) or (Pos('SEVERE',    U) > 0) or
     (Pos(' ERR ',      U) > 0) or
     (Pos(' EXCEPTION:', U) > 0) or (Pos('[EXCEPTION]', U) > 0) then
  begin
    Result := lError; Exit;
  end;

  // WARN-Klasse: WARN, WARNING
  if (Pos('WARN', U) > 0) then
  begin
    Result := lWarn; Exit;
  end;

  // INFO-Klasse: INFO, INFORMATION
  if (Pos(' INFO ',       U) > 0) or (Pos('[INFO]',       U) > 0) or
     (Pos(': INFO',       U) > 0) or (Pos('|INFO|',       U) > 0) or
     (Pos(' INFO:',       U) > 0) or (Pos('INFORMATION',  U) > 0) or
     // Zeilenanfang: "INFO " oder "INFO:"
     (Copy(U, 1, 5) = 'INFO ') or (Copy(U, 1, 5) = 'INFO:') or
     (Copy(U, 1, 6) = '[INFO]') then
  begin
    Result := lInfo; Exit;
  end;

  // DEBUG-Klasse: DEBUG, DBG
  if (Pos('DEBUG', U) > 0) or (Pos(' DBG ', U) > 0) then
  begin
    Result := lDebug; Exit;
  end;

  // TRACE-Klasse: TRACE, VERBOSE, VRB
  if (Pos('TRACE', U) > 0) or (Pos('VERBOSE', U) > 0) or
     (Pos(' VRB ', U) > 0) then
  begin
    Result := lTrace; Exit;
  end;

  // ── HTTP-Methoden + Statuscodes ──────────────────────────────────────────
  // HTTP-Methoden: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, CONNECT
  if (Pos('"GET ',     U) > 0) or (Pos('"POST ',    U) > 0) or
     (Pos('"PUT ',     U) > 0) or (Pos('"PATCH ',   U) > 0) or
     (Pos('"DELETE ',  U) > 0) or (Pos('"HEAD ',    U) > 0) or
     (Pos('"OPTIONS ', U) > 0) or (Pos('"CONNECT ', U) > 0) or
     // ohne Anführungszeichen (IIS, Nginx-Varianten)
     (Pos(' GET ',     U) > 0) or (Pos(' POST ',    U) > 0) or
     (Pos(' PUT ',     U) > 0) or (Pos(' DELETE ',  U) > 0) then
  begin
    // HTTP-Statuscode aus der Zeile lesen: 3-stellige Zahl nach HTTP/x.x
    Code := 0;
    P := Pos(' HTTP/', U);
    if P > 0 then
    begin
      // Format: "... HTTP/1.1" 200 → nach dem schließenden " suchen
      P := Pos('" ', ALine, P);
      if P > 0 then
      begin
        Inc(P, 2);
        // Leerzeichen überspringen
        while (P <= Length(ALine)) and (ALine[P] = ' ') do Inc(P);
        if P + 2 <= Length(ALine) then
          Code := StrToIntDef(Copy(ALine, P, 3), 0);
      end;
    end
    else
    begin
      // IIS/Nginx: Statuscode einfach als letztes 3-stelliges Token
      // Grobe Heuristik: letztes Wort in der Zeile
      P := Length(ALine);
      while (P > 0) and (ALine[P] in ['0'..'9']) do Dec(P);
      if P < Length(ALine) then
        Code := StrToIntDef(Copy(ALine, P + 1, 3), 0);
    end;

    if (Code >= 500) then
      Result := lError
    else if (Code >= 400) then
      Result := lWarn
    else
      Result := lInfo;
    Exit;
  end;

  Result := lCustom;
end;

{ Parst einen Timestamp-String anhand eines Formatmusters.
  Unterstuetzte Platzhalter: YYYY, MM, DD, hh, nn, ss, zzz
  Trennzeichen im Muster (/, -, :, T, ., Leerzeichen) werden uebersprungen.
  Beispiel: 'YYYY/MM/DD hh:nn:ss.zzz' parst '2022/10/17 15:56:58.793' }
class function TLogParser.ParseTimestampByFormat(const AValue, AFmt: string;
  out DT: TDateTime): Boolean;
var
  Y, Mo, D, H, Mi, Sec, Ms : Integer;
  FP, VP, FLen, VLen        : Integer;

  { Liest N Ziffern ab VP aus AValue, gibt -1 bei Fehler }
  function ReadDigits(N: Integer): Integer;
  var
    j, dig: Integer;
  begin
    Result := 0;
    for j := 1 to N do
    begin
      if VP > VLen then begin Result := -1; Exit; end;
      dig := Ord(AValue[VP]) - Ord('0');
      if Cardinal(dig) > 9 then begin Result := -1; Exit; end;
      Result := Result * 10 + dig;
      Inc(VP);
    end;
  end;

begin
  Result := False;
  Y := 1; Mo := 1; D := 1; H := 0; Mi := 0; Sec := 0; Ms := 0;
  FP := 1; VP := 1;
  FLen := Length(AFmt);
  VLen := Length(AValue);

  while FP <= FLen do
  begin
    if VP > VLen then Break;

    if (FP + 3 <= FLen) and (AFmt[FP] = 'Y') and (AFmt[FP+1] = 'Y')
       and (AFmt[FP+2] = 'Y') and (AFmt[FP+3] = 'Y') then
    begin
      Y := ReadDigits(4); if Y < 0 then Exit;
      Inc(FP, 4);
    end
    else if (FP + 2 <= FLen) and (AFmt[FP] = 'z') and (AFmt[FP+1] = 'z')
            and (AFmt[FP+2] = 'z') then
    begin
      Ms := ReadDigits(3); if Ms < 0 then Exit;
      Inc(FP, 3);
    end
    else if (FP + 1 <= FLen) and (AFmt[FP] = 'M') and (AFmt[FP+1] = 'M') then
    begin
      Mo := ReadDigits(2); if Mo < 0 then Exit;
      Inc(FP, 2);
    end
    else if (FP + 1 <= FLen) and (AFmt[FP] = 'D') and (AFmt[FP+1] = 'D') then
    begin
      D := ReadDigits(2); if D < 0 then Exit;
      Inc(FP, 2);
    end
    else if (FP + 1 <= FLen) and (AFmt[FP] = 'h') and (AFmt[FP+1] = 'h') then
    begin
      H := ReadDigits(2); if H < 0 then Exit;
      Inc(FP, 2);
    end
    else if (FP + 1 <= FLen) and (AFmt[FP] = 'n') and (AFmt[FP+1] = 'n') then
    begin
      Mi := ReadDigits(2); if Mi < 0 then Exit;
      Inc(FP, 2);
    end
    else if (FP + 1 <= FLen) and (AFmt[FP] = 's') and (AFmt[FP+1] = 's') then
    begin
      Sec := ReadDigits(2); if Sec < 0 then Exit;
      Inc(FP, 2);
    end
    else
    begin
      // Trennzeichen: Format- und Value-Zeichen ueberspringen
      Inc(FP);
      Inc(VP);
    end;
  end;

  if (Y < 1) or (Y > 9999) or (Mo < 1) or (Mo > 12)
     or (D < 1) or (D > 31) or (H > 23) or (Mi > 59) or (Sec > 59) then
    Exit;
  try
    DT := EncodeDateTime(Y, Mo, D, H, Mi, Sec, Ms);
    Result := True;
  except
    Result := False;
  end;
end;

{ Parst eine Zeile anhand der benutzerdefinierten Formatdefinition }
class procedure TLogParser.ParseCustom(const ALine: string; out AResult: TLogEntry);
var
  Cfg     : TCustomFormatConfig;
  Fields  : TStringArray;
  i, cnt  : Integer;
  S       : string;
  DT      : TDateTime;
  P, Start: Integer;
begin
  AResult.Format    := lfCustom;
  AResult.Level     := lCustom;
  AResult.Source    := '';
  AResult.Thread    := '';
  AResult.TimeStamp := 0;

  Cfg := AppSettings.CustomFormat;
  Fields := nil;

  if Cfg.Mode = cfmDelimiter then
  begin
    // Felder am Trennzeichen aufteilen
    SetLength(Fields, 0);
    Start := 1;
    for P := 1 to Length(ALine) do
    begin
      if ALine[P] = Cfg.Delimiter then
      begin
        SetLength(Fields, Length(Fields) + 1);
        Fields[High(Fields)] := Copy(ALine, Start, P - Start);
        Start := P + 1;
      end;
    end;
    SetLength(Fields, Length(Fields) + 1);
    Fields[High(Fields)] := Copy(ALine, Start, MaxInt);

    cnt := Length(Fields);
    for i := 0 to Cfg.FieldCount - 1 do
    begin
      if i >= cnt then Break;
      S := Trim(Fields[i]);
      case Cfg.FieldRoles[i] of
        cfrTimestamp:
          begin
            if (Cfg.TimestampFmt <> '') then
            begin
              if ParseTimestampByFormat(S, Cfg.TimestampFmt, DT) then
                AResult.TimeStamp := DT;
            end;
          end;
        cfrLevel:
          AResult.Level := LevelFromStr(UpperCase(S));
        cfrSource:
          AResult.Source := S;
        cfrThread:
          AResult.Thread := S;
      end;
    end;
  end
  else
  begin
    // Positions-Modus: feste Start/Laenge
    if (Cfg.TSStart > 0) and (Cfg.TSLen > 0) then
    begin
      S := Copy(ALine, Cfg.TSStart, Cfg.TSLen);
      if Cfg.TimestampFmt <> '' then
      begin
        if ParseTimestampByFormat(S, Cfg.TimestampFmt, DT) then
          AResult.TimeStamp := DT;
      end
      else
      begin
        if TryParseLog4xDate(S, DT) then
          AResult.TimeStamp := DT;
      end;
    end;
    if (Cfg.LvlStart > 0) and (Cfg.LvlLen > 0) then
    begin
      S := Trim(Copy(ALine, Cfg.LvlStart, Cfg.LvlLen));
      AResult.Level := LevelFromStr(UpperCase(S));
    end;
    if (Cfg.SrcStart > 0) and (Cfg.SrcLen > 0) then
      AResult.Source := Trim(Copy(ALine, Cfg.SrcStart, Cfg.SrcLen));
  end;
end;

class procedure TLogParser.ParseLine(const ALine: string; ALineNo: Integer;
  AFormat: TLogFormat; out AResult: TLogEntry);
begin
  case AFormat of
    lfLog4x  : ParseLog4x(ALine, AResult);
    lfApache : ParseApache(ALine, AResult);
    lfNginx  : ParseNginx(ALine, AResult);
    lfSyslog : ParseSyslog(ALine, AResult);
    lfCSV    : ParseCSV(ALine, AResult);
    lfJSON   : ParseJSON(ALine, AResult);
    lfIIS    : ParseIIS(ALine, AResult);
    lfCustom : ParseCustom(ALine, AResult);
  else
    ParsePlain(ALine, AResult);
  end;
  if AResult.Level = lCustom then
    AResult.Level := KeywordScanLevel(ALine, UpperCase(ALine));
  AResult.LineNo := ALineNo;
  AResult.Raw    := ALine;
end;

end.
