unit stepRockerBootMain;
(*  Projekt:  Firmware-Download-Tool für TMCM-1110-Module
              mit neuem Bootloader.

    Unit:     stepRockerBootMain
              Dialog für Firmwaredownload über RS232 oder RS485 (bzw. USB vitual COM port)


    Datum:    27. September 2011 OK


   This program is free software; you can redistribute it and/or modify it
   freely.

   This program is distributed "as is" in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
   or FITNESS FOR A PARTICULAR PURPOSE.
*)


interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ComCtrls, Spin, StrUtils, Math, async32, Registry;

type
  TFormMain = class(TForm)
    GrpFile: TGroupBox;
    BtnLoad: TButton;
    StaticName: TStaticText;
    StaticSize: TStaticText;
    StaticVersion: TStaticText;
    StaticChecksum: TStaticText;
    LblName: TLabel;
    LblSize: TLabel;
    LblVersion: TLabel;
    LblChecksum: TLabel;
    GrpProgram: TGroupBox;
    BtnProgramme: TButton;
    StaticDeviceType: TStaticText;
    StaticProgress: TStaticText;
    LblDeviceType: TLabel;
    LblProgress: TLabel;
    ProgressBar: TProgressBar;
    OpenDialog: TOpenDialog;
    BtnClose: TButton;
    CbCOM: TComboBox;
    LblCOM: TLabel;
    Comm32: TComm32;
    EditAddress: TSpinEdit;
    Label1: TLabel;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure BtnProgrammeClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure BtnLoadClick(Sender: TObject);
    procedure Comm32RxChar(Sender: TObject; Count: Integer);
  private
    ProgData: array[0..262144] of byte;
    ProgStart: cardinal;
    ProgEnd: cardinal;
    ProgChecksum: cardinal;
    DeviceAndVersion: string;
    ARMFlashAddress: cardinal;
    TMCLReply: array[0..8] of byte;
    ReplyReady: boolean;
    function CheckUSB_VID_PID(ADeviceName: string): boolean;
    function CompareWildcard(c1, c2: char):boolean;
    function FindVersionString(Data: array of byte; Mask: string; var Version: string):boolean;
    function SendTMCLAndWait(Addr:word; Cmd: array of byte; Wait: boolean): boolean; overload;
    function SendTMCLAndWait(Addr: word; Cmd: byte; TypePar: byte; MotBankPar: byte;
                              ValuePar: integer; Wait: boolean):boolean; overload;
  end;

var
  FormMain: TFormMain;

implementation
uses TMCLMsgBox;

type
  EHexLoadError=class(Exception);
  EHexCheckError=class(Exception);
  EHexAddressError=class(Exception);

const
  TMCL_BootEraseAll     = 200;
  TMCL_BootWriteBuffer  = 201;
  TMCL_BootWritePage    = 202;
  TMCL_BootGetChecksum  = 203;
  TMCL_BootReadMemory   = 204;
  TMCL_BootStartAppl    = 205;
  TMCL_BootGetInfo      = 206;
  TMCL_BootReset        = 255;
  TMCL_GetVersion       = 136;
  TMCL_Boot = $f2;

  //PIDs für USB virtual COM ports (mit VID $16D0)
  USB_PIDList: array[0..20] of word=($041b, $041c, $041d,
                                     $045d, $045e, $045f, $0460, $0461,
                                     $051a, $051b, $051c, $051d, $051e,
                                     $059e, $059f, $05A0, $05A1,
                                     $650, $651, $652, $653);

{$R *.dfm}

(* Funktion: GetParameterSep
   Sucht aus einer durch ein Trennzeichen getrennten Liste den
   n-ten Wert heraus.
   Parameter: Line: String, der die Liste enthält
              Separator: das Trennzeichen
              Index: Index des Listenelements (beginnend bei 1)
   Rückgabewert: Das Listenelement
                 Leerer String wenn zu wenig Elemente vorhanden sind.
*)
function GetParameterSep(Line, Separator: string; Index: cardinal):string;
var
  i, j: integer;
