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
    // Delimiter-Modus
    Delimiter     : Char;
    FieldRoles    : array[0..MAX_CUSTOM_FIELDS-1] of TCustomFieldRole;
    FieldCount    : Integer;
    // Positions-Modus (1-basiert, 0 = nicht vorhanden)
    TSStart       : Integer;
    TSLen         : Integer;
    LvlStart      : Integer;
    LvlLen        : Integer;
    SrcStart      : Integer;
    SrcLen        : Integer;
    // Timestamp-Format, z.B. 'YYYY/MM/DD hh:nn:ss.zzz'
    TimestampFmt  : string;
  end;

  TLogEntry = record
    TimeStamp : TDateTime;
    Level     : TLogLevel;
    Source    : string;
    Thread    : string;
    Raw       : string;
    LineNo    : Integer;
    Format    : TLogFormat;
  end;

  TLogEntryArray = array of TLogEntry;
  PLogEntry      = ^TLogEntry;

const
  LogFormatNames: array[TLogFormat] of string = (
    'Unbekannt', 'Plain', 'Log4x (log4j/log4net/log4pascal)',
    'Apache Access', 'Nginx Access', 'Syslog', 'CSV', 'JSON',
    'IIS W3C', 'Custom (user-defined)');

  CustomFieldRoleNames: array[TCustomFieldRole] of string = (
    'Ignore', 'Timestamp', 'Level', 'Source', 'Thread');

implementation
end.
