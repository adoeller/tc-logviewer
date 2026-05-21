program LogViewer;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, datetimectrls,
  uMain, uSettings, uFormats;

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  TFormats.RegisterDefaultFormats;
  Application.Run;
end.
