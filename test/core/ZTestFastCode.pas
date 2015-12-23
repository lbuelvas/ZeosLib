{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{            Test Case for Utility Functions              }
{                                                         }
{         Originally written by Sergey Merkuriev          }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2006 Zeos Development Group       }
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
{   http://zeosbugs.firmos.at (BUGTRACKER)                }
{   svn://zeos.firmos.at/zeos/trunk (SVN Repository)      }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{   http://www.zeoslib.sourceforge.net                    }
{                                                         }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit ZTestFastCode;

interface

{$I ZCore.inc}

uses {$IFDEF FPC}testregistry{$ELSE}TestFramework{$ENDIF}, SysUtils,
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  ZTestCase, ZSysUtils, ZClasses, ZVariant, ZMatchPattern, ZCompatibility;

type
  TZTestFastCodeCase = class(TZGenericTestCase)
  published
    procedure TestValRawExt;
  end;

implementation

uses ZFastCode;

{ TZTestFastCodeCase }

procedure TZTestFastCodeCase.TestValRawExt;
const EValues: array[0..9] of Extended = (11111.1111, 3.402823466E+38,
  3.402823466E+38, 1.7976931348623157E+308, 21474836.47, 99999.9999,
  1.175494351E-38, 1.175494351E-38, 2.2250738585072014E-308, 21474836.47);
const PValues: array[0..High(EValues)] of PAnsiChar = ('11111.1111', '3.402823466E+38',
  '3.402823466E+38', '1.7976931348623157E+308', '21474836.47', '99999.9999',
  '1.175494351E-38', '1.175494351E-38', '2.2250738585072014E-308', '21474836.47');
var I, Code: Integer;
begin
  for i := low(EValues) to high(EValues) do
     Check({EValues[i], }ValRawExt(PValues[i], '.', Code) <> 0, 'Falied conversion of '+String(PValues[i]));
end;

initialization
  RegisterTest('core',TZTestFastCodeCase.Suite);
end.