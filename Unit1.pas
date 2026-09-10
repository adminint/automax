unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ComCtrls, System.IOUtils;

type
  TForm1 = class(TForm)
    lblStatus: TLabel;
    ProgressBar1: TProgressBar;
    btnInstall: TButton;
    btnCancel: TButton;
    btnCancel1: TButton;
    procedure btnInstallClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnCancel1Click(Sender: TObject);
  private
    FProcess: THandle;
    FCancelled: Boolean;
    procedure SetUIState(Installing: Boolean);
    procedure UpdateStatus(const S: string);
    function DownloadFile(const Url, DestFile: string): Boolean;
    function InstallMsi(const MsiPath: string; out ExitCode: Cardinal): Boolean;
    procedure RunProcessAndWait(const Exe, Params: string;
      out ExitCode: Cardinal);
    function CheckAndShowInstalled: Boolean;
    procedure ShowAutoCloseDialog(Seconds: Integer);
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

{ ============================================================ }
{  Свои типы и константы WinHTTP                              }
{ ============================================================ }

type
  HINTERNET = Pointer;
  PLPWSTR   = ^LPWSTR;
  DWORD_PTR = NativeUInt;

const
  BUFFER_SIZE = 64 * 1024;
  MAX_URL = 'https://download.max.ru/win/release/MAX.msi';

  WINHTTP_FLAG_SECURE                = $00800000;
  WINHTTP_FLAG_REFRESH               = $00000100;

  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY   = 0;
  WINHTTP_ACCESS_TYPE_NO_PROXY        = 1;
  WINHTTP_ACCESS_TYPE_NAMED_PROXY     = 3;
  WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY = 4;

  WINHTTP_QUERY_STATUS_CODE    = 19;
  WINHTTP_QUERY_CONTENT_LENGTH = 5;
  WINHTTP_QUERY_FLAG_NUMBER    = $20000000;

  WINHTTP_OPTION_SECURITY_FLAGS = 31;

  SECURITY_FLAG_IGNORE_UNKNOWN_CA        = $00000100;
  SECURITY_FLAG_IGNORE_CERT_DATE_INVALID = $00002000;
  SECURITY_FLAG_IGNORE_CERT_CN_INVALID   = $00001000;
  SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE  = $00000200;

var
  WINHTTP_NO_PROXY_NAME: PWideChar = nil;
  WINHTTP_NO_PROXY_BYPASS: PWideChar = nil;
  WINHTTP_NO_REFERER: PWideChar = nil;
  WINHTTP_DEFAULT_ACCEPT_TYPES: PLPWSTR = nil;
  WINHTTP_NO_ADDITIONAL_HEADERS: PWideChar = nil;
  WINHTTP_NO_REQUEST_DATA: Pointer = nil;
  WINHTTP_NO_HEADER_INDEX: PDWORD = nil;

{ ============================================================ }
{  Импорт WinHTTP API                                         }
{ ============================================================ }

function WinHttpOpen(pwszUserAgent: LPCWSTR; dwAccessType: DWORD;
  pwszProxyName, pwszProxyBypass: LPCWSTR; dwFlags: DWORD): HINTERNET;
  stdcall; external 'winhttp.dll' name 'WinHttpOpen';

function WinHttpConnect(hSession: HINTERNET; pswzServerName: LPCWSTR;
  nServerPort: Word; dwReserved: DWORD): HINTERNET;
  stdcall; external 'winhttp.dll' name 'WinHttpConnect';

function WinHttpOpenRequest(hConnect: HINTERNET; pwszVerb: LPCWSTR;
  pwszObjectName: LPCWSTR; pwszVersion: LPCWSTR; pwszReferrer: LPCWSTR;
  ppwszAcceptTypes: PLPWSTR; dwFlags: DWORD): HINTERNET;
  stdcall; external 'winhttp.dll' name 'WinHttpOpenRequest';

