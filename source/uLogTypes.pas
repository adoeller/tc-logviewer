unit uLogTypes;

{$mode objfpc}{$H+}

interface

const
  MAX_CUSTOM_FIELDS = 8;

type
  TLogLevel = (lError, lWarn, lInfo, lDebug, lTrace, lCustom);
  TLevelSet  = set of TLogLevel;

  TLogFormat = (lfUnknown, lfPlain, lfLog4x, lfApache, lfNginx,
                lfSyslog, lfCSV, lfJSON, lfIIS, lfCustom);

  TCustomFormatMode = (cfmDelimiter, cfmPosition);

  TCustomFieldRole = (cfrIgnore, cfrTimestamp, cfrLevel, cfrSource, cfrThread);

  TCustomFormatConfig = record
    Mode          : TCustomFormatMode;
    Delimiter     : Char;
    FieldRoles    : array[0..MAX_CUSTOM_FIELDS-1] of TCustomFieldRole;
    FieldCount    : Integer;
    TSStart       : Integer;
    TSLen         : Integer;
    LvlStart      : Integer;
    LvlLen        : Integer;
    SrcStart      : Integer;
    SrcLen        : Integer;
    TimestampFmt  : string;
  end;

  { Kein einziges Managed-Feld mehr.
    SetLength / FFiltered := nil  →  O(1), kein Finalizer-Aufruf pro Zeile. }
  TLogEntry = record
    TimeStamp  : TDateTime;   // 8
    RawOffset  : Integer;     // 4  – Byte-Offset in TLogList.FRawBuf (0-basiert)
    RawLen     : Integer;     // 4  – Laenge der Rohzeile in Bytes
    Level      : TLogLevel;   // 1
    LineNo     : Integer;     // 4
    Format     : TLogFormat;  // 1
  end;                        // ≈ 22 Bytes, vollständig unmanaged

  TLogEntryArray = array of TLogEntry;
  PLogEntry      = ^TLogEntry;

const
  LogFormatNames: array[TLogFormat] of string = (
    'Unbekannt', 'Plain', 'Log4x',
    'Apache Access', 'Nginx Access', 'Syslog', 'CSV', 'JSON',
    'IIS W3C', 'Custom (user-defined)');

  CustomFieldRoleNames: array[TCustomFieldRole] of string = (
    'Ignore', 'Timestamp', 'Level', 'Source', 'Thread');

implementation
end.
