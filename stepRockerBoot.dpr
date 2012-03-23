program stepRockerBoot;

uses
  Forms,
  stepRockerBootMain in 'stepRockerBootMain.pas' {FormMain},
  TMCLMsgBox in 'TMCLMsgBox.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.Title := 'Firmware Downloader';
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