function WinHttpSendRequest(hRequest: HINTERNET;
  pwszHeaders: LPCWSTR; dwHeadersLength: DWORD;
  lpOptional: Pointer; dwOptionalLength: DWORD;
  dwTotalLength: DWORD; dwContext: DWORD_PTR): BOOL;
  stdcall; external 'winhttp.dll' name 'WinHttpSendRequest';

function WinHttpReceiveResponse(hRequest: HINTERNET;
  lpReserved: Pointer): BOOL;
  stdcall; external 'winhttp.dll' name 'WinHttpReceiveResponse';

function WinHttpQueryHeaders(hRequest: HINTERNET; dwInfoLevel: DWORD;
  pwszName: LPCWSTR; lpBuffer: Pointer; var lpdwBufferLength: DWORD;
  lpdwIndex: PDWORD): BOOL;
  stdcall; external 'winhttp.dll' name 'WinHttpQueryHeaders';

function WinHttpReadData(hRequest: HINTERNET;
  lpBuffer: Pointer; dwNumberOfBytesToRead: DWORD;
  var lpdwNumberOfBytesRead: DWORD): BOOL;
  stdcall; external 'winhttp.dll' name 'WinHttpReadData';

function WinHttpSetOption(hInternet: HINTERNET; dwOption: DWORD;
  lpBuffer: Pointer; dwBufferLength: DWORD): BOOL;
  stdcall; external 'winhttp.dll' name 'WinHttpSetOption';

function WinHttpCloseHandle(hInternet: HINTERNET): BOOL;
  stdcall; external 'winhttp.dll' name 'WinHttpCloseHandle';

{ ============================================================ }
{  Утилиты UI                                                 }
{ ============================================================ }

procedure TForm1.UpdateStatus(const S: string);
begin
  lblStatus.Caption := S;
  lblStatus.Update;
  Application.ProcessMessages;
end;

procedure TForm1.SetUIState(Installing: Boolean);
begin
  btnInstall.Enabled := not Installing;
  btnCancel.Enabled  := Installing;
end;

{ ============================================================ }
{  Скачивание через WinHTTP                                   }
{ ============================================================ }

function TForm1.DownloadFile(const Url, DestFile: string): Boolean;
var
  hSession, hConnect, hRequest: HINTERNET;
  HostName, UrlPath, Scheme, Rest: string;
  Port: Word;
  Flags: DWORD;
  Buffer: array of Byte;
  BytesRead: DWORD;
  TotalRead: Int64;
  ContentLength: Int64;
  StatusCode: DWORD;
  StatusSize: DWORD;
  FS: TFileStream;
  LastUpdate: Cardinal;
  P, P2: Integer;
  AccessType: DWORD;
