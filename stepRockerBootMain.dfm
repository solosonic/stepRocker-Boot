object FormMain: TFormMain
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsSingle
  Caption = 'stepRocker Software Installer V1.00'
  ClientHeight = 319
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poDesktopCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object GrpFile: TGroupBox
    Left = 8
    Top = 8
    Width = 441
    Height = 105
    Caption = ' File '
    TabOrder = 0
    object LblName: TLabel
      Left = 112
      Top = 29
      Width = 31
      Height = 13
      Caption = 'Name:'
    end
    object LblSize: TLabel
      Left = 112
      Top = 52
      Width = 23
      Height = 13
      Caption = 'Size:'
    end
    object LblVersion: TLabel
      Left = 285
      Top = 52
      Width = 39
      Height = 13
      Caption = 'Version:'
    end
    object LblChecksum: TLabel
      Left = 112
      Top = 75
      Width = 52
      Height = 13
      Caption = 'Checksum:'
    end
    object BtnLoad: TButton
      Left = 16
      Top = 24
      Width = 75
      Height = 25
      Caption = '&Load...'
      TabOrder = 0
      OnClick = BtnLoadClick
    end
    object StaticName: TStaticText
      Left = 170
      Top = 29
      Width = 257
      Height = 17
      AutoSize = False
      BorderStyle = sbsSunken
      TabOrder = 1
    end
    object StaticSize: TStaticText
      Left = 170
      Top = 52
      Width = 89
      Height = 17
      AutoSize = False
      BorderStyle = sbsSunken
      TabOrder = 2
    end
    object StaticVersion: TStaticText
      Left = 330
      Top = 52
      Width = 97
      Height = 17
      AutoSize = False
      BorderStyle = sbsSunken
      TabOrder = 3
    end
    object StaticChecksum: TStaticText
      Left = 170
      Top = 75
      Width = 89
      Height = 17
      AutoSize = False
      BorderStyle = sbsSunken
      TabOrder = 4
    end
  end
  object GrpProgram: TGroupBox
    Left = 8
    Top = 119
    Width = 442
    Height = 162
    Caption = ' Download '
    TabOrder = 1
    object LblDeviceType: TLabel
      Left = 112
      Top = 85
      Width = 63
      Height = 13
      Caption = 'Device Type:'
    end
    object LblProgress: TLabel
      Left = 112
      Top = 108
      Width = 46
      Height = 13
      Caption = 'Progress:'
    end
    object LblCOM: TLabel
      Left = 140
      Top = 18
      Width = 24
      Height = 13
      Caption = 'Port:'
    end
    object Label1: TLabel
      Left = 121
      Top = 45
      Width = 43
      Height = 13
      Caption = 'Address:'
    end
    object BtnProgramme: TButton
      Left = 16
      Top = 80
      Width = 75
      Height = 25
      Caption = '&Start'
      Enabled = False
      TabOrder = 0
      OnClick = BtnProgrammeClick
    end
    object StaticDeviceType: TStaticText
      Left = 185
      Top = 85
      Width = 242
      Height = 17
      AutoSize = False
      BorderStyle = sbsSunken
      TabOrder = 1
    end
    object StaticProgress: TStaticText
      Left = 170
      Top = 108
      Width = 257
      Height = 17
      AutoSize = False
      BorderStyle = sbsSunken
      TabOrder = 2
    end
    object ProgressBar: TProgressBar
      Left = 170
      Top = 131
      Width = 257
      Height = 16
      Smooth = True
      TabOrder = 3
    end
    object CbCOM: TComboBox
      Left = 170
      Top = 16
      Width = 167
      Height = 21
      Style = csDropDownList
      TabOrder = 4
    end
    object EditAddress: TSpinEdit
      Left = 170
      Top = 43
      Width = 47
      Height = 22
      MaxValue = 254
      MinValue = 1
      TabOrder = 5
      Value = 1
    end
  end
  object BtnClose: TButton
    Left = 375
    Top = 287
    Width = 75
    Height = 25
    Caption = '&Close'
    TabOrder = 2
    OnClick = BtnCloseClick
  end
  object OpenDialog: TOpenDialog
    Filter = 'HEX files|*.hex|All files|*.*'
    Left = 24
    Top = 256
  end
  object Comm32: TComm32
    DeviceName = 'COM2'
    MonitorEvents = [evRxChar]
    FlowControl = fcNone
    Options = []
    OnRxChar = Comm32RxChar
    Simple = False
    Left = 96
    Top = 256
  end
end