begin
  for i:=1 to Index do
  begin
    j:=Pos(Separator, Line);
    if j=0 then j:=Length(Line)+1;
    Result:=LeftStr(Line, j-1);
    Line:=RightStr(Line, Length(Line)-j);
  end;
end;


//Test, ob ein USB-Gerät unsere VID und PID hat
function TFormMain.CheckUSB_VID_PID(ADeviceName: string): boolean;
var
  DevName:string;
  i: cardinal;
begin
  Result:=false;
  DevName:=UpperCase(ADeviceName);

  if Pos('VID_16D0', DevName)>0 then
  begin
    for i:=Low(USB_PIDList) to High(USB_PIDList) do
      if Pos('PID_'+IntToHex(USB_PIDList[i], 4), DevName)>0 then
      begin
        Result:=true;
        exit;
      end;
  end
end;

//Vergleich zweier Zeichen mit Wildcard
//Parameter: c1: erstes Zeichen
//           c2: zweites Zeichen, '#' bedeutet eine beliebige Ziffer (0..9)
//Rückgabewert: TRUE bei Übereinstimmung, sonst FALSE.
procedure TFormMain.Comm32RxChar(Sender: TObject; Count: Integer);
begin
  if Count>=9 then //Eine Antwort besteht immer aus 9 Bytes
  begin
    Comm32.Read(TMCLReply, 9);
    ReplyReady:=true;
  end;
end;

function TFormMain.CompareWildcard(c1, c2: char):boolean;
begin
  Result:=((c2='#') and (c1 in ['0'..'9'])) or (c1=c2);
end;

//Suchen eines Versionsstrings in Binärdaten für AVR- und PIC18Fxxx-Prozessoren.
//Parameter: Data: Array mit den Binärdaten
//           Mask: Suchmaske. Dabei bedeutet das Zeichen '#' eine beliebige Ziffer (0..9).
//           Version: Der gefundene Versionsstring wird hier abgelegt.
//Rückgabewert: TRUE wenn erfolgreich, sonst FALSE.
function TFormMain.FindVersionString(Data: array of byte; Mask: string; var Version: string):boolean;
var
  i, j, l: integer;
begin
  i:=1;
  j:=0;
  l:=Length(Mask);
  while (i<262136) and (j<l) do
  begin
    if CompareWildcard(Chr(Data[i+j]), Mask[j+1]) then
    begin
      Version:=Version+Chr(Data[i+j]);
      Inc(j);
    end
    else begin
      Inc(i);
      j:=0;
      Version:='';
    end;
  end;

  Result:=(j=l);
end;

//Senden eines TMCL-Befehls und warten auf Bestätigung vom Modul
//Parameter: Data: Array mit dem Befehl (binär)
//           Len: Anzahl der Bytes des Befehls
//Rückgabewert: TRUE wenn erfolgreich, sonst FALSE.
function TFormMain.SendTMCLAndWait(Addr:word; Cmd: array of byte; Wait:boolean): boolean;
var
  TxData: array[0..8] of byte;
  i: integer;
  t1: cardinal;
begin
  ReplyReady:=false;

  //Prüfsumme berechnen
  TxData[0]:=Addr;
  for i:=0 to 7 do
    TxData[i+1]:=Cmd[Low(Cmd)+i];

  //Senden
  TxData[8]:=0;
  for i:=0 to 7 do TxData[8]:=TxData[8]+TxData[i];
  Comm32.PurgeIn;
  Comm32.Write(TxData, 9);

  //Warten auf Antwort (Empfang erfolgt asynchron)
  if Wait then
  begin
    t1:=GetTickCount;
    repeat
      Application.ProcessMessages;
    until ReplyReady or (Abs(GetTickCount-t1)>4000);
    Result:=ReplyReady;
  end else Result:=true;