begin
  Result := False;
  hSession := nil; hConnect := nil; hRequest := nil;

  { --- Разбор URL вручную --- }
  if Pos('https://', LowerCase(Url)) = 1 then
  begin
    Scheme := 'https';
    Port := 443;
    Rest := Copy(Url, 9, MaxInt);
  end
  else if Pos('http://', LowerCase(Url)) = 1 then
  begin
    Scheme := 'http';
    Port := 80;
    Rest := Copy(Url, 8, MaxInt);
  end
  else
  begin
    UpdateStatus('Поддерживаются только http/https.');
    Exit;
  end;

  P := Pos('/', Rest);
  if P = 0 then
  begin
    HostName := Rest;
    UrlPath := '/';
  end
  else
  begin
    HostName := Copy(Rest, 1, P - 1);
    UrlPath  := Copy(Rest, P, MaxInt);
  end;

  { Порт в хосте, если указан: host:port }
  P2 := Pos(':', HostName);
  if P2 > 0 then
  begin
    Port := StrToIntDef(Copy(HostName, P2 + 1, MaxInt), Port);
    HostName := Copy(HostName, 1, P2 - 1);
  end;

  if (HostName = '') or (UrlPath = '') then
  begin
    UpdateStatus('Некорректный URL.');
    Exit;
  end;

  { --- Прокси: авто на Win8.1+, иначе default --- }
  if (TOSVersion.Major > 6) or
     ((TOSVersion.Major = 6) and (TOSVersion.Minor >= 3)) then
    AccessType := WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY
  else
    AccessType := WINHTTP_ACCESS_TYPE_DEFAULT_PROXY;

  hSession := WinHttpOpen('MAX Installer/1.0',
    AccessType,
    WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if hSession = nil then
  begin
    UpdateStatus('Не удалось инициализировать WinHTTP.');
    Exit;
  end;

  try
    hConnect := WinHttpConnect(hSession,
      PWideChar(WideString(HostName)), Port, 0);
    if hConnect = nil then
    begin
      UpdateStatus('Ошибка соединения с сервером.');
      Exit;
    end;

    Flags := WINHTTP_FLAG_REFRESH;
    if Scheme = 'https' then
      Flags := Flags or WINHTTP_FLAG_SECURE;

    hRequest := WinHttpOpenRequest(hConnect, 'GET',
      PWideChar(WideString(UrlPath)),
      nil, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, Flags);
    if hRequest = nil then
    begin
      UpdateStatus('Ошибка создания запроса.');
      Exit;
    end;

    { Игнорировать ошибки сертификата (аналог curl -k) }
    Flags := SECURITY_FLAG_IGNORE_UNKNOWN_CA or
             SECURITY_FLAG_IGNORE_CERT_DATE_INVALID or
             SECURITY_FLAG_IGNORE_CERT_CN_INVALID or
             SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE;
    WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS,
      @Flags, SizeOf(Flags));

    if not WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
      WINHTTP_NO_REQUEST_DATA, 0, 0, 0) then
    begin
      UpdateStatus('Ошибка отправки запроса.');
      Exit;
    end;

    if not WinHttpReceiveResponse(hRequest, nil) then
    begin
      UpdateStatus('Ошибка получения ответа.');
      Exit;
    end;

    { --- Код ответа --- }
    StatusSize := SizeOf(StatusCode);
    WinHttpQueryHeaders(hRequest,
      WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER,
      nil, @StatusCode, StatusSize, nil);

    if StatusCode <> 200 then
    begin
      UpdateStatus(Format('HTTP %d.', [StatusCode]));
      Exit;
    end;

    { --- Content-Length --- }
    ContentLength := 0;
    StatusSize := SizeOf(ContentLength);
    WinHttpQueryHeaders(hRequest,
      WINHTTP_QUERY_CONTENT_LENGTH or WINHTTP_QUERY_FLAG_NUMBER,
      nil, @ContentLength, StatusSize, nil);

    FS := TFileStream.Create(DestFile, fmCreate);
    try
      SetLength(Buffer, BUFFER_SIZE);
      TotalRead := 0;
      LastUpdate := GetTickCount;

      repeat
        Application.ProcessMessages;
        if FCancelled then
        begin
          UpdateStatus('Отмена загрузки...');
          Exit;
        end;

        if not WinHttpReadData(hRequest, @Buffer[0], BUFFER_SIZE, BytesRead) then
        begin
          UpdateStatus('Ошибка чтения данных.');
          Exit;
        end;
        if BytesRead = 0 then
          Break;

        FS.WriteBuffer(Buffer[0], BytesRead);
        Inc(TotalRead, BytesRead);

        if (ContentLength > 0) and (GetTickCount - LastUpdate >= 100) then
        begin
          ProgressBar1.Position := Integer((TotalRead * 100) div ContentLength);
          UpdateStatus(Format('Скачивание... %d %% (%s из %s)',
            [ProgressBar1.Position,
             FormatFloat('#,##0.0', TotalRead / 1024 / 1024) + ' МБ',
             FormatFloat('#,##0.0', ContentLength / 1024 / 1024) + ' МБ']));
          LastUpdate := GetTickCount;
        end;
      until False;

      Result := (not FCancelled) and (TotalRead > 0);
    finally
      FS.Free;
    end;

    if Result then
    begin
      ProgressBar1.Position := 100;
      UpdateStatus('Скачивание завершено.');
    end;

  finally
    if hRequest <> nil then WinHttpCloseHandle(hRequest);
    if hConnect <> nil then WinHttpCloseHandle(hConnect);
    if hSession <> nil then WinHttpCloseHandle(hSession);
  end;
