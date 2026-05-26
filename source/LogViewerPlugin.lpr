library LogViewerPlugin;

{$mode objfpc}{$H+}
{$R *.res}

uses
  Windows,
  SysUtils,
  listplug       in 'listplug.pas',
  uWLXTypes      in 'uWLXTypes.pas',
  uLogTypes      in 'uLogTypes.pas',
  uLogModel      in 'uLogModel.pas',
  uLogFilter     in 'uLogFilter.pas',
  uSettings      in 'uSettings.pas',
  uLogParser     in 'uLogParser.pas',
  uLogLoader     in 'uLogLoader.pas',
  uWin32LogWindow in 'uWin32LogWindow.pas',
  uWLXExports    in 'uWLXExports.pas';

exports
  ListLoad,
  ListLoadW,
  ListCloseWindow,
  ListGetDetectString,
  ListSetDefaultParams,
  ListSendCommand,
  ListSearchText,
  ListSearchTextW,
  ListSearchDialog;

begin
end.