end;

function TFormMain.SendTMCLAndWait(Addr: word; Cmd: byte; TypePar: byte;
           MotBankPar: byte; ValuePar: integer; Wait:boolean):boolean;
var
  TxData: array[0..8] of byte;
  i: integer;
  t1: cardinal;
begin
  ReplyReady:=false;

  //Prüfsumme berechnen
  TxData[0]:=Addr;
  TxData[1]:=Cmd;
  TxData[2]:=TypePar;
  TxData[3]:=MotBankPar;
  TxData[4]:=ValuePar shr 24;
  TxData[5]:=ValuePar shr 16;
  TxData[6]:=ValuePar shr 8;
  TxData[7]:=ValuePar and $ff;

  //Senden
  TxData[8]:=0;
  for i:=0 to 7 do TxData[8]:=TxData[8]+TxData[i];
  Comm32.PurgeIn;
  Comm32.Write(TxData, 9);

  //Warten auf Antwort (Empfang erfolgt asynchron)
  if Wait then
  begin
    t1:=GetTickCount;
    repeat
      Application.ProcessMessages;
    until ReplyReady or (Abs(GetTickCount-t1)>17000);
    Result:=ReplyReady;
  end else Result:=true;
end;

//Fenster soll geschlossen werden. Dies wird verhindert, wenn gerade
//ein Download läuft.
procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose:=BtnClose.Enabled;
end;

//Initialisierung
procedure TFormMain.FormCreate(Sender: TObject);
var
  ComPorts: TStringList;
  i: integer;
  j: integer;
  Buffer:array[0..255] of char;
  DevName: string;
  TestHandle: THandle;
  USBPorts: TStringList;
  Dummy: integer;