end;

{ ============================================================ }
{  Проверка установки                                         }
{ ============================================================ }

function TForm1.CheckAndShowInstalled: Boolean;
var
  AppData, MaxDir, ExePath: string;
begin
  Result := False;

  AppData := GetEnvironmentVariable('APPDATA');
  if AppData = '' then
  begin
    UpdateStatus('Не удалось определить %APPDATA%.');
    Exit;
  end;

  MaxDir  := TPath.Combine(AppData, 'MAX');
  ExePath := TPath.Combine(MaxDir, 'max.exe');

  if FileExists(ExePath) then
  begin
    Result := True;
    UpdateStatus('MAX установлен: ' + ExePath);
  end
  else
  begin
    UpdateStatus('Установка завершена, но max.exe не найден: ' + ExePath);
  end;
end;

{ ============================================================ }
{  Окно с автозакрытием через N секунд                         }
{ ============================================================ }

procedure TForm1.ShowAutoCloseDialog(Seconds: Integer);
var
  Dlg: TForm;
  lbl: TLabel;
  lblCount: TLabel;
  btnClose, btnStay: TButton;
  Start: Cardinal;
  Remaining: Integer;
  Elapsed: Cardinal;
begin
  Dlg := TForm.CreateNew(nil);
  try
    Dlg.Caption := 'MAX installed';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poScreenCenter;
    Dlg.ClientWidth := 400;
    Dlg.ClientHeight := 170;
    Dlg.Font.Assign(Self.Font);

    lbl := TLabel.Create(Dlg);
    lbl.Parent := Dlg;
    lbl.SetBounds(16, 16, 368, 60);
    lbl.AutoSize := False;
    lbl.WordWrap := True;
    lbl.Caption := 'MAX has been installed successfully.';

    lblCount := TLabel.Create(Dlg);
    lblCount.Parent := Dlg;
    lblCount.SetBounds(16, 80, 368, 24);
    lblCount.AutoSize := False;
    lblCount.Font.Style := [fsBold];
    lblCount.Caption := Format('Closing in %d seconds...', [Seconds]);

    btnClose := TButton.Create(Dlg);
    btnClose.Parent := Dlg;
    btnClose.SetBounds(210, 120, 85, 28);
    btnClose.Caption := 'Close now';
    btnClose.Default := True;
    btnClose.ModalResult := mrOk;

    btnStay := TButton.Create(Dlg);
    btnStay.Parent := Dlg;
    btnStay.SetBounds(301, 120, 85, 28);
    btnStay.Caption := 'Stay';
    btnStay.Cancel := True;
    btnStay.ModalResult := mrCancel;

    Start := GetTickCount;
    while True do
    begin
      Application.ProcessMessages;
      if Dlg.ModalResult <> 0 then
        Break;

      Elapsed := GetTickCount - Start;
      Remaining := Seconds - Integer(Elapsed div 1000);
      if Remaining < 0 then
        Remaining := 0;

      lblCount.Caption := Format('Closing in %d seconds...', [Remaining]);
      lblCount.Update;

      if Remaining = 0 then
      begin
        Dlg.ModalResult := mrOk;
        Break;
      end;

      Sleep(50);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ============================================================ }
{  Запуск процессов                                           }
{ ============================================================ }

procedure TForm1.RunProcessAndWait(const Exe, Params: string;
  out ExitCode: Cardinal);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  CmdLine: string;
