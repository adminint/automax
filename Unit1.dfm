object Form1: TForm1
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  Caption = #1040#1074#1090#1086#1091#1089#1090#1072#1085#1086#1074#1082#1072' '#1084#1077#1089#1089#1077#1085#1076#1078#1077#1088#1072' MAX '
  ClientHeight = 127
  ClientWidth = 451
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poDesktopCenter
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object lblStatus: TLabel
    Left = 16
    Top = 24
    Width = 112
    Height = 13
    Caption = #1055#1088#1086#1075#1088#1077#1089#1089' '#1089#1082#1072#1095#1080#1074#1072#1085#1080#1103':'
  end
  object ProgressBar1: TProgressBar
    Left = 16
    Top = 43
    Width = 417
    Height = 17
    TabOrder = 0
  end
  object btnInstall: TButton
    Left = 16
    Top = 80
    Width = 75
    Height = 25
    Caption = #1059#1089#1090#1072#1085#1086#1074#1080#1090#1100
    TabOrder = 1
    OnClick = btnInstallClick
  end
  object btnCancel: TButton
    Left = 110
    Top = 80
    Width = 75
    Height = 25
    Caption = #1054#1090#1084#1077#1085#1072
    TabOrder = 2
    OnClick = btnCancelClick
  end
  object btnCancel1: TButton
    Left = 358
    Top = 80
    Width = 75
    Height = 25
    Caption = #1047#1072#1082#1088#1099#1090#1100
    TabOrder = 3
    OnClick = btnCancel1Click
  end
end