begin
  //Größenveränderung des Fensters sperren
  DeleteMenu(GetSystemMenu(Handle, false), SC_SIZE, MF_BYCOMMAND);
  DeleteMenu(GetSystemMenu(Handle, false), SC_MAXIMIZE, MF_BYCOMMAND);

  //RS232-Listbox füllen
  ComPorts:=TStringList.Create;
  with TRegistry.Create do
  try
    Rootkey:=HKEY_LOCAL_MACHINE;
    if KeyExists('HARDWARE') and OpenKey('HARDWARE', false) then
        if KeyExists('DEVICEMAP') and OpenKey('DEVICEMAP', false) then
            if KeyExists('SERIALCOMM') and OpenKey('SERIALCOMM', false) then
            begin
              //Alle seriellen Ports einlesen
              GetValueNames(ComPorts);
              for i:=0 to ComPorts.Count-1 do
                ComPorts[i]:=ReadString(ComPorts[i]);

              //Alles entfernen, was nicht wirklich ein serieller Port ist
              //(Name beginnt nicht mit "COM")
              i:=0;
              while i<ComPorts.Count do
              begin
                if LeftStr(ComPorts[i], 3)<>'COM'
                  then ComPorts.Delete(i)
                  else Inc(i);
              end;
            end;
  finally
    Free;
  end;

  //Wenn die obige Methode nicht funktioniert hat, ermitteln wir die vorhandenen
  //COM-Ports auf diese Weise.
  if ComPorts.Count=0 then
    for i:=1 to 255 do
    begin
      StrFmt(Buffer, '\\.\COM%d', [i]);
      TestHandle:=CreateFile(Buffer, GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
      if TestHandle<>INVALID_HANDLE_VALUE then
      begin
        ComPorts.Add(Format('COM%d', [i]));
        CloseHandle(TestHandle);
      end else if GetLastError=ERROR_ACCESS_DENIED then
      begin
        ComPorts.Add(Format('COM%d', [i]));
      end;
    end;

  //Nachsehen, welche davon TMCM-Module mit USB (virtual COM port) sind
  //Zunächst feststellen, welche USB-Geräte über usbser.sys angeschlossen sind
  //(VID/PID)
  USBPorts:=TStringList.Create;
  with TRegistry.Create(KEY_READ) do
  try
    Rootkey:=HKEY_LOCAL_MACHINE;
    if KeyExists('SYSTEM') and OpenKey('SYSTEM', false) then
      if KeyExists('CurrentControlSet') and OpenKey('CurrentControlSet', false) then
        if KeyExists('Services') and OpenKey('Services', false) then
          if KeyExists('usbser') and OpenKey('usbser', false) then
            if KeyExists('Enum') and OpenKey('Enum', false) then
             begin
               //Alle Wertenamen in Stringliste einlesen
               GetValueNames(USBPorts);

               //Die Wertenamen aus unserer Liste entfernen, die nicht aus Ziffern bestehen
               i:=0;
               while i<USBPorts.Count do
                  if TryStrToInt(USBPorts[i], dummy) then
                  begin
                    USBPorts[i]:=ReadString(USBPorts[i]);
                    Inc(i);
                  end else USBPorts.Delete(i);
             end;
  finally
    Free;
  end;

  //Dann alle aus der String-Liste löschen, die nicht unsere VID/PID haben
  i:=0;
  while i<USBPorts.Count do
    if not CheckUSB_VID_PID(USBPorts[i])
      then USBPorts.Delete(i)
      else Inc(i);


  //Nun feststellen, welche COM-Ports den Geräten mit unseren VIDs/PIDs zugewiesen sind
  with TRegistry.Create(KEY_READ) do
  try
    Rootkey:=HKEY_LOCAL_MACHINE;
    for i:=0 to USBPorts.Count-1 do
      if KeyExists('SYSTEM') and OpenKey('SYSTEM', false) then
        if KeyExists('CurrentControlSet') and OpenKey('CurrentControlSet', false) then
          if KeyExists('Enum') and OpenKey('Enum', false) then
            if KeyExists(USBPorts[i]) and OpenKey(USBPorts[i], false) then
            begin
              DevName:=GetParameterSep(ReadString('DeviceDesc'), ' ', 2);
              OpenKey('Device Parameters', false);
              USBPorts[i]:=ReadString('PortName')+'  ['+DevName+']';
              CloseKey;
            end;
  finally
    Free;
  end;

  //Zuletzt diese Informationen mit in die COM-Port-Liste schreiben
  {for i:=0 to USBPorts.Count-1 do
  begin
    j:=ComPorts.IndexOf(GetParameterSep(USBPorts[i], ' ', 1));
    if j>-1 then ComPorts[j]:=USBPorts[i];
  end;}
  for DevName in USBPorts do
  begin
    j:=ComPorts.IndexOf((GetParameterSep(DevName, ' ', 1)));
    if j>-1 then ComPorts[j]:=DevName;
  end;


  //Jetzt suchen wir noch nach USB-2-485-Geräten
  //Dazu zunächst alle FTDI-Geräte suchen und die mit unserer PID ($EF11) ausfiltern
  USBPorts.Clear;
  with TRegistry.Create(KEY_READ) do
  try
    Rootkey:=HKEY_LOCAL_MACHINE;
    if KeyExists('SYSTEM') and OpenKey('SYSTEM', false) then
      if KeyExists('CurrentControlSet') and OpenKey('CurrentControlSet', false) then
        if KeyExists('Enum') and OpenKey('Enum', false) then
          if KeyExists('FTDIBUS') and OpenKey('FTDIBUS', false) then
          begin
            GetKeyNames(USBPorts);
            i:=0;
            while i<USBPorts.Count do
              if (Pos('VID_0403', USBPorts[i])>0) and (Pos('PID_EF11', USBPorts[i])>0)
                then Inc(i)
                else USBPorts.Delete(i);
          end;
  finally
    Free;
  end;

  //nun die COM-Port-Namen der gefundenen USB-2-485-Geräte abfragen
  with TRegistry.Create(KEY_READ) do
  try
    Rootkey:=HKEY_LOCAL_MACHINE;
    for i:=0 to USBPorts.Count-1 do
    begin
      if KeyExists('SYSTEM') and OpenKey('SYSTEM', false) then
        if KeyExists('CurrentControlSet') and OpenKey('CurrentControlSet', false) then
          if KeyExists('Enum') and OpenKey('Enum', false) then
            if KeyExists('FTDIBUS') and OpenKey('FTDIBUS', false) then
              if KeyExists(USBPorts[i]) and OpenKey(USBPorts[i], false) then
                if KeyExists('0000') and OpenKey('0000', false) then
                  if KeyExists('Device Parameters') and OpenKey('Device Parameters', false) then
                    USBPorts[i]:=ReadString('PortName');
      CloseKey;
    end;
  finally
    Free;
  end;

  //entsprechende Informationen zur COM-Port-Liste hinzufügen
  {for i:=0 to USBPorts.Count-1 do
  begin
    j:=ComPorts.IndexOf(USBPorts[i]);
    if j>-1 then ComPorts[j]:=ComPorts[j]+'  [USB-2-485]';
  end;}
  for DevName in USBPorts do
  begin
    j:=ComPorts.IndexOf(DevName);
    if j>-1 then ComPorts[j]:=ComPorts[j]+'  [USB-2-485]';
  end;

  //Und nun die Einträge in die Listbox kopieren


  //Einträge sortieren (stehen manchmal nicht in numerischer Reihenfolge in der Registry)
  //und in die Auswahlliste kopieren.
  ComPorts.Sort;
  CbCOM.Items:=ComPorts;
  ComPorts.Free;

  j:=-1;
  for DevName in CbCOM.Items do
  begin
    if Pos('TMCM-1110', DevName)>0 then j:=CbCOM.Items.IndexOf(DevName);
  end;

  if j>-1
    then CbCOM.ItemIndex:=j
    else CbCOM.ItemIndex:=0;
end;

//Button "Close": Fenster schließen
procedure TFormMain.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

//Button "Load": HEX-Datei laden
procedure TFormMain.BtnLoadClick(Sender: TObject);
var
  HEXFile:System.Text;
  HEXLine:string;
  RecordLength, RecordAddress, i:cardinal;
  RecordType:byte;
  RecordChecksum:byte;
  Checksum, LineCount:cardinal;
  ExtendedLinearAddress:cardinal;
  SegmentAddress:cardinal;
  FirstAddress: boolean;
begin
  if OpenDialog.Execute then
  begin
    //Name anzeigen, eventuell gekürzt
    if Length(OpenDialog.FileName)>40
      then StaticName.Caption:=ExtractFileDrive(OpenDialog.FileName)+'\...\'
                                +ExtractFileName(OpenDialog.FileName)
      else StaticName.Caption:=OpenDialog.FileName;

    ProgEnd:=0;
    LineCount:=1;
    RecordType:=0;
    ExtendedLinearAddress:=0;
    SegmentAddress:=0;
    FirstAddress:=true;

    AssignFile(HEXFile, OpenDialog.FileName);
    try
      try
        for i:=Low(ProgData) to High(ProgData) do ProgData[i]:=0;
        Reset(HEXFile);
        while (not Eof(HEXFile)) and (RecordType<>1) do  //Record-Typ 1 bedeutet Dateiende
        begin
          //Jede Zeile hat mindestens 11 Zeichen und beginnt mit einem Doppelpunkt
          ReadLn(HEXFile, HEXLine);
          if Length(HEXLine)<11 then raise EHexLoadError.Create('Line too short');
          if HEXLine[1]<>':' then raise EHexLoadError.Create('Improper record format');

          //Felder extrahieren
          RecordLength:=StrToInt('$'+MidStr(HEXLine, 2, 2));
          RecordAddress:=StrToInt('$'+MidStr(HEXLine, 4, 4));
          RecordType:=StrToInt('$'+MidStr(HEXLine, 8, 2));
          //Record Type: 0=normal data, 1=EOF, 2=Extended Segment Address, 4=Extended Linear Address
          RecordChecksum:=StrToInt('$'+MidStr(HEXLine, 10+RecordLength*2, 2));
          Checksum:=RecordLength+Cardinal(StrToInt('$'+MidStr(HEXLine, 4,2)))+
            Cardinal(StrToInt('$'+MidStr(HEXLine, 6, 2)))+RecordType;

          if RecordType=0 then  //Record Type 0: Daten
          begin
            if ExtendedLinearAddress<262144 then  //Daten mit Extended Linear Address >128KB werden ignoriert!
            begin                                 //(das sind die Fuses beim PIC und dsPIC)
              if FirstAddress then
              begin
                ProgStart:=RecordAddress+SegmentAddress+ExtendedLinearAddress;
                FirstAddress:=false;
              end else ProgStart:=Min(ProgStart, RecordAddress+SegmentAddress+ExtendedLinearAddress);

              for i:=0 to RecordLength-1 do
              begin
                if RecordAddress+SegmentAddress+ExtendedLinearAddress>SizeOf(ProgData)
                  then raise EHexLoadError.Create('Address too high');
                ProgData[RecordAddress+SegmentAddress+ExtendedLinearAddress]:=StrToInt('$'+MidStr(HEXLine, 10+i*2, 2));
                Inc(Checksum, ProgData[RecordAddress+SegmentAddress+ExtendedLinearAddress]);
                Inc(RecordAddress);
                ProgEnd:=Max(ProgEnd, RecordAddress+SegmentAddress+ExtendedLinearAddress);
                if ProgEnd>262144 then raise EHexLoadError.Create('HEX file too large');
              end;
              Checksum:=Checksum and $ff;               //Prüfsumme bilden und vergleichen
              Checksum:=(256-Checksum) and $ff;
              if Checksum<>RecordChecksum then raise EHexLoadError.Create('Record checksum error');
            end else if ExtendedLinearAddress>=$6000000
              then raise EHexAddressError.Create('Load address set for debugging');
          end
          else if RecordType=2
            then SegmentAddress:=StrToInt('$'+MidStr(HEXLine, 10, 4)) shl 4
          else if RecordType=4
            then begin
              ExtendedLinearAddress:=StrToInt('$'+MidStr(HEXLine, 10, 4)) shl 16;
              if (ExtendedLinearAddress>=$100000) and (ExtendedLinearAddress<$140000) then
              begin //Adressbereich bei ARM (AT91SAM7)
                ExtendedLinearAddress:=ExtendedLinearAddress-$100000;
              end;
            end
          else if not(RecordType in [1, 3, 5]) //Es werden nur Record Typ 0, 2 und 4 unterstützt (1,3,5 werden ingoriert)
            then raise EHexLoadError.Create('Record type not supported');

          Inc(LineCount);
        end;

        //Prüfsumme über alle Datenbytes bilden (wie im Sixpack/Quadpack) und anzeigen
        ProgChecksum:=0;
        Dec(ProgEnd);
        for i:=ProgStart to ProgEnd do ProgChecksum:=ProgChecksum+ProgData[i];
        StaticSize.Caption:=IntToStr(ProgEnd-ProgStart+1)+' bytes';
        StaticChecksum.Caption:=IntToHex(ProgChecksum, 4);
        BtnProgramme.Enabled:=true;

        //Prüfen, für welches Gerät die Datei gedacht ist
        if FindVersionString(ProgData, '####V###', DeviceAndVersion) then  //Motor-Firmware
        begin
          Insert(' ', DeviceAndVersion, 5);
          Insert('.', DeviceAndVersion, 8);
          if LeftStr(DeviceAndVersion, 4)<>'1110'
            then raise EHexCheckError.Create('');

          DeviceAndVersion:='TMCM-'+DeviceAndVersion;
          StaticVersion.Caption:=DeviceAndVersion;
        end
        else raise EHexCheckError.Create('');
      finally
        CloseFile(HEXFile);
      end
    except
      on E:EHexLoadError do  //Fehler beim Laden der HEX-Datei
      begin
        StaticName.Caption:='';
        StaticChecksum.Caption:='';
        StaticSize.Caption:='';
        StaticVersion.Caption:='';
        BtnProgramme.Enabled:=false;

        MessageDialog(Format('The file "%s" is not a valid HEX file!'#13'(%s in line %d)',
          [ExtractFileName(OpenDialog.FileName), E.Message, LineCount]), mtError, [mbOK], 0);
      end;
      on E:EHexCheckError do  //Fehler beim  Prüfen der HEX-Datei
      begin
        StaticName.Caption:='';
        StaticChecksum.Caption:='';
        StaticSize.Caption:='';
        StaticVersion.Caption:='';
        BtnProgramme.Enabled:=false;

        MessageDialog(Format('The file "%s" is not intended for use with a TMCM-2112 module!',
          [ExtractFileName(OpenDialog.FileName)]), mtError, [mbOK], 0);
      end;
    end;
  end;
end;

//Button "Start": Download durchführen
procedure TFormMain.BtnProgrammeClick(Sender: TObject);
var
  PageSize: cardinal;
  PageOffset: cardinal;
  PageAddress: cardinal;
  MemSize: cardinal;
  i: cardinal;
  Checksum: cardinal;
  t1: cardinal;
begin
  Comm32.DeviceName:='\\.\'+GetParameterSep(CbCOM.Text, ' ', 1);
  Comm32.Open;
  if Comm32.Enabled then
  begin
    try
      BtnProgramme.Enabled:=false;
      BtnLoad.Enabled:=false;
      BtnClose.Enabled:=false;
      EditAddress.Enabled:=false;
      CbCOM.Enabled:=false;

      ProgressBar.Position:=0;
      ProgressBar.Max:=ProgEnd-ProgStart;

      //Modul in den Boot-Modus versetzen
      StaticProgress.Caption:='Trying to enter boot mode...';
      SendTMCLAndWait(EditAddress.Value, [TMCL_Boot, $81, $92, $a3, $b4, $c5, $d6], false);
      //if not SendTMCLAndWait(EditNode.Value, [TMCL_Boot, $81, $92, $a3, $b4, $c5, $d6], true)
      //  then raise Exception.Create('Cannot enter boot mode');

      Comm32.Close;
      t1:=GetTickCount;
      repeat
        Application.ProcessMessages;
      until abs(GetTickCount-t1)>5000;
      Comm32.Open;

      //Modultyp und Bootloader-Version prüfen
      if not SendTMCLAndWait(EditAddress.Value, TMCL_GetVersion, 1, 0, 0, true)
        then raise Exception.Create('Cannot get boot loader version info');
      if (TMCLReply[4]=$04) and (TMCLReply[5]=$56)
        then StaticDeviceType.Caption:='TMCM-1110'
        else raise Exception.Create('Wrong module type connected');

      //Flash-Seitengröße abfragen
      if SendTMCLAndWait(EditAddress.Value, TMCL_BootGetInfo, 0, 0, 0, true) then
      begin
        PageSize:=TMCLReply[6]*256+TMCLReply[7];
      end else raise Exception.Create('Could not read the page size!');

      //Speichergröße abfragen
      if SendTMCLAndWait(EditAddress.Value, TMCL_BootGetInfo, 2, 0, 0, true) then
      begin
        MemSize:=(TMCLReply[4] shl 24) or (TMCLReply[5] shl 16) or
                  (TMCLReply[6] shl 8) or TMCLReply[7];
        if ProgEnd-ProgStart+1>MemSize-PageSize-16384
          then raise Exception.Create('Application to large!');
      end else raise Exception.Create('Could not read the memory size!');

      //Flash löschen
      StaticProgress.Caption:='Erasing...';
      if not SendTMCLAndWait(EditAddress.Value, TMCL_BootEraseAll, 0, 0, 0, true)
        then raise Exception.Create('Erase not successful!');

      //Seite für Seite programmieren
      StaticProgress.Caption:='Writing...';
      i:=ProgStart;
      PageAddress:=16384;
      PageOffset:=0;
      while i<ProgEnd do
      begin
        //Vier Bytes schreiben
        if not SendTMCLAndWait(EditAddress.Value, [TMCL_BootWriteBuffer, PageOffset div 4, 0,
        ProgData[i+3], ProgData[i+2], ProgData[i+1], ProgData[i]], true)
          then raise Exception.Create('Programming error (1)!');

        Inc(PageOffset, 4);
        Inc(i, 4);

        //Eine Seite voll oder letzte Seite?
        if (PageOffset mod PageSize=0) or (i>=ProgEnd) then
        begin
          //ShowMessage(IntToStr(PageOffset));
          if not SendTMCLAndWait(EditAddress.Value, TMCL_BootWritePage, 0, 0, PageAddress, true)
            then raise Exception.Create('Programming error (2)!');
          PageOffset:=0;
          PageAddress:=PageAddress+PageSize;
        end;

        ProgressBar.Position:=i-ProgStart;
      end;

      //Prüfsumme ermitteln
      StaticProgress.Caption:='Checking checksum...';
      if SendTMCLAndWait(EditAddress.Value, TMCL_BootGetChecksum, 0, 0, ProgEnd{16384+ProgEnd-ProgStart}, true) then
      begin
        Checksum:=(TMCLReply[4] shl 24) or (TMCLReply[5] shl 16) or
                  (TMCLReply[6] shl 8) or TMCLReply[7];
        if Checksum<>ProgChecksum
          then raise Exception.Create('Checksum error: '+IntToHex(Checksum, 8)+' / '
                                      +IntToHex(ProgChecksum, 8));
      end else raise Exception.Create('Checksum read error!');

      //Prüfsumme in die dafür vorgesehenen Speicherstellen schreiben
      StaticProgress.Caption:='Writing checksum...';
      {for i:= 0 to 125 do
        if not SendTMCLAndWait(EditAddress.Value, TMCL_BootWriteBuffer, i, 0, $ffffffff, true)
          then raise Exception.Create('Checksum write error (1)');}

      if not SendTMCLAndWait(EditAddress.Value, TMCL_BootWriteBuffer, 126, 0, ProgEnd-ProgStart+1, true)
        then raise Exception.Create('Checksum write error (2)!');
      if not SendTMCLAndWait(EditAddress.Value, TMCL_BootWriteBuffer, 127, 0, Checksum, true)
        then raise Exception.Create('Checksum write error (3)!');
      if not SendTMCLAndWait(EditAddress.Value, TMCL_BootWritePage, 0, 0, $3fe00, true)
        then raise Exception.Create('Checksum write error (4)!');

      //Applikation starten
      StaticProgress.Caption:='Starting application...';
      if not SendTMCLAndWait(EditAddress.Value, TMCL_BootStartAppl, 0, 0, 0, true)
        then raise Exception.Create('Application start error!');

      Comm32.Close;
      StaticProgress.Caption:='Successful!';
    finally
      Comm32.Close;
      BtnProgramme.Enabled:=true;
      BtnLoad.Enabled:=true;
      BtnClose.Enabled:=true;
      EditAddress.Enabled:=true;
      CbCOM.Enabled:=true;
    end;
  end else MessageDialog('Could not open port!', mtError, [mbOK], 0);
end;

end.