begin
  ExitCode := Cardinal(-1);
  CmdLine := '"' + Exe + '" ' + Params;

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;

  if CreateProcess(nil, PChar(CmdLine), nil, nil, False,
    CREATE_NEW_PROCESS_GROUP, nil, nil, SI, PI) then
  begin
    FProcess := PI.hProcess;
    try
      while WaitForSingleObject(PI.hProcess, 200) = WAIT_TIMEOUT do
      begin
        Application.ProcessMessages;
        if FCancelled then
        begin
          TerminateProcess(PI.hProcess, 1);
          Break;
        end;
      end;
      GetExitCodeProcess(PI.hProcess, ExitCode);
    finally
      CloseHandle(PI.hThread);
      CloseHandle(PI.hProcess);
      FProcess := 0;
    end;
  end;
end;

function TForm1.InstallMsi(const MsiPath: string;
  out ExitCode: Cardinal): Boolean;
var
  MsiExe: string;
  LogPath: string;
begin
  UpdateStatus('Установка MAX, подождите...');
  ProgressBar1.Style := pbstMarquee;

  MsiExe := TPath.Combine(GetEnvironmentVariable('SystemRoot'),
    'System32\msiexec.exe');
  LogPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'max_install.log');

  // /fa — принудительная переустановка всех файлов
  // ALLUSERS=2 + MSIINSTALLPERUSER=1 = установка для текущего пользователя
  RunProcessAndWait(MsiExe,
    Format('/fa "%s" ALLUSERS=2 MSIINSTALLPERUSER=1 /qn /norestart /l*v "%s"',
      [MsiPath, LogPath]), ExitCode);

  ProgressBar1.Style := pbstNormal;
  Result := (ExitCode = 0) and (not FCancelled);
end;

{ ============================================================ }
{  Обработчики событий                                        }
{ ============================================================ }

procedure TForm1.FormCreate(Sender: TObject);
begin
  ProgressBar1.Min := 0;
  ProgressBar1.Max := 100;
  ProgressBar1.Position := 0;
  ProgressBar1.Smooth := True;
  FCancelled := False;
  FProcess := 0;
  lblStatus.Caption := 'Нажмите "Установить" для начала.';
end;

procedure TForm1.btnInstallClick(Sender: TObject);
var
  MsiPath: string;
  ExitCode: Cardinal;
  Start: Cardinal;
  InstallOK: Boolean;
begin
  FCancelled := False;
  SetUIState(True);
  ProgressBar1.Position := 0;
  InstallOK := False;

  MsiPath := TPath.Combine(TPath.GetTempPath, 'MAX.msi');
  if FileExists(MsiPath) then
    try TFile.Delete(MsiPath); except end;

  Start := GetTickCount;
  UpdateStatus('Скачивание MAX...');

  // 1. Скачивание
  if not DownloadFile(MAX_URL, MsiPath) then
  begin
    if FCancelled then UpdateStatus('Отменено пользователем.')
    else UpdateStatus('Ошибка скачивания файла.');
    SetUIState(False);
    if FileExists(MsiPath) then
      try TFile.Delete(MsiPath); except end;
    Exit;
  end;

  // 2. Установка
  if not InstallMsi(MsiPath, ExitCode) then
  begin
    if FCancelled then UpdateStatus('Установка отменена.')
    else UpdateStatus(Format('Ошибка установки (код %d).', [ExitCode]));
    SetUIState(False);
    Exit;
  end;

  UpdateStatus(Format('Готово! Установка заняла %d сек.',
    [(GetTickCount - Start) div 1000]));
  ProgressBar1.Position := 100;
  SetUIState(False);

  // 3. Проверка установки
  InstallOK := CheckAndShowInstalled;

  // 4. Если всё ок — окно с автозакрытием через 5 секунд
  if InstallOK then
  begin
    ShowAutoCloseDialog(5);
    Application.Terminate;
  end
  else
    ShowMessage('MAX установлен, но проверьте папку вручную.');
end;

procedure TForm1.btnCancelClick(Sender: TObject);
begin
  FCancelled := True;
  if FProcess <> 0 then
    TerminateProcess(FProcess, 1);
  UpdateStatus('Отмена...');
end;

procedure TForm1.btnCancel1Click(Sender: TObject);
begin
  btnCancelClick(nil);
  Close;
end;

end.
