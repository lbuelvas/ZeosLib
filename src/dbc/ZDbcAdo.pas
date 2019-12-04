{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{               ADO Connectivity Classes                  }
{                                                         }
{        Originally written by Janos Fegyverneki          }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2012 Zeos Development Group       }
{                                                         }
{ License Agreement:                                      }
{                                                         }
{ This library is distributed in the hope that it will be }
{ useful, but WITHOUT ANY WARRANTY; without even the      }
{ implied warranty of MERCHANTABILITY or FITNESS FOR      }
{ A PARTICULAR PURPOSE.  See the GNU Lesser General       }
{ Public License for more details.                        }
{                                                         }
{ The source code of the ZEOS Libraries and packages are  }
{ distributed under the Library GNU General Public        }
{ License (see the file COPYING / COPYING.ZEOS)           }
{ with the following  modification:                       }
{ As a special exception, the copyright holders of this   }
{ library give you permission to link this library with   }
{ independent modules to produce an executable,           }
{ regardless of the license terms of these independent    }
{ modules, and to copy and distribute the resulting       }
{ executable under terms of your choice, provided that    }
{ you also meet, for each linked independent module,      }
{ the terms and conditions of the license of that module. }
{ An independent module is a module which is not derived  }
{ from or based on this library. If you modify this       }
{ library, you may extend this exception to your version  }
{ of the library, but you are not obligated to do so.     }
{ If you do not wish to do so, delete this exception      }
{ statement from your version.                            }
{                                                         }
{                                                         }
{ The project web site is located on:                     }
{   http://zeos.firmos.at  (FORUM)                        }
{   http://sourceforge.net/p/zeoslib/tickets/ (BUGTRACKER)}
{   svn://svn.code.sf.net/p/zeoslib/code-0/trunk (SVN)    }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit ZDbcAdo;

interface

{$I ZDbc.inc}

{$IF not defined(MSWINDOWS) and not defined(ZEOS_DISABLE_ADO)}
  {$DEFINE ZEOS_DISABLE_ADO}
{$IFEND}

{$IFNDEF ZEOS_DISABLE_ADO}
uses
  Classes, {$IFDEF MSEgui}mclasses,{$ENDIF} SysUtils,
  ZDbcConnection, ZDbcIntfs, ZCompatibility, ZPlainAdoDriver,
  ZPlainAdo, ZURL, ZTokenizer, ZClasses, ZDbcLogging;

type
  {** Implements Ado Database Driver. }
  TZAdoDriver = class(TZAbstractDriver)
  public
    constructor Create; override;
    function Connect(const Url: TZURL): IZConnection; override;
    function GetMajorVersion: Integer; override;
    function GetMinorVersion: Integer; override;
    function GetTokenizer: IZTokenizer; override;
  end;

  {** Represents an Ado specific connection interface. }
  IZAdoConnection = interface (IZConnection)
    ['{50D1AF76-0174-41CD-B90B-4FB770EFB14F}']
    function GetAdoConnection: ZPlainAdo.Connection;
    procedure InternalExecute(const SQL: WideString; LoggingCategory: TZLoggingCategory);
  end;

  {** Implements a generic Ado Connection. }
  TZAdoConnection = class(TZAbstractDbcConnection, IZAdoConnection, IZTransaction)
  private
    fServerProvider: TZServerProvider;
    FSavePoints: IZCollection;
    FTransactionLevel: Integer;
  protected
    FAdoConnection: ZPlainAdo.Connection;
    function GetAdoConnection: ZPlainAdo.Connection;
    procedure InternalExecute(const SQL: WideString; LoggingCategory: TZLoggingCategory);
    procedure InternalCreate; override;
    procedure InternalClose; override;
  public //IZTransaction
    function SavePoint(const AName: String): IZTransaction;
  public
    destructor Destroy; override;

    function GetBinaryEscapeString(const Value: TBytes): String; overload; override;
    function GetBinaryEscapeString(const Value: RawByteString): String; overload; override;
    function CreateRegularStatement(Info: TStrings): IZStatement; override;
    function CreatePreparedStatement(const SQL: string; Info: TStrings):
      IZPreparedStatement; override;
    function CreateCallableStatement(const SQL: string; Info: TStrings):
      IZCallableStatement; override;

    procedure Commit; override;
    procedure Rollback; override;
    procedure SetAutoCommit(Value: Boolean); override;
    procedure SetTransactionIsolation(Level: TZTransactIsolationLevel); override;
    function StartTransaction: Integer;  override;

    procedure Open; override;

    procedure SetCatalog(const Catalog: string); override;
    function GetCatalog: string; override;

    function GetServerProvider: TZServerProvider; override;
  end;

  TZAdoSavePoint = class(TZCodePagedObject, IZTransaction)
  private
    {$IFDEF AUTOREFCOUNT}[weak]{$ENDIF}FOwner: TZAdoConnection;
    fName: UnicodeString;
  public //IZTransaction
    procedure Commit;
    procedure Rollback;
    function SavePoint(const AName: String): IZTransaction;
  public
    Constructor Create(const Name: String; Owner: TZAdoConnection);
  end;

var
  {** The common driver manager object. }
  AdoDriver: IZDriver;

{$ENDIF ZEOS_DISABLE_ADO}
implementation
{$IFNDEF ZEOS_DISABLE_ADO}

uses
  Variants, ActiveX, ZOleDB,
  ZDbcUtils, ZAdoToken, ZSysUtils, ZMessages, ZDbcProperties,
  ZDbcAdoStatement, ZDbcAdoMetaData, ZEncoding, ZCollections,
  ZDbcOleDBUtils, ZDbcOleDBMetadata, ZDbcAdoUtils;

const                                                //adXactUnspecified
  IL: array[TZTransactIsolationLevel] of TOleEnum = (adXactChaos, adXactReadUncommitted, adXactReadCommitted, adXactRepeatableRead, adXactSerializable);

{ TZAdoDriver }

{**
  Constructs this object with default properties.
}
constructor TZAdoDriver.Create;
begin
  inherited Create;
  AddSupportedProtocol(AddPlainDriverToCache(TZAdoPlainDriver.Create));
end;

{**
  Attempts to make a database connection to the given URL.
}
function TZAdoDriver.Connect(const Url: TZURL): IZConnection;
begin
  Result := TZAdoConnection.Create(Url);
end;

{**
  Gets the driver's major version number. Initially this should be 1.
  @return this driver's major version number
}
function TZAdoDriver.GetMajorVersion: Integer;
begin
  Result := 1;
end;

{**
  Gets the driver's minor version number. Initially this should be 0.
  @return this driver's minor version number
}
function TZAdoDriver.GetMinorVersion: Integer;
begin
  Result := 0;
end;

function TZAdoDriver.GetTokenizer: IZTokenizer;
begin
  Result := TZAdoSQLTokenizer.Create; { thread save! Allways return a new Tokenizer! }
end;

var //eh: was threadvar but this defintely does not work! we just need !one! value
  AdoCoInitialized: integer;

procedure CoInit;
begin
  inc(AdoCoInitialized);
  if AdoCoInitialized=1 then
    CoInitialize(nil);
end;

procedure CoUninit;
begin
  assert(AdoCoInitialized>0);
  dec(AdoCoInitialized);
  if AdoCoInitialized=0 then
    CoUninitialize;
end;
{ TZAdoConnection }

procedure TZAdoConnection.InternalCreate;
begin
  CoInit;
  FAdoConnection := CoConnection.Create;
  Self.FMetadata := TZAdoDatabaseMetadata.Create(Self, URL);
  FSavePoints := TZCollection.Create;
end;

{**
  Destroys this object and cleanups the memory.
}
destructor TZAdoConnection.Destroy;
begin
  Close;
  FAdoConnection := nil;
  inherited Destroy;
  CoUninit;
end;

{**
  Just return the Ado Connection
}
function TZAdoConnection.GetAdoConnection: ZPlainAdo.Connection;
begin
  Result := FAdoConnection;
end;

{**
  Executes simple statements internally.
}
procedure TZAdoConnection.InternalExecute(const SQL: WideString;
  LoggingCategory: TZLoggingCategory);
var
  RowsAffected: OleVariant;
begin
  try
    FAdoConnection.Execute(SQL, RowsAffected, adExecuteNoRecords);
    DriverManager.LogMessage(LoggingCategory, ConSettings^.Protocol, ZUnicodeToRaw(SQL, ZOSCodePage));
  except
    on E: Exception do
    begin
      DriverManager.LogError(LoggingCategory, ConSettings^.Protocol, ZUnicodeToRaw(SQL, ZOSCodePage), 0,
        ConvertEMsgToRaw(E.Message, ConSettings^.ClientCodePage^.CP));
      raise;
    end;
  end;
end;

{**
  Opens a connection to database server with specified parameters.
}
procedure TZAdoConnection.Open;
var
  LogMessage: RawByteString;
  ConnectStrings: TStrings;
  DBInitialize: IDBInitialize;
  Command: ZPlainAdo.Command;
  DBCreateCommand: IDBCreateCommand;
  GetDataSource: IGetDataSource;
begin
  if not Closed then Exit;

  LogMessage := 'CONNECT TO "'+ConSettings^.Database+'" AS USER "'+ConSettings^.User+'"';
  try
    if ReadOnly then
      FAdoConnection.Set_Mode(adModeRead)
    else
      FAdoConnection.Set_Mode(adModeUnknown);

    ConnectStrings := SplitString(DataBase, ';');
    FServerProvider := ProviderNamePrefix2ServerProvider(ConnectStrings.Values[ConnProps_Provider]);
    FreeAndNil(ConnectStrings);

    FAdoConnection.Open(WideString(Database), WideString(User), WideString(Password), -1{adConnectUnspecified});
    FAdoConnection.Set_CursorLocation(adUseClient);
    DriverManager.LogMessage(lcConnect, ConSettings^.Protocol, LogMessage);
    ConSettings^.AutoEncode := {$IFDEF UNICODE}False{$ELSE}True{$ENDIF};
    CheckCharEncoding('CP_UTF16');
  except
    on E: Exception do
    begin
      DriverManager.LogError(lcConnect, ConSettings^.Protocol, LogMessage, 0,
        ConvertEMsgToRaw(E.Message, ConSettings^.ClientCodePage^.CP));
      raise;
    end;
  end;

  inherited Open;

  {EH: the only way to get back to generic Ole is using the command ... }
  Command := CoCommand.Create;
  Command.Set_ActiveConnection(FAdoConnection);
  if Succeeded(((Command as ADOCommandConstruction).OLEDBCommand as ICommand).GetDBSession(IID_IDBCreateCommand, IInterface(DBCreateCommand))) then
    if DBCreateCommand.QueryInterface(IID_IGetDataSource, GetDataSource) = S_OK then
      if Succeeded(GetDataSource.GetDataSource(IID_IDBInitialize, IInterFace(DBInitialize))) then
        (GetMetadata.GetDatabaseInfo as IZOleDBDatabaseInfo).InitilizePropertiesFromDBInfo(DBInitialize, ZAdoMalloc);

  if not GetMetadata.GetDatabaseInfo.SupportsTransactionIsolationLevel(GetTransactionIsolation) then
    inherited SetTransactionIsolation(GetMetadata.GetDatabaseInfo.GetDefaultTransactionIsolation);
  FAdoConnection.IsolationLevel := IL[GetTransactionIsolation];
  if not AutoCommit then
    StartTransaction;
end;

function TZAdoConnection.GetBinaryEscapeString(const Value: TBytes): String;
begin
  Result := GetSQLHexString(PAnsiChar(Value), Length(Value), True);
end;

function TZAdoConnection.GetBinaryEscapeString(const Value: RawByteString): String;
begin
  Result := GetSQLHexString(PAnsiChar(Value), Length(Value), True);
end;

{**
  Creates a <code>Statement</code> object for sending
  SQL statements to the database.
  SQL statements without parameters are normally
  executed using Statement objects. If the same SQL statement
  is executed many times, it is more efficient to use a
  <code>PreparedStatement</code> object.
  <P>
  Result sets created using the returned <code>Statement</code>
  object will by default have forward-only type and read-only concurrency.

  @param Info a statement parameters.
  @return a new Statement object
}
function TZAdoConnection.CreateRegularStatement(Info: TStrings): IZStatement;
begin
  if IsClosed then Open;
  Result := TZAdoStatement.Create(Self, Info);
end;

{**
  Creates a <code>PreparedStatement</code> object for sending
  parameterized SQL statements to the database.

  A SQL statement with or without IN parameters can be
  pre-compiled and stored in a PreparedStatement object. This
  object can then be used to efficiently execute this statement
  multiple times.

  <P><B>Note:</B> This method is optimized for handling
  parametric SQL statements that benefit from precompilation. If
  the driver supports precompilation,
  the method <code>prepareStatement</code> will send
  the statement to the database for precompilation. Some drivers
  may not support precompilation. In this case, the statement may
  not be sent to the database until the <code>PreparedStatement</code> is
  executed.  This has no direct effect on users; however, it does
  affect which method throws certain SQLExceptions.

  Result sets created using the returned PreparedStatement will have
  forward-only type and read-only concurrency, by default.

  @param sql a SQL statement that may contain one or more '?' IN
    parameter placeholders
  @param Info a statement parameters.
  @return a new PreparedStatement object containing the
    pre-compiled statement
}
function TZAdoConnection.CreatePreparedStatement(
  const SQL: string; Info: TStrings): IZPreparedStatement;
begin
  if IsClosed then Open;
  Result := TZAdoPreparedStatement.Create(Self, SQL, Info)
end;

{**
  Creates a <code>CallableStatement</code> object for calling
  database stored procedures.
  The <code>CallableStatement</code> object provides
  methods for setting up its IN and OUT parameters, and
  methods for executing the call to a stored procedure.

  <P><B>Note:</B> This method is optimized for handling stored
  procedure call statements. Some drivers may send the call
  statement to the database when the method <code>prepareCall</code>
  is done; others
  may wait until the <code>CallableStatement</code> object
  is executed. This has no
  direct effect on users; however, it does affect which method
  throws certain SQLExceptions.

  Result sets created using the returned CallableStatement will have
  forward-only type and read-only concurrency, by default.

  @param sql a SQL statement that may contain one or more '?'
    parameter placeholders. Typically this  statement is a JDBC
    function call escape string.
  @param Info a statement parameters.
  @return a new CallableStatement object containing the
    pre-compiled SQL statement
}
function TZAdoConnection.CreateCallableStatement(const SQL: string; Info: TStrings):
  IZCallableStatement;
begin
  if IsClosed then Open;
  Result := TZAdoCallableStatement2.Create(Self, SQL, Info);
end;

function TZAdoConnection.SavePoint(const AName: String): IZTransaction;
begin
  if Closed then
    raise EZSQLException.Create(cSConnectionIsNotOpened);
  if AutoCommit then
    raise EZSQLException.Create(SInvalidOpInAutoCommit);
  Result := TZAdoSavePoint.Create(AName, Self);
  FSavePoints.Add(Result);
end;

{**
  Sets this connection's auto-commit mode.
  If a connection is in auto-commit mode, then all its SQL
  statements will be executed and committed as individual
  transactions.  Otherwise, its SQL statements are grouped into
  transactions that are terminated by a call to either
  the method <code>commit</code> or the method <code>rollback</code>.
  By default, new connections are in auto-commit mode.

  The commit occurs when the statement completes or the next
  execute occurs, whichever comes first. In the case of
  statements returning a ResultSet, the statement completes when
  the last row of the ResultSet has been retrieved or the
  ResultSet has been closed. In advanced cases, a single
  statement may return multiple results as well as output
  parameter values. In these cases the commit occurs when all results and
  output parameter values have been retrieved.

  @param autoCommit true enables auto-commit; false disables auto-commit.
}
procedure TZAdoConnection.SetAutoCommit(Value: Boolean);
begin
  if Value <> AutoCommit then
    if Closed
    then AutoCommit := Value
    else if Value then begin
      FSavePoints.Clear;
      while FTransactionLevel > 0 do begin
        FAdoConnection.CommitTrans;
        Dec(FTransactionLevel);
      end;
      DriverManager.LogMessage(lcExecute, ConSettings^.Protocol, 'COMMIT');
      AutoCommit := True;
    end else
      StartTransaction;
end;

{**
  Attempts to change the transaction isolation level to the one given.
  The constants defined in the interface <code>Connection</code>
  are the possible transaction isolation levels.

  <P><B>Note:</B> This method cannot be called while
  in the middle of a transaction.

  @param level one of the TRANSACTION_* isolation values with the
    exception of TRANSACTION_NONE; some databases may not support other values
  @see DatabaseMetaData#supportsTransactionIsolationLevel
}
procedure TZAdoConnection.SetTransactionIsolation(
  Level: TZTransactIsolationLevel);
begin
  if TransactIsolationLevel = Level then Exit;
  if not Closed then begin
    FAdoConnection.IsolationLevel := IL[Level];
    if not AutoCommit then
      StartTransaction;
  end;
  TransactIsolationLevel := Level;
end;

{**
  Starts a new transaction. Used internally.
}
function TZAdoConnection.StartTransaction: Integer;
var LogMessage: RawByteString;
  ASavePoint: IZTransaction;
  S: String;
begin
  if Closed then
    Open;
  LogMessage := 'BEGIN TRANSACTION';
  AutoCommit := False;
  try
    if FTransactionLevel = 0 then begin
      FTransactionLevel := FAdoConnection.BeginTrans;
      DriverManager.LogMessage(lcExecute, ConSettings^.Protocol, LogMessage);
      Result := FTransactionLevel;
    end else begin
      Result := FSavePoints.Count+2;
      S := 'SP'+IntToStr(NativeUint(Self))+'_'+IntToStr(Result);
      ASavePoint := SavePoint(S);
    end;
  except
    on E: Exception do begin
      DriverManager.LogError(lcExecute, ConSettings^.Protocol, LogMessage, 0,
       ConvertEMsgToRaw(E.Message, ConSettings^.ClientCodePage^.CP));
      raise EZSQLException.Create(E.Message);
    end;
  end;
end;

{**
  Makes all changes made since the previous
  commit/rollback permanent and releases any database locks
  currently held by the Connection. This method should be
  used only when auto-commit mode has been disabled.
  @see #setAutoCommit
}
procedure TZAdoConnection.Commit;
var LogMessage: RawByteString;
    Tran: IZTransaction;
begin
  if Closed then
    raise EZSQLException.Create(cSConnectionIsNotOpened);
  if AutoCommit then
    raise EZSQLException.Create(SInvalidOpInAutoCommit);
  if Closed then Exit;
  LogMessage := 'COMMIT';
  try
    if FSavePoints.Count > 0 then begin
      Assert(FSavePoints[FSavePoints.Count-1].QueryInterface(IZTransaction, Tran) = S_OK);
      Tran.Commit;
    end else begin
      FAdoConnection.CommitTrans;
      DriverManager.LogMessage(lcExecute, ConSettings^.Protocol, LogMessage);
      FTransactionLevel := 0;
      StartTransaction;
    end;
  except
    on E: Exception do
    begin
      DriverManager.LogError(lcExecute, ConSettings^.Protocol, LogMessage, 0,
       ConvertEMsgToRaw(E.Message, ConSettings^.ClientCodePage^.CP));
      raise;
    end;
  end;
end;

{**
  Drops all changes made since the previous
  commit/rollback and releases any database locks currently held
  by this Connection. This method should be used only when auto-
  commit has been disabled.
  @see #setAutoCommit
}
procedure TZAdoConnection.Rollback;
var
  LogMessage: RawbyteString;
  Tran: IZTransaction;
begin
  if AutoCommit then
    raise EZSQLException.Create(SInvalidOpInAutoCommit);
  LogMessage := 'ROLLBACK';
  if not (AutoCommit or (GetTransactionIsolation = tiNone)) then
  try
    if FSavePoints.Count > 0 then begin
      Assert(FSavePoints[FSavePoints.Count-1].QueryInterface(IZTransaction, Tran) = S_OK);
      Tran.Rollback;
    end else begin
      FAdoConnection.RollbackTrans;
      DriverManager.LogMessage(lcExecute, ConSettings^.Protocol, LogMessage);
      FTransactionLevel := 0;
      StartTransaction;
    end;
  except
    on E: Exception do
    begin
      DriverManager.LogError(lcExecute, ConSettings^.Protocol, LogMessage, 0,
       ConvertEMsgToRaw(E.Message, ConSettings^.ClientCodePage^.CP));
      raise;
    end;
  end;
end;

{**
  Releases a Connection's database and JDBC resources
  immediately instead of waiting for
  them to be automatically released.

  <P><B>Note:</B> A Connection is automatically closed when it is
  garbage collected. Certain fatal errors also result in a closed
  Connection.
}
procedure TZAdoConnection.InternalClose;
var
  LogMessage: RawByteString;
begin
  if Closed or (not Assigned(PlainDriver)) then
    Exit;

  FSavePoints.Clear;
  if not AutoCommit then begin
    SetAutoCommit(True);
    AutoCommit := False;
  end;
  try
    LogMessage := 'CLOSE CONNECTION TO "'+ConSettings^.Database+'"';
    if FAdoConnection.State = adStateOpen then
      FAdoConnection.Close;
//      FAdoConnection := nil;
    DriverManager.LogMessage(lcExecute, ConSettings^.Protocol, LogMessage);
  except
    on E: Exception do begin
      DriverManager.LogError(lcExecute, ConSettings^.Protocol, LogMessage, 0,
       ConvertEMsgToRaw(E.Message, ConSettings^.ClientCodePage^.CP));
      raise;
    end;
  end;
end;

{**
  Sets a catalog name in order to select
  a subspace of this Connection's database in which to work.
  If the driver does not support catalogs, it will
  silently ignore this request.
}
procedure TZAdoConnection.SetCatalog(const Catalog: string);
var
  LogMessage: RawByteString;
begin
  if Closed then Exit;

  LogMessage := 'SET CATALOG '+ConSettings^.ConvFuncs.ZStringToRaw(Catalog, ConSettings^.CTRL_CP, ConSettings^.ClientCodePage^.CP);
  try
    if Catalog <> '' then //see https://sourceforge.net/p/zeoslib/tickets/117/
      FAdoConnection.DefaultDatabase := WideString(Catalog);
    DriverManager.LogMessage(lcExecute, ConSettings^.Protocol, LogMessage);
  except
    on E: Exception do
    begin
      DriverManager.LogError(lcExecute, ConSettings^.Protocol, LogMessage, 0,
       ConvertEMsgToRaw(E.Message, ConSettings^.ClientCodePage^.CP));
      raise;
    end;
  end;
end;

{**
  Returns the Connection's current catalog name.
  @return the current catalog name or null
}
function TZAdoConnection.GetCatalog: string;
begin
  Result := String(FAdoConnection.DefaultDatabase);
end;

function TZAdoConnection.GetServerProvider: TZServerProvider;
begin
  Result := fServerProvider;
end;

{ TZAdoSavePoint }

procedure TZAdoSavePoint.Commit;
var Idx, i: Integer;
  S: WideString;
  Trn: IZTransaction;
begin
  try
    {oracle does not support the "release savepoint <identifier>" syntax.
     the first commit just releases all saveponts.
     MSSQL/Sybase committing all save points if the first COMMIT Transaction is send. identifiers are ignored
     so this is a fake call for those providers }
    if not (FOwner.GetServerProvider in [spOracle, spMSSQL, spASE]) then begin
      S := 'RELEASE SAVEPOINT '+FName;
      FOwner.InternalExecute(S, lcTransaction);
    end;
  finally
    QueryInterface(IZTransaction, Trn);
    idx := FOwner.FSavePoints.IndexOf(Trn);
    if idx <> -1 then
      for I := FOwner.FSavePoints.Count -1 downto idx do
        FOwner.FSavePoints.Delete(I);
  end;
end;

constructor TZAdoSavePoint.Create(const Name: String;
  Owner: TZAdoConnection);
var S: ZWideString;
begin
  inherited Create;
  ConSettings := Owner.ConSettings;
  {$IFNDEF UNICODE}
  fName := ConSettings.ConvFuncs.ZStringToUnicode(Name, ConSettings.CTRL_CP);
  {$ELSE}
  fName := Name;
  {$ENDIF}
  FOwner := Owner;
  if FOwner.GetServerProvider in [spMSSQL, spASE]
  then S := 'SAVE TRANSACTION '+FName
  else S := 'SAVEPOINT '+FName;
  FOwner.InternalExecute(S, lcTransaction);
end;

procedure TZAdoSavePoint.Rollback;
var Idx, i: Integer;
  S: WideString;
begin
  try
    if FOwner.GetServerProvider in [spMSSQL, spASE]
    then S := 'ROLLBACK TRANSACTION '+FName
    else S := 'ROLLBACK TO '+FName;
    FOwner.InternalExecute(S, lcTransaction);
  finally
    idx := FOwner.FSavePoints.IndexOf(Self as IZTransaction);
    if idx <> -1 then
      for I := FOwner.FSavePoints.Count -1 downto idx do
        FOwner.FSavePoints.Delete(I);
  end;
end;

function TZAdoSavePoint.SavePoint(const AName: String): IZTransaction;
begin
  Result := TZAdoSavePoint.Create(AName, FOwner);
  FOwner.FSavePoints.Add(Result);
end;

initialization
  AdoCoInitialized := 0;
  AdoDriver := TZAdoDriver.Create;
  DriverManager.RegisterDriver(AdoDriver);
finalization
  if Assigned(DriverManager) then
    DriverManager.DeregisterDriver(AdoDriver);
  AdoDriver := nil;
{$ENDIF ZEOS_DISABLE_ADO}
end.