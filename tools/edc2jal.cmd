/* ------------------------------------------------------------------------ *
 * Title: Edc2Jal.cmd - Create JalV2 device specifications for flash PICs   *
 *                                                                          *
 * Author: Rob Hamerling, Copyright (c) 2013..2013, all rights reserved.    *
 *                                                                          *
 * Adapted-by:                                                              *
 *                                                                          *
 * Revision: $Revision$                                                     *
 *                                                                          *
 * Compiler: N/A                                                            *
 *                                                                          *
 * This file is part of jallib  http://jallib.googlecode.com                *
 * Released under the BSD license                                           *
 *              http://www.opensource.org/licenses/bsd-license.php          *
 *                                                                          *
 * Description:                                                             *
 *   Rexx script to create device specifications for JALV2, and             *
 *   the file chipdef_jallib.jal, included by each of these.                *
 *   Input are .edc files: expanded MPLAB-X .pic files.                     *
 *   Apart from declaration of all registers, register-subfields, ports     *
 *   and pins of the chip the device files contain shadowing procedures     *
 *   to prevent the 'read-modify-write' problems and use the LATx register  *
 *   (for PICs which have such registers) for output in stead of PORTx.     *
 *   In addition some device dependent procedures are provided              *
 *   for common operations, like enable_digital_io().                       *
 *   Also various aliases are declared to 'normalize' the names of          *
 *   registers and bit fields, which makes it easier to build device        *
 *   independent libraries.                                                 *
 *                                                                          *
 * Sources:  MPLAB-X .pic files  (preprocessed by pic2edc script).          *
 *           MPLAB-X .lkr files  (via devicespecific.json)                  *
 *                                                                          *
 * Notes:                                                                   *
 *   - This script is written in 'classic' Rexx as delivered with           *
 *     eComStation (OS/2) and is executed on a system with eCS 2.1 or 2.2.  *
 *     With only minor changes it can be executed on a different system,    *
 *     or even a different platform (Linux, Windows) with "Regina Rexx"     *
 *     Ref:  http://regina-rexx.sourceforge.net/                            *
 *     See the embedded comments below for instructions for possibly        *
 *     required changes. You don't have to look further than the line which *
 *     says "Here the device file generation actually starts" (approx 125). *
 *   - A summary of changes of this script is maintained in 'changes.txt'   *
 *     (not published, available on request).                               *
 *                                                                          *
 * ------------------------------------------------------------------------ */
   ScriptVersion   = '0.0.09'
   ScriptAuthor    = 'Rob Hamerling'
   CompilerVersion = '2.4q'
/* MPlabXVersion obtained from file VERSION.xxx created by Pic2edc script.  */
/* ------------------------------------------------------------------------ */

/* 'msglevel' controls the amount of messages being generated */
/*   0 - progress messages, info, warnings and errors         */
/*   1 - info, warnings and errors                            */
/*   2 - warnings and errors                                  */
/*   3 - errors (always reported!)                            */

msglevel = 2

/* 'debuglevel' controls specific debug info                  */
/*   0 - no debugging output                                  */
/*   1 - debugging output of ...                              */
/*   2 - debugging output of ...                              */

debuglevel = 1

call RxFuncAdd 'SysLoadFuncs', 'RexxUtil', 'SysLoadFuncs'
call SysLoadFuncs                                           /* load Rexx utilities */

Call SysFileTree 'VERSION.*', 'dir.', 'FO'           /* search mplab-x version */
if dir.0 = 0 then do
   call msg 3, 'Could not find the VERSION.* file'
   return 2
end
MPlabXVersion = right(dir.1,3)

/* MPLAB-X and a local copy of the Jallib SVN tree should be installed.        */
/* The .PIC files used are in [basedir]/MPLAB_IDE/BIN/LIB/CROWNKING.EDC.JAR.   */
/* This file must be expanded (unZIPped) to obtain the individual .pic files,  */
/* and be processed by the Pic2edc files.                                      */
/* Directory of expanded MPLAB-X .pic files:  */

edcdir        = './edc.'MPlabXVersion                       /* source of expanded .pic files */

/* Some information is collected from files in JALLIB tools directory */

JALLIBbase    = 'k:/jallib/'                       /* JALLIB base directory (local) */
DevSpecFile   = JALLIBbase'tools/devicespecific.json'       /* device specific data */
PinMapFile    = JALLIBbase'tools/pinmap_pinsuffix.json'     /* pin aliases */
FuseDefFile   = JALLIBbase'tools/fusedefmap.cmd'            /* fuse_def mapping (Fosc) */
DataSheetFile = JALLIBbase'tools/datasheet.list'            /* actual datasheets */

call msg 0, 'Pic2Jal version' ScriptVersion '  -  ' ScriptAuthor '  -  ' date('N')';' time('N')
if msglevel > 2 then
   call msg 0, 'Only reporting errors!'

/* The destination of the generated device files depends on the first    */
/* mandatory commandline argument, which must be 'PROD' or 'TEST'        */
/*  - with 'PROD' the files go to directory "<JALLIBbase>include/device" */
/*  - with 'TEST' the files go to directory "./test>"                    */
/* Note: Before creating new device files all .jal files are             */
/*       removed from the destination directory.                         */

parse upper arg destination selection .                     /* commandline arguments */

if destination = 'PROD' then                                /* production run */
   dstdir = JALLIBbase'include/device'                      /* local Jallib */
else if destination = 'TEST' then do                        /* test run */
   dstdir = './test'                                        /* subdir for testing */
   rx = SysMkDir(dstdir)                                    /* create destination dir */
   if rx \= 0 & rx \= 5 then do                             /* not created, not existing */
      call msg 3, rx 'while creating destination directory' dstdir
      return rx                                             /* unrecoverable: terminate */
   end
end
else do
   call msg 3, 'Required argument missing: "prod" or "test"',
               ' and optionally wildcard.'
   return 1
end

/* The optional second commandline argument designates for which PICs device */
/* files must be generated. This argument is only accepted in a 'TEST' run.  */
/* The selection may contain wildcards like '18LF*', default is '*' (all).   */
/* Regardless the selection only flash PICs are processed.                   */

if selection = '' then                                      /* no selection spec'd */
   wildcard = '1*.edc'                                      /* default (8 bit PICs) */
else if destination = 'TEST' then                           /* TEST run */
   wildcard = selection'.edc'                               /* accept user selection */
else do                                                     /* PROD run with selection */
   call msg 3, 'No selection allowed for production run!'
   return 1                                                 /* unrecoverable: terminate */
end

/* ------ Here the device file generation actually starts ------------------------ */

call time 'R'                                               /* reset 'elapsed' timer */

call msg 0, 'Creating Jallib device files with MPLAB-X version',
             MPlabXVersion%100'.'MPlabXVersion//100

call SysFileTree edcdir'/'wildcard, 'dir.', 'FOS'           /* search all .edc files */
if dir.0 = 0 then do
   call msg 3, 'No .edc files found matching <'wildcard'> in' edcdir
   return 0                                                 /* nothing to do */
end
call SysStemSort 'dir.', 'A', 'I'                           /* sort on name (alpha, incremental) */

signal on syntax name catch_syntax                          /* catch syntax errors */
signal on error  name catch_error                           /* catch execution errors */

DevSpec. = '?'                                              /* default PIC specific data */
if file_read_devspec() \= 0 then                            /* read device specific data */
   return 1                                                 /* terminate with error */

PinMap.   = '?'                                             /* pin mapping data */
PinANMap. = '-'                                             /* pin_ANx -> RXy mapping */
if file_read_pinmap() \= 0 then                             /* read pin alias names */
   return 1                                                 /* terminate with error */

Fuse_Def. = '?'                                             /* Fuse_Def name mapping */
if file_read_fusedef() \= 0 then                            /* read fuse_def table */
   return 1                                                 /* terminate with error */

call SysFileTree dstdir'/*.jal', 'jal.', 'FO'               /* .jal files in destination */
do i = 1 to jal.0                                           /* all .jal files */
   call SysFileDelete jal.i                                 /* remove */
end

chipdef = dstdir'/chipdef_jallib.jal'                       /* common include for device files */
if stream(chipdef, 'c', 'open write') \= 'READY:' then do   /* new chipdef file */
   call msg 3, 'Could not create common include file' chipdef
   return 1                                                 /* unrecoverable: terminate */
end
call list_chipdef_header                                    /* create header of chipdef file */

xChipDef. = '?'                                             /* collection of dev IDs in chipdef */

ListCount = 0                                               /* # created device files */
SpecMissCount = 0                                           /* # missing in devicespecific.json */
DSMissCount = 0                                             /* # missing datasheet */
PinmapMissCount = 0                                         /* # missing in pinmap */

do i = 1 to dir.0                                           /* all relevant .edc files */
                                                            /* init for each new PIC */
   DevFile = tolower(translate(dir.i,'/','\'))              /* lower case + forward slashes */
   parse value filespec('Name', DevFile) with PicName '.edc'
   if PicName = '' then do
      call msg 3, 'Could not derive PIC name from filespec: "'DevFile'"'
      leave                                                 /* setup error: terminate */
   end

   if \(substr(PicName,3,1) = 'f'    |,                     /* not flash PIC or */
        substr(PicName,3,2) = 'lf'   |,                     /*     low power flash PIC or */
        substr(PicName,3,2) = 'hv')  |,                     /*     high voltage flash PIC */
      PicName = '16hv540' then do                           /* OTP */
      iterate                                               /* skip */
   end

   call msg 0, PicName                                      /* progress signal */

   PicNameCaps = toupper(PicName)
   if DevSpec.PicNameCaps.DataSheet = '?' then do
      call msg 2, 'Not listed in' DevSpecFile', no device file generated'
      SpecMissCount = SpecMissCount + 1
      iterate                                               /* skip */
   end
   else if DevSpec.PicNameCaps.DataSheet = '-' then do
      call msg 1, 'No datasheet found in' DevSpecFile', no device file generated'
      DSMissCount = DSMissCount + 1
      iterate                                               /* skip */
   end
   if PinMap.PicNameCaps \= PicNameCaps then do             /* Name mismatch */
      call msg 2, 'No Pinmapping found in' PinMapFile
      PinmapMissCount = PinmapMissCount + 1                 /* count misses */
      iterate                                               /* skip */
   end

   Pic. = ''                                                /* reset .pic file contents */
   edcfile = edcdir'/'PicName'.edc'
   do j = 1 while lines(edcfile)                            /* read edc file */
      Pic.j = linein(edcfile)
   end                                                      /* error with read */
   Pic.0 = j - 1
   call stream edcfile, 'c', close

   Ram.                  = ''                               /* sfr usage and mirroring */
   Name.                 = '-'                              /* register and subfield names */
   CfgAddr.              = ''                               /* config memory addresses (decimal) */
   Cfgmem                = ''                               /* config string */

   DevID                 = '0000'                           /* no device ID */
   NumBanks              = 0                                /* # memory banks */
   StackDepth            = 0                                /* hardware stack depth */
   AccessBankSplitOffset = 128                              /* 0x80 (18Fs) */
   CodeSize              = 0                                /* amount of program memory */
   DataSize              = 0                                /* amount of data memory (RAM) */
   EESpec                = ''                               /* EEPROM: hexaddr,size (dec) */
   IDSpec                = ''                               /* ID bytes: hexaddr,size (dec) */
   VddRange              = 0                                /* working voltage range */
   VddNominal            = 0                                /* nominal working voltage */
   VppRange              = 0                                /* programming voltage range */
   VppDefault            = 0                                /* default programming voltage */

   ADCS_bits             = 0                                /* # ADCONx_ADCS bits */
   ADC_highres           = 0                                /* 0 = has no ADRESH register */
   IRCF_bits             = 0                                /* # OSCCON_IRCF bits */
   HasLATreg             = 0                                /* zero LAT registers found (yet) */
                                                            /* used for extended midrange only */
   HasMuxedSFR           = 0                                /* zero multiplexed SFRs found(yet) */
   OSCCALaddr            = 0                                /* address of OSCCAL (>0 if present!)  */
   FSRaddr               = 0                                /* address of FSR (>0 if present!)  */


   /* -------- collect some basic information ------------ */

   core = load_config_info()                                /* core + various cfg info */

   /* -------- set core-dependent properties ------------ */

   select
      when core = '12' then do                              /* baseline */
         MaxRam       = 128                                 /* range 0..0x7F */
         BankSize     = 32                                  /* 0x0020 */
         PageSize     = 512                                 /* 0x0200 */
      end
      when core = '14' then do                              /* classic midrange */
         MaxRam       = 512                                 /* range 0..0x1FF */
         BankSize     = 128                                 /* 0x0080 */
         PageSize     = 2048                                /* 0x0800 */
      end
      when core = '14H' then do                             /* enhance midrange (Hybrid) */
         MaxRam       = 4096                                /* range 0..0xFFF */
         BankSize     = 128                                 /* 0x0080 */
         PageSize     = 2048                                /* 0x0800 */
      end
      when core = '16' then do                              /* 18Fs */
         MaxRam       = 4096                                /* range 0..0xFFF */
         BankSize     = 256                                 /* 0x0100 */
      end
   otherwise                                                /* other or undetermined core */
      call msg 3, 'Unsupported core:' Core,                 /* report detected Core */
                  'Internal script error, terminating ....'
      call msg 0, Pic.0 ':' Pic.1
      leave                                                 /* script error: terminate */
   end

   call load_sfr                                            /* SFR addressing */

   /* ------------ produce device file ------------------------ */

   jalfile = dstdir'/'PicName'.jal'                         /* device filespec */
   if stream(jalfile, 'c', 'open write') \= 'READY:' then do
      call msg 3, 'Could not create device file' jalfile
      leave                                                 /* unrecoverable error */
   end

   parse var DevSpec.PicNameCaps.SHARED '0x' addr1 '-' '0x' addr2
   SharedMem.0 = x2d(addr2) - x2d(addr1) + 1                /* # bytes of shared memory */
   SharedMem.1 = x2d(addr1)                                 /* lowest address (decimal) */
   SharedMem.2 = x2d(addr2)                                 /* highest */

   call list_head                                           /* common header */
   call list_cfgmem                                         /* cfg mem addr + defaults */

   select
      when core = '12' then do                              /* baseline */
         if OSCCALaddr > 0 then                             /* OSCCAL present */
            call list_osccal                                /* INTRC calibration */
         call list_sfr
         if HasMuxedSFR > 0 then
            call list_muxed_sfr
         call list_nmmr12
      end
      when core = '14' then do                              /* midrange */
/*       if OSCCALaddr > 0 then      */                     /* OSCCAL present */
/*          call list_osccal         */                     /* TOO DANGEROUS (INTRC calibration) */
         call list_sfr
         if HasMuxedSFR > 0 then
            call list_muxed_sfr
         call list_nmmr14
      end
      when core = '14H' then do                             /* extended midrange (Hybrids) */
         call list_sfr
         if HasMuxedSFR > 0 then
            call list_muxed_sfr
      end
      when core = '16' then do                              /* 18Fs */
         call list_sfr
         if HasMuxedSFR > 0 then
            call list_muxed_sfr
/*       call list_nmmr   */
      end
   end

   call list_analog_functions                               /* common enable_digital_io() */

   call list_fusedef                                        /* pragma fusedef */

   call stream jalfile, 'c', 'close'                        /* done with this PIC */

   ListCount = ListCount + 1;                               /* count generated device files */

end

call lineout chipdef, '--'                                  /* last line */
call stream  chipdef, 'c', 'close'                          /* done */

call msg 0, ''                                              /* empty line */
ElapsedTime = time('E')
if ElapsedTime > 0 then
   call msg 1, 'Generated' listcount 'device files in' format(ElapsedTime,,2) 'seconds',
               ' ('format(listcount/ElapsedTime,,1) 'per second)'
if SpecMissCount > 0 then
   call msg 3, SpecMissCount 'device files not created because PIC not in' DevSpecFile
if DSMissCount > 0 then
   call msg 3, DSMissCount 'device files not created because no datasheet in' DevSpecFile
if PinmapMissCount > 0 then
   call msg 3, PinmapMissCount 'occurences of missing pin mapping in' PinmapFile

signal off error
signal off syntax                                           /* restore to default */

call SysDropFuncs                                           /* release Rexxutil */

return 0

/* ---------- This is the end of the mainline of dev2jal --------------- */




/* -------------------------------------------- */
/* procedure to collect various elementary      */
/* information and figures.                     */
/* input:   - nothing                           */
/* output:  - nothing                           */
/* returns: core (0, '12', '14', '14H', '16')   */
/* -------------------------------------------- */
load_config_info: procedure expose Pic. PicName,
                                   StackDepth NumBanks AccessBankSplitOffset,
                                   CodeSize EESpec IDSpec DevID CfgAddr. Cfgmem,
                                   VddRange VddNominal VppRange VppDefault,
                                   HasLATreg HasMuxedSFR OSCCALaddr FSRaddr,
                                   ADC_highres ADCS_bits IRCF_bits
CfgAddr.0 = 0                                               /* empty */
Core = 0                                                    /* undetermined */
CodeSize = 0                                                /* no code memory */
NumBanks = 0                                                /* no databanks */
SFRaddr = 0                                                 /* start of SFRs */

do i = 1 to Pic.0

   kwd = word(Pic.i,1)                                      /* selection keyword */

   select

      when pos('<EDC:PIC', Pic.i) > 0 then do
         parse var Pic.i . 'EDC:ARCH="' Val1 '"' .
         if Val1 \= '' then do
            if      Val1 = '16C5X' then
               Core = '12'
            else if Val1 = '16XXXX' then
               Core = '14'
            else if Val1 = '16EXXX' then
               Core = '14H'
            else if Val1 = '18XXXX' then
               Core = '16'
            else do                                         /* otherwise */
               msg 3, 'Unrecognized core type:' Val1', terminated!'
               exit 3
            end
         end
      end

      when kwd = '<EDC:VPP' then do
         parse var Pic.i '<EDC:VPP' 'EDC:DEFAULTVOLTAGE="' Val1 '"',
                          'EDC:MAXVOLTAGE="' Val2 '"' 'EDC:MINVOLTAGE="' Val3 '"' .
         if Val1 \= '' then do
            VppDefault = strip(Val1)
            VppRange = strip(Val3)'-'strip(Val2)
         end
      end

      when kwd = '<EDC:VDD' then do
         parse var Pic.i '<EDC:VDD' 'EDC:MAXDEFAULTVOLTAGE="' Val1 'EDC:MAXVOLTAGE="' Val2 '"',
                          'EDC:MINDEFAULTVOLTAGE="' Val3 'EDC:MINVOLTAGE="' Val4 '"',
                          'EDC:NOMINALVOLTAGE="' Val5 '"' .
         if Val1 \= '' then do
            VddRange = strip(Val4)'-'strip(Val2)
            VddNominal = strip(Val5)
         end
      end

      when kwd = '<EDC:MEMTRAITS' then do
         parse var Pic.i '<EDC:MEMTRAITS',
                          'EDC:BANKCOUNT="' Val1 '"' 'EDC:HWSTACKDEPTH="' Val2 '"' .
         if Val1 \= '' then do
            Val1 = strip(Val1)                              /* hex or dec */
            if left(Val1,2) = '0X' then
               Val1 = X2D(substr(Val1,3))
            NumBanks = Val1
         end
         else
            parse var Pic.i '<EDC:MEMTRAITS' 'EDC:HWSTACKDEPTH="' Val2 '"' .
         if Val2 \= '' then
            StackDepth = val2                               /* dec only */
      end

      when kwd = '<EDC:CONFIGFUSESECTOR' |,
           kwd = '<EDC:WORMHOLESECTOR' then do
         if kwd = '<EDC:CONFIGFUSESECTOR' then
            parse var Pic.i '<EDC:CONFIGFUSESECTOR',
                          'EDC:BEGINADDR="0X' Val1 '"' 'EDC:ENDADDR="0X' Val2 '"' .
         else
            parse var Pic.i '<EDC:WORMHOLESECTOR',
                             'EDC:BEGINADDR="0X' Val1 '"' 'EDC:ENDADDR="0X' Val2 '"' .
         if Val1 \= '' then do
            Val1 = X2D(Val1)                                /* take decimal values */
            Val2 = X2D(Val2)
            CfgAddr.0 = Val2 - Val1                         /* number of config words/bytes */
            do j = 1 to CfgAddr.0                           /* all of 'm */
               CfgAddr.j = Val1 + j - 1                     /* address (decimal) */
            end
         end
         FuseOffset = 0
         do i = i until (word(Pic.i,1) = '</EDC:CONFIGFUSESECTOR>' |,
                         word(Pic.i,1) = '</EDC:WORMHOLESECTOR>')
            select
               when word(Pic.i,1) = '<EDC:ADJUSTPOINT'then do
                  parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' val1 '"' .
                  if val1 \= '' then do
                     val1 = strip(val1)                     /* hex or dec */
                     if left(Val1,2) = '0X' then
                        Val1 = X2D(substr(Val1,3))
                     FuseOffset = FuseOffset + Val1         /* adjust */
                     Cfgmem = Cfgmem'00'                    /* concat unimplemented byte */
                  end
               end
               when word(Pic.i,1) = '<EDC:DCRDEF' then do
                  parse var Pic.i '<EDC:DCRDEF' . 'EDC:IMPL="0X' val1 '"' . ,
                                   'EDC:NZWIDTH="' val2 '"' .
                  if val1 \= '' then do
                     val2 = strip(val2)                     /* hex or dec */
                     if left(val2,2) = '0X' then
                        val2 = X2D(substr(val2,3))
                     if val2 \= 8 | val2 \= 16 then do
                        call msg 2, 'Unusual config word size <'val2'>, corrected!'
                        if core = 16 then
                           val2 = 8                         /* byte for 18Fs */
                        else
                           val2 = 16                        /* word otherwise */
                     end
                     newfuse = right(val1,val2/4,'0')       /* 2 or 4 hex chars */
                     if Core = '14'  | Core = '14H' then
                        newfuse = right(C2X(BITOR(X2C(newfuse),X2C('3FFF'))),val2/4,'0')
                     Cfgmem = Cfgmem||newfuse               /* concat byte/word */
                  end
                  do while word(Pic.i,1) \= '</EDC:DCRMODELIST>'
                     i = i + 1                              /* skip inner statements */
                  end
               end
            otherwise
               nop
            end
         end
      end

      when kwd = '<EDC:CODESECTOR' then do
         parse var Pic.i '<EDC:CODESECTOR',
                          'EDC:BEGINADDR="0X' Val1 '"' 'EDC:ENDADDR="0X' Val2 '"' .
         if Val1 \= '' then
            CodeSize = CodeSize + X2D(Val2) - X2D(Val1)
      end

      when kwd = '<EDC:DEVICEIDSECTOR' then do
         parse var Pic.i '<EDC:DEVICEIDSECTOR' . 'EDC:MASK="0X' Val1 '"' . 'EDC:VALUE="0X' Val2 '"' .
         if Val1 \= '' then do
            RevMask = right(strip(Val1),4,'0')                    /* 4 hex chars */
            DevID = right(strip(Val2),4,'0')                      /* 4 hex chars */
            DevID = C2X(bitand(X2C(DevID),X2C(RevMask)))          /* reset revision bits */
         end
         else do                                                  /* no revision mask */
            parse var Pic.i '<EDC:DEVICEIDSECTOR' . 'EDC:VALUE="0X' Val1 '"' .
            if Val1 \= '' then
               DevID = right(strip(Val1),4,'0')                   /* 4 hex chars */
         end
      end

      when kwd = '<EDC:USERIDSECTOR' then do
         parse var Pic.i '<EDC:USERIDSECTOR',
                          'EDC:BEGINADDR="0X' Val1 '"' 'EDC:ENDADDR="0X' Val2 '"' .
         if Val1 \= '' then
            IDSpec = '0x'strip(val1)','X2D(val2) - X2D(val1)
      end

      when kwd = '<EDC:EEDATASECTOR' then do
         parse var Pic.i '<EDC:EEDATASECTOR' ,
                          'EDC:BEGINADDR="0X' Val1 '"' 'EDC:ENDADDR="0X' Val2 '"' .
         if Val1 \= '' then
            EESpec = '0x'Val1','X2D(Val2) - X2D(Val1)
      end

      when kwd = '<EDC:SFRDATASECTOR' then do
         parse var Pic.i '<EDC:SFRDATASECTOR' 'EDC:BANK="' val1 '"',
                          'EDC:BEGINADDR="0X' Val2 '"' .
         if Val1 \= '' then do
            Val1 = strip(Val1)
            if left(Val1,2) = '0X' then
               Val1 = X2D(substr(Val1,3))
            if NumBanks < Val1 + 1 then                  /* new larger than previous */
               Numbanks = Val1 + 1
         end
         if Val2 \= '' then
            SFRaddr = X2D(Val2)
      end

      when kwd = '<EDC:EXTENDEDMODEONLY>' then do        /* skip extended mode features */
         do until word(Pic.i,1) = '</EDC:EXTENDEDMODEONLY>'
            i = i + 1
         end
      end

      when kwd = '<EDC:PINLIST>' then do                 /* skip pin descriptions */
         do until word(Pic.i,1) = '</EDC:PINLIST>'
            i = i + 1
         end
      end

      when kwd = '<EDC:GPRDATASECTOR' then do
         parse var Pic.i '<EDC:GPRDATASECTOR' 'EDC:BANK="' val1 '"' ,
                          'EDC:BEGINADDR="0X' Val2 '"' 'EDC:ENDADDR="0X' Val3 '"' .
         if Val1 \= '' then do
            Val1 = strip(Val1)                           /* hex or dec */
            if left(Val1,2) = '0X' then
               Val1 = X2D(substr(Val1,3))
            if NumBanks < Val1 + 1 then                  /* new larger than previous */
               Numbanks = Val1 + 1
            if Val1 = 0  &  X2D(Val2) = 0 then           /* first part of access bank */
               AccessBankSplitOffset = X2D(Val3)
         end
         else do                                         /* no bank specification */
            parse var Pic.i '<EDC:GPRDATASECTOR' ,
                             'EDC:BEGINADDR="0X' Val1 '"' 'EDC:ENDADDR="0X' Val2 '"' .
            if Val1 \= '' then do
               Val1 = strip(Val1)                        /* hex or dec */
               if left(Val1,2) = '0X' then
                  Val1 = X2D(substr(Val1,3))
               if Val1 = 0 then                          /* first part of access bank */
                  AccessBankSplitOffset = X2D(Val2)
            end
         end
      end

      when kwd = '<EDC:MUXEDSFRDEF' then do
         do while word(Pic.i,1) \= '</EDC:MUXEDSFRDEF>'
            if word(Pic.i,1) = '<EDC:SFRDEF' then do
               parse var Pic.i '<EDC:SFRDEF' . 'EDC:CNAME="' val1 '"' .
               reg = strip(val1)
               if left(reg,5) = 'ADCON' then do          /* ADCONx register */
                  do while word(pic.i,1) \= '</EDC:SFRMODELIST>'  /* till end subfields */
                     if word(Pic.i,1) = '<EDC:SFRMODE' then do    /* new set of subfields */
                        parse var Pic.i '<EDC:SFRMODE' 'EDC:ID="' Val1 '"' .
                        if Val1 = 'DS.0' then do               /* check only one SFRmode */
                           do while word(pic.i,1) \= '</EDC:SFRMODE>'
                              if word(pic.i,1) = '<EDC:SFRFIELDDEF' then do
                                 parse var Pic.i '<EDC:SFRFIELDDEF' . 'EDC:CNAME="' Val1 '"' . ,
                                                  'EDC:NZWIDTH="' Val2 '"' .
                                 Val1 = strip(Val1)
                                 if left(Val1,4) = 'ADCS' then do          /* ADCS field */
                                    Val2 = strip(Val2)
                                    if left(Val2,2) = '0X' then
                                       Val2 = X2D(substr(Val2,3))
                                    ADCS_bits = ADCS_bits + Val2           /* count ADCS bits */
                                 end
                              end
                              i = i + 1
                           end
                        end
                     end
                     i = i + 1
                  end
               end
            end
            i = i + 1
         end
         HasMuxedSFR = HasMuxedSFR + 1                   /* count */
         SFRaddr = SFRaddr + 1                           /* muxed SFRs count for 1 */
      end

      when kwd = '<EDC:SFRDEF' then do
         parse var Pic.i '<EDC:SFRDEF' . 'EDC:CNAME="' Val1 '"' .
         reg = strip(Val1)
         if reg = 'OSCCAL' then
            OSCCALaddr = SFRaddr                         /* store addr (dec) */
         else if left(reg,3) = 'LAT' then
            HasLATreg = HasLATReg + 1                    /* count LATx registers */
         else if reg = 'FSR' then
            FSRaddr = SFRaddr                            /* store addr (dec) */
         else if reg = 'ADRESH' | reg = 'ADRES0H' then
            ADC_highres = 1                              /* has high res ADC */
         else if left(reg,5) = 'ADCON' then do          /* ADCONx register */
            do while word(pic.i,1) \= '</EDC:SFRMODELIST>'  /* till end subfields */
               if word(Pic.i,1) = '<EDC:SFRMODE' then do    /* new set of subfields */
                  parse var Pic.i '<EDC:SFRMODE' 'EDC:ID="' Val1 '"' .
                  if Val1 = 'DS.0' then do               /* check only one SFRmode */
                     do while word(pic.i,1) \= '</EDC:SFRMODE>'
                        if word(pic.i,1) = '<EDC:SFRFIELDDEF' then do
                           parse var Pic.i '<EDC:SFRFIELDDEF' . 'EDC:CNAME="' Val1 '"' . ,
                                            'EDC:NZWIDTH="' Val2 '"' .
                           Val1 = strip(Val1)
                           if left(Val1,4) = 'ADCS' then do          /* ADCS field */
                              Val2 = strip(Val2)
                              if left(Val2,2) = '0X' then
                                 Val2 = X2D(substr(Val2,3))
                              ADCS_bits = ADCS_bits + Val2           /* count ADCS bits */
                           end
                        end
                        i = i + 1
                     end
                  end
               end
               i = i + 1
            end
         end
         else if reg = 'OSCCON' then do                    /* OSCCON register */
            do while word(pic.i,1) \= '</EDC:SFRMODELIST>'  /* till end subfields */
               if word(pic.i,1) = '<EDC:SFRFIELDDEF' then do
                  parse var Pic.i '<EDC:SFRFIELDDEF' . 'EDC:CNAME="' Val1 '"' .,
                                            'EDC:NZWIDTH="' Val2 '"' .
                  Val1 = strip(Val1)
                  if left(Val1,4) = 'IRCF' then do             /* IRCF field */
                     Val2 = strip(Val2)
                     if left(Val2,2) = '0X' then
                        Val2 = X2D(substr(Val2,3))
                     if val2 = 1 then                          /* single bit */
                        IRCF_bits = IRCF_bits + Val2           /* count enumerated IRCF bits */
                     else                                      /* mult-bit field */
                        IRCF_bits = Val2                       /* # IRCF bits */
                  end
               end
               i = i + 1
            end
         end
         do while word(pic.i,1) \= '</EDC:SFRDEF>'
            i = i + 1                                 /* skip subfields */
         end
         SFRaddr = SFRaddr + 1
      end

      when kwd = '<EDC:MIRROR' then do
         parse var Pic.i '<EDC:MIRROR' 'EDC:NZSIZE="' Val1 '"' .
         if Val1 \= '' then do
            Val1 = strip(Val1)                           /* hex or dec */
            if left(Val1,2) = '0X' then
               Val1 = X2D(substr(Val1,3))
            SFRaddr = SFRaddr + Val1
         end
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' Val1 '"' .
         if Val1 \= '' then do
            Val1 = strip(Val1)                           /* hex or dec */
            if left(Val1,2) = '0X' then
               Val1 = X2D(substr(Val1,3))
            SFRaddr = SFRaddr + Val1
         end
      end

   otherwise
      nop                                                /* ignore */
   end

end
return core


/* ---------------------------------------------------------- */
/* procedure to build special function register array         */
/* with mirror info and unused registers                      */
/* input:  - nothing                                          */
/* output: nothing                                            */
/* ---------------------------------------------------------- */
load_sfr: procedure expose Pic. Name. Ram. core,
                           NumBanks BankSize MaxRam msglevel
do i = 0 to NumBanks*Banksize                            /* whole range */
   Ram.i = -1                                            /* mark address as unused */
end

SFRaddr = 0                                              /* start value */

do i = 1 while \(word(Pic.i,1) = '<EDC:DATASPACE'   |,    /* search start of dataspace */
                 word(Pic.i,1) = '<EDC:DATASPACE>')
   nop
end

do i = i while word(Pic.i,1) \= '</EDC:DATASPACE>'       /* to end of data */

   kwd = word(Pic.i,1)                                   /* selection keyword */

   select

      when kwd = '<EDC:SFRDATASECTOR' then do
         parse var Pic.i '<EDC:SFRDATASECTOR' 'EDC:BEGINADDR="0X' Val1 '"' .
         if Val1 \= '' then
            SFRaddr = X2D(Val1)
      end

      when kwd = '<EDC:MUXEDSFRDEF' then do
         Ram.SFRaddr = SFRaddr
         do while word(Pic.i,1) \= '</EDC:MUXEDSFRDEF>'
            i = i + 1
         end
         SFRaddr = SFRaddr + 1                           /* muxed SFRs count for 1 */
      end

      when kwd = '<EDC:SFRDEF' then do
         Ram.SFRaddr = SFRaddr
         do while word(pic.i,1) \= '</EDC:SFRDEF>'
            i = i + 1                                 /* skip subfields */
         end
         SFRaddr = SFRaddr + 1
      end

      when kwd = '<EDC:MIRROR' then do
         parse var Pic.i '<EDC:MIRROR' 'EDC:NZSIZE="' val1 '"' . 'EDC:REGIONIDREF="' Val2 '"' .
         if Val1 \= '' then do
            val1 = strip(Val1)                           /* hex or dec */
            if left(val1,2) = '0X' then
               Val1 = X2D(substr(Val1,3))
            do j = 0 to val1 - 1
               BaseBank = right(val2,1)                  /* base bank of SFR */
               baseaddr = BaseBank * BankSize + (SFRaddr // Banksize)   /* base addr */
               Ram.SFRaddr = baseaddr                    /* mirrored address */
               SFRaddr = SFRaddr + 1
            end
         end
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' Val1 '"' .
         if Val1 \= '' then
            val1 = strip(Val1)                           /* hex or dec */
            if left(Val1,2) = '0X' then
               Val1 = X2D(substr(Val1,3))
            SFRaddr = SFRaddr + Val1
      end

   otherwise
      nop

   end

end

/* --- debug
say 'Core='Core 'Banksize='BankSize 'NumBanks='Numbanks 'MaxRam='Maxram
do i = 0 to BankSize - 1
   call charout stdout, D2X(i,2)'  '
   do j = 0 to NumBanks - 1
      k = banksize * j + i
      if Ram.k \= -1 then
         call charout stdout, D2X(Ram.k,4)' '
      else
         call charout stdout, '   - '
   end
   call lineout stdout, ''
end
--- */

return 0


/* -------------------------------------------------------- */
/* procedure to assign a JalV2 unique ID in chipdef_jallib  */
/* input:  - nothing                                        */
/* -------------------------------------------------------- */
list_devid_chipdef: procedure expose Pic. jalfile chipdef Core PicName msglevel DevID xChipDef.
PicNameCaps = toupper(PicName)                           /* name in upper case */
if DevId \== '0000' then                                    /* DevID not missing */
   xDevId = left(Core,2)'_'DevID
else do                                                     /* DevID unknown */
   DevID = right(PicNameCaps,3)                             /* rightmost 3 chars of name */
   if datatype(Devid,'X') = 0 then do                       /* not all hex digits */
      DevID = right(right(PicNameCaps,2),3,'F')             /* 'F' + rightmost 2 chars */
   end
   xDevId = Core'_F'DevID
end
if xChipDef.xDevId = '?' then do                            /* if not yet assigned */
   xChipDef.xDevId = PicName                                /* remember */
   call lineout chipdef, left('const       PIC_'PicNameCaps,29) '= 0x_'xDevId
end
else do
   call msg 1, 'DevID ('xDevId') in use by' xChipDef.xDevid
   do i = 1                                                 /* index in array */
      tDevId = xDevId||substr('abcdef0123456789',i,1)       /* temp value */
      if xChipDef.tDevId = '?' then do                      /* if not yet assigned */
         xDevId = tDevId                                    /* definitve value */
         xChipDef.xDevId = PicName                          /* remember alternate */
         call lineout chipdef, left('const       PIC_'PicNameCaps,29) '= 0x_'xDevId
         call msg 1, 'Alternate devid (0x'xDevid') assigned'
         leave                                              /* suffix assigned */
      end
      else
         call msg 2, 'DevID ('tDevId') in use by' xChipDef.tDevid
   end
   if i > 16 then do
      call msg 3, 'Not enough suffixes for identical devid, terminated!'
      exit 3
   end
end
return


/* ----------------------------------------------------------- */
/* procedure to list Config memory layout and default settings */
/* input:  - nothing                                           */
/* All cores                                                   */
/* ----------------------------------------------------------- */
list_cfgmem: procedure expose jalfile Pic. CfgAddr. cfgmem DevSpec. PicName Core msglevel
PicNameCaps = toupper(PicName)
if DevSpec.PicNameCaps.FUSESDEFAULT \= '?' then do          /* specified in devicespecific.json */
   if length(DevSpec.PicNameCaps.FUSESDEFAULT) \= length(cfgmem) then do
      call msg 3, 'Fuses in devicespecific.json do not match size of configuration memory'
      call msg 0, '   <'DevSpec.PicNameCaps.FUSESDEFAULT'>  <-->  <'cfgmem'>'
      FusesDefault = DevSpec.PicNameCaps.FUSESDEFAULT       /* take derived value */
   end
   else do                                                  /* same length */
      if DevSpec.PicNameCaps.FUSESDEFAULT = cfgmem then
         call msg 2, 'FusesDefault in devicespecific.json same as derived:' cfgmem
      FusesDefault = devSpec.PicNameCaps.FUSESDEFAULT      /* take devicespecific value */
      call msg 1, 'Using default fuse settings from devicespecific.json:' FusesDefault
   end
end
else do                                                     /* not in devicespecific.json */
   FusesDefault = cfgmem                                    /* take derived value */
end
call lineout jalfile, 'const word  _FUSES_CT             =' CfgAddr.0
if CfgAddr.0 = 1 then do                    /* single word/byte only with baseline/midrange ! */
   call lineout jalfile, 'const word  _FUSE_BASE            = 0x'D2X(CfgAddr.1)
   call charout jalfile, 'const word  _FUSES                = 0b'
   do i = 1 to 4
      call charout jalfile, '_'X2B(substr(FusesDefault,i,1))
   end
   call lineout jalfile, ''
end
else do                                                     /* multiple fuse words/bytes */
   if core \= '16' then                                     /* baseline,midrange */
      call charout jalfile, 'const word  _FUSE_BASE[_FUSES_CT] = { '
   else                                                     /* 18F */
      call charout jalfile, 'const dword _FUSE_BASE[_FUSES_CT] = { '
   do  j = 1 to CfgAddr.0
      call charout jalfile, '0x'D2X(CfgAddr.j)
      if j < CfgAddr.0 then do
         call lineout jalfile, ','
         call charout jalfile, left('',38)
      end
   end
   call lineout jalfile, ' }'

   if core \= '16' then do                                     /* baseline,midrange */
      call charout jalfile, 'const word  _FUSES[_FUSES_CT]     = { '
      do  j = 1 to CfgAddr.0
         call charout jalfile, '0b'
         do i = 1 to 4
            call charout jalfile, '_'X2B(substr(FusesDefault,i+4*(j-1),1,'0'))
         end
         if j < CfgAddr.0 then                                 /* not last word */
            call charout jalfile, ', '
         else
            call charout jalfile, ' }'
         call lineout jalfile, '        -- CONFIG'||j
         if j < CfgAddr.0 then
            call charout jalfile, left('',38,' ')
      end
   end

   else do                                                     /* 18F */
      call charout jalfile, 'const byte  _FUSES[_FUSES_CT]     = { '
      do j = 1 to CfgAddr.0
         call charout jalfile, '0b'
         do i = 1 to 2
            call charout jalfile, '_'X2B(substr(FusesDefault,i+2*(j-1),1,'0'))
         end
         if j < CfgAddr.0 then
            call charout jalfile, ', '
         else
            call charout jalfile, ' }'
         call lineout jalfile, '        -- CONFIG'||(j+1)%2||substr('HL',1+(j//2),1)
         if j < CfgAddr.0 then
            call charout jalfile, left('',38,' ')
      end
   end

end
call lineout jalfile, '--'
return


/* ----------------------------------------------------------- */
/* procedure to generate OSCCAL calibration instructions       */
/* input:  - nothing                                           */
/* cores 12 and 14                                             */
/* notes: Only safe for 12 bits core!                          */
/* ----------------------------------------------------------- */
list_osccal: procedure expose jalfile Pic. CfgAddr. DevSpec. PicName,
                              Core NumBanks CodeSize OSCCALaddr FSRaddr msglevel
if OSCCALaddr > 0 then do                          /* PIC has OSCCAL register */
   if Core = 12 then do                            /* 10F2xx, some 12F5xx, 16f5xx */
      call lineout jalfile, 'var volatile byte  __osccal  at  0x'D2X(OSCCALaddr)
      if NumBanks > 1 then do
         call lineout jalfile, 'var volatile byte  __fsr     at  0x'D2X(FSRaddr)
         call lineout jalfile, 'asm          bcf   __fsr,5                  -- select bank 0'
         if NumBanks > 2 then
            call lineout jalfile, 'asm          bcf   __fsr,6                  --   "     "'
      end
      call lineout jalfile, 'asm          movwf __osccal                 -- calibrate oscillator'
      call lineout jalfile, '--'
   end
   else if Core = 14 then do                       /* 12F629/675, 16F630/676 */
      call lineout jalfile, 'var  volatile byte   __osccal  at  0x'D2X(OSCCALaddr)
      call lineout jalfile, 'asm  page    call   0x'D2X(CodeSize-1)'              -- fetch calibration value'
      call lineout jalfile, 'asm  bank    movwf  __osccal                   -- calibrate oscillator'
      call lineout jalfile, '--'
   end
end
return


/* ---------------------------------------------------- */
/* procedure to list special function registers         */
/* input:  - nothing                                    */
/* ---------------------------------------------------- */
list_sfr: procedure expose Pic. Ram. Name. PinMap. PinANMap. SharedMem.,
                             Core PicName ADCS_bits IRCF_bits jalfile BankSize,
                             HasLATReg NumBanks PinmapMissCount msglevel
PortLat. = 0                                                /* no pins at all */
SFRaddr = 0                                                 /* start value */

do i = 1 to Pic.0  until (word(Pic.i,1) = '<EDC:DATASPACE'   |,
                          word(Pic.i,1) = '<EDC:DATASPACE>')    /* start of data */
   nop
end

do i = i to Pic.0 while word(pic.i,1) \= '</EDC:DATASPACE>'  /* end of SFRs */

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:NMMRPLACE' then do                   /* start of NMMR section */
         do until word(Pic.i,1) = '</EDC:NMMRPLACE>'        /* skip all of it */
            i = i + 1
         end
      end

      when kwd = '<EDC:SFRDATASECTOR' then do               /* start of SFRs */
         parse var Pic.i '<EDC:SFRDATASECTOR' . 'EDC:BEGINADDR="0X' Val1 '"' .
         if Val1 \= '' then
            SFRaddr = X2D(Val1)
      end

      when kwd = '<EDC:MIRROR' then do
         parse var Pic.i '<EDC:MIRROR' 'EDC:NZSIZE="' val1 '"' .
         if Val1 \= '' then do
            val1 = strip(val1)
            if left(val1,2) = '0X' then
               val1 = X2D(substr(val1,3))
            SFRaddr = SFRaddr + Val1
         end
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' val1 '"' .
         if Val1 \= '' then do
            val1 = strip(val1)
            if left(val1,2) = '0X' then
               val1 = X2D(val1)
            SFRaddr = SFRaddr + Val1
         end
      end

      when kwd = '<EDC:JOINEDSFRDEF' then do
         parse var Pic.i '<EDC:JOINEDSFRDEF' . 'EDC:CNAME="' Val1 '"' . 'EDC:NZWIDTH="' Val2 '"' .
         if Val1 \= '' then do
            reg = strip(Val1)
            Name.reg = reg                                        /* add to collection of names */
            addr = SFRaddr                                        /* decimal */
            Ram.addr = addr                                       /* mark address in use */
            addr = sfr_mirror_address(addr)                       /* add mirror addresses */
            val2 = strip(val2)                                    /* hex or dec */
            if left(val2,2) = '0X' then
               val2 = X2D(substr(val2,3))
            width = Val2                                          /* field size (bits) */
            if width <= 8 then                                    /* one byte */
               field = 'byte  '
            else if width <= 16  then                             /* two bytes */
               field = 'word  '
            else
               field = 'byte*'||(width+7)%8                       /* rounded to whole bytes */
            call lineout jalfile, '-- ------------------------------------------------'
            call list_variable field, reg, addr
            call list_sfr_subfields i, reg                        /* SFR bit fields */
            if (reg = 'FSR'      |,
                reg = 'PCL'      |,
                reg = 'TABLAT'   |,
                reg = 'TBLPTR') then do
               reg = tolower(reg)                                 /* to lower case */
               call list_variable field, '_'reg, addr             /* compiler privately */
            end
         end
      end

      when kwd = '<EDC:MUXEDSFRDEF' then do
         do while word(Pic.i,1) \= '</EDC:MUXEDSFRDEF>'
            if word(Pic.i,1) = '<EDC:SELECTSFR>' then             /* unconditional */
               cond = ''
            else if word(Pic.i,1) = '<EDC:SELECTSFR' then do
               parse var Pic.i '<EDC:SELECTSFR' 'EDC:WHEN="' val1 '"' .
               cond = Val1                                        /* conditional */
            end
            else if word(Pic.i,1) = '<EDC:SFRDEF' then do
               parse var Pic.i '<EDC:SFRDEF' . 'EDC:CNAME="' val1 '"' .
               if val1 \= '' then do
                  reg = strip(val1)
                  Name.reg = reg                                  /* add to collection of names */
                  subst  = '_'reg                                 /* substitute name */
                  addr = SFRaddr                                  /* decimal */
                  Ram.addr = addr                                 /* mark address in use */
                  addr = sfr_mirror_address(addr)                 /* add mirror addresses */
                  if cond = '' then do                            /* unconditional */
                     call lineout jalfile, '-- ------------------------------------------------'
                     call list_variable 'byte  ', reg, addr
                     call list_sfr_subfields i, reg               /* SFR bit fields */
                  end
               end

               do while word(Pic.i,1) \= '</EDC:SFRDEF>'
                  i = i + 1
               end

            end
            i = i + 1
         end
         SFRaddr = SFRaddr + 1
      end

      when kwd = '<EDC:SFRDEF' then do
         i_save = i                                               /* remember start SFR */
         parse var Pic.i '<EDC:SFRDEF' . 'EDC:CNAME="' Val1 '"' . 'EDC:NZWIDTH="' val2 '"' .
         if Val1 \= '' then do
            reg = strip(Val1)
            Name.reg = reg                                        /* add to collection of names */
            if left(val2,2) = '0X' then
               val2 = X2D(substr(val2,3))
            width = val2
            addr = SFRaddr                                        /* decimal */
            Ram.addr = addr                                       /* mark address in use */
            addr = sfr_mirror_address(addr)                       /* add mirror addresses */
            field = 'byte  '
            call lineout jalfile, '-- ------------------------------------------------'
            if \(left(reg,4) = 'PORT'  |,
                      reg    = 'GPIO') then                       /* not PORTx or GPIO */
               call list_variable field, reg, addr

            select                                                /* possibly additional declarations  */
               when left(reg,3) = 'LAT' then do                   /* LATx register  */
                  call list_port16_shadow reg                     /* force use of LATx (core 16 like) */
                                                                  /* for output to PORTx */
               end
               when left(reg,4) = 'PORT' then do                  /* port */
                  if HasLATReg = 0 then do                        /* PIC without LAT registers */
                     call list_variable field, '_'reg,  addr
                     call list_port1x_shadow reg
                  end
                  else do                                         /* PIC with LAT registers */
                     call list_variable field, reg, addr
                     PortLetter = substr(reg,4)
                     PortLat.PortLetter. = 0                      /* init: zero pins in PORTx */
                                                                  /* updated in list_sfr_subfields */
                  end
               end
               when reg = 'GPIO' then do                          /* port */
                  call list_variable field, '_'reg, addr
                  call list_alias '_'PORTA, '_'reg
                  call list_port1x_shadow 'PORTA'                 /* GPIO -> PORTA */
               end
               when (reg = 'SPBRG' | reg = 'SPBRG1') & width = 8 then do    /* 8-bits wide */
                  if Name.SPBRGL = '-' then                       /* SPBRGL not defined yet */
                     call list_alias 'SPBRGL', reg                /* add alias */
               end
               when (reg = 'SPBRG2' | reg = 'SP2BRG') & width = 8 then do   /* 8 bits wide */
                  if Name.SPBRGL2 = '-' then                      /* SPBRGL2 not defined yet */
                     call list_alias 'SPBRGL2', reg               /* add alias */
               end
               when reg = 'TRISIO' | reg = 'TRISGPIO' then do     /* low pincount PIC */
                  call list_alias  'TRISA', reg
                  call list_alias  'PORTA_direction', reg
                  call list_tris_nibbles 'TRISA'                  /* nibble direction */
               end
               when left(reg,4) = 'TRIS' then do                  /* TRISx */
                  call list_alias 'PORT'substr(reg,5)'_direction', reg
                  call list_tris_nibbles reg                      /* nibble direction */
               end
            otherwise
               nop                                                /* others can be ignored */
            end

            call list_sfr_subfields i, reg                        /* SFR bit fields */

            if (reg = 'BSR'      |,
                reg = 'FSR'      |,
                reg = 'FSR0L'    |,
                reg = 'FSR0H'    |,
                reg = 'FSR1L'    |,
                reg = 'FSR1H'    |,
                reg = 'INDF'     |,
                reg = 'INDF0'    |,
                reg = 'PCL'      |,
                reg = 'PCLATH'   |,
                reg = 'PCLATU'   |,
                reg = 'STATUS'   |,
                reg = 'TABLAT'   |,
                reg = 'TBLPTR'   |,
                reg = 'TBLPTRH'  |,
                reg = 'TBLPTRL'  |,
                reg = 'TBLPTRU') then do
               if reg = 'INDF' | reg = 'INDF0' then
                  reg = 'IND'                                     /* compiler wants '_ind' */
               reg = tolower(reg)                                 /* to lower case */
               call list_variable field, '_'reg, addr             /* compiler privately */
               if reg = 'status' then                             /* status register */
                  call list_status i                              /* compiler privately */
            end

            call multi_module_register_alias i, reg               /* even when there are no  */
                                                                  /* multiple modules, register */
                                                                  /* aliases may have to be added */

         end

         do while word(Pic.i,1) \= '</EDC:SFRDEF>'
            i = i + 1
         end
         SFRaddr = SFRaddr + 1
      end

   otherwise
      nop

   end

end
return 0


/* ---------------------------------------------------- */
/* procedure to list SFR subfields                      */
/* input:  - nothing                                    */
/* Note: - name is stored but not checked on duplicates */
/* ---------------------------------------------------- */
list_sfr_subfields: procedure expose Pic. Ram. Name. PinMap. PinANMap. SharedMem.,
                                     PortLat.,
                                     Core PicName ADCS_bits IRCF_bits jalfile BankSize,
                                     HasLATReg NumBanks PinmapMissCount msglevel
parse arg i, reg .

offset = 0

do i = i while word(pic.i,1) \= '</EDC:SFRMODELIST>'

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:SFRMODE' then do                     /* new set of subfields */
         offset = 0                                         /* reset bitfield offset */
         parse var Pic.i '<EDC:SFRMODE' 'EDC:ID="' Val1 '"' .
         if ( PicName = '12f609' | PicName = '12f615' | PicName = '12f617' |,
              PicName = '12f629' | PicName = '12f635' | PicName = '12f675' |,
              PicName = '12hv609' | PicName = '12hv615' ) then do
            if Val1 \= 'DS.0'  then do                      /* only SFRmode 'DS.0' */
               do until word(pic.i,1) = '</EDC:SFRMODE>'
                  i = i + 1
               end
            end
         end
         else do                                            /* all SFRmodes DS. and LT. */
            if \(left(Val1,3) = 'DS.' | left(Val1,3) = 'LT.') then do
               do until word(pic.i,1) = '</EDC:SFRMODE>'
                  i = i + 1
               end
            end
         end
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' Val1 '"' .
         if Val1 \= '' then do
            offset = offset + Val1
         end
      end

      when kwd = '<EDC:SFRFIELDDEF' then do
         parse var Pic.i '<EDC:SFRFIELDDEF' 'EDC:CNAME="' val1 '"' . ,
                          'EDC:MASK="' val3 '"' . 'EDC:NZWIDTH="' val4 '"' .
         if Val1 \= '' then do
            field = reg'_'val1
            width = strip(val4)
            if left(width,2) = '0X' then
               width = X2D(substr(width,3))
            if width \= 8 then do                            /* skip 8-bit width subfields */

                                                             /* *** interceptions *** */
               select
                  when reg = 'ADCON0' & val1 = 'ADCS' & width = 2  &, /* possibly splitted ADCS bits */
                      (PicName = '16f737'  | PicName = '16f747'  |,
                       PicName = '16f767'  | PicName = '16f777'  |,
                       PicName = '16f818'  | PicName = '16f819'  |,
                       PicName = '16f873a' | PicName = '16f874a' |,
                       PicName = '16f876a' | PicName = '16f877a' |,
                       PicName = '16f88'                         |,
                       PicName = '18f242'  | PicName = '18f2439' |,
                       PicName = '18f248'                        |,
                       PicName = '18f252'  | PicName = '18f2539' |,
                       PicName = '18f258'                        |,
                       PicName = '18f442'  | PicName = '18f4439' |,
                       PicName = '18f448'                        |,
                       PicName = '18f452'  | PicName = '18f4539' |,
                       PicName = '18f458'                        ) then do
                     call list_bitfield width, reg'_ADCS10', reg, offset
                     if core = '16' then do
                        call lineout jalfile, '--'
                        call lineout jalfile, 'var volatile byte   ADCON0_ADCS    -- shadow'
                        call lineout jalfile, 'procedure  ADCON0_ADCS'"'put"'(byte in x) is'
                        call lineout jalfile, '   ADCON0_ADCS10 = (x & 0x03)      -- low order bits'
                        call lineout jalfile, '   ADCON1_ADCS2  = (x & 0x04)      -- high order bit'
                        call lineout jalfile, 'end procedure'
                        call lineout jalfile, '--'
                     end
                  end
                  when reg = 'ADCON1'  &  val1 = 'ADCS2'  &,    /* possibly splitted ADCS bits */
                      (PicName = '16f737'  | PicName = '16f747'  |,
                       PicName = '16f767'  | PicName = '16f777'  |,
                       PicName = '16f818'  | PicName = '16f819'  |,
                       PicName = '16f873a' | PicName = '16f874a' |,
                       PicName = '16f876a' | PicName = '16f877a' |,
                       PicName = '16f88'                         |,
                       PicName = '18f242'  | PicName = '18f2439' |,
                       PicName = '18f248'                        |,
                       PicName = '18f252'  | PicName = '18f2539' |,
                       PicName = '18f258'                        |,
                       PicName = '18f442'  | PicName = '18f4439' |,
                       PicName = '18f448'                        |,
                       PicName = '18f452'  | PicName = '18f4539' |,
                       PicName = '18f458'                        ) then do
                     call list_bitfield width, field, reg, offset
                     if core = '14' then do
                        call lineout jalfile, '--'
                        call lineout jalfile, 'var volatile byte   ADCON0_ADCS    -- shadow'
                        call lineout jalfile, 'procedure  ADCON0_ADCS'"'put"'(byte in x) is'
                        call lineout jalfile, '   ADCON0_ADCS10 = (x & 0x03)      -- low order bits'
                        call lineout jalfile, '   ADCON1_ADCS2  = (x & 0x04)      -- high order bit'
                        call lineout jalfile, 'end procedure'
                        call lineout jalfile, '--'
                     end
                  end
                  when reg = 'ADCON0'  &,                   /* ADCON0 */
                       (PicName = '16f737'  | PicName = '16f747'  |,
                        PicName = '16f767'  | PicName = '16f777')   &,
                        val1 = 'CHS' then do
                     call list_bitfield width, field'210', reg, offset
                     call lineout jalfile, '--'
                     call lineout jalfile, 'procedure' reg'_CHS'"'put"'(byte in x) is'
                     call lineout jalfile, '   'reg'_CHS210 = (x & 0x07)     -- low order bits'
                     call lineout jalfile, '   'reg'_CHS3   = 0              -- reset'
                     call lineout jalfile, '   if ((x & 0x08) != 0) then'
                     call lineout jalfile, '      'reg'_CHS3 = 1             -- high order bit'
                     call lineout jalfile, '   end if'
                     call lineout jalfile, 'end procedure'
                     call lineout jalfile, '--'
                  end
                  when (left(val1,2) = 'AN'  &  width = 1)  &,             /* AN(S) subfield */
                       (left(reg,5) = 'ADCON'  | left(reg,5) = 'ANSEL')  then do
                     call list_bitfield 1, reg'_'val1, reg, offset
                     ansx = ansel2j(reg, val1)
                     if ansx < 99 then                      /* valid number */
                        call list_alias 'JANSEL_ANS'ansx, field
                  end
                  when pos('CCP',reg) > 0  & right(reg,3) = 'CON'  &,   /* [E]CCPxCON */
                       left(val1,3) = 'CCP'                        &,
                       (right(val1,1) = 'X' | right(val1,1) = 'Y') then do   /* CCP.X/Y */
                     nop                                    /* suppress */
                  end
                  when (reg = 'GPIO' & left(val1,2) = 'RB') then do  /* suppress wrong pinnames */
                     nop
                  end
                  when (reg = 'GPIO' & left(val1,2) = 'GP') then do
                     if width = 1 then do                   /* only single pins */
                        field = reg'_GP'right(val1,1)       /* pin GPIOx -> GPx */
                        call list_bitfield 1, field, '_'reg, offset
                     end
                  end
                  when reg = 'OSCCON' & left(val1,4) = 'IRCF' & width = 1 then do
                     nop                                    /* suppress enumerated IRCF bits */
                  end
                  when reg = 'OPTION_REG' & val1 = 'PS2' then do
                     call list_bitfield 1, reg'_PS', reg, offset
                  end

               otherwise

                  call list_bitfield width, field, reg, offset

               end

                                                            /* *** additions *** */
               select
                  when left(reg,5) = 'ADCON'  &,            /* ADCON0/1 */
                       right(field,5) = 'VCFG0' then do     /* enumerated VCFG field */
                     field = reg'_VFCG'
                     if Name.field = '-' then               /* multi-bit field not declared */
                        call list_bitfield 2, field, reg, offset
                  end
                  when reg = 'CANCON'  &  val1 = 'REQOP0' then do
                     call list_bitfield 3, reg'_REQOP', reg, offset
                  end
                  when pos('CCP',reg) > 0  &  right(reg,3) = 'CON' &,   /* [E]CCPxCON */
                     ((left(val1,3) = 'CCP' &  right(val1,1) = 'Y') |,    /* CCPxY */
                      (left(val1,2) = 'DC' &  right(val1,2) = 'B0')) then do /* DCxB0 */
                     if left(val1,2) = 'DC' then
                        field = reg'_DC'substr(val1,3,1)'B'
                     else
                        field = reg'_DC'substr(val1,4,1)'B'
                     call list_bitfield 2, field, reg, (offset - width + 1)
                  end
                  when reg = 'FVRCON'  &  (val1 = 'CDAFVR0' | val1 = 'ADFVR0') then do
                     call list_bitfield 2, strip(field,'T','0'), reg, offset
                  end
                  when reg = 'GPIO' then do
                     if left(val1,2) = 'GP' & width = 1 then do    /* single I/O pin */
                        if HasLATReg = 0 then do                  /* PIC without LAT registers */
                           shadow = '_PORTA_shadow'
                           pin = 'pin_A'right(val1,1)
                           call list_bitfield 1, pin, '_'reg, offset
                           call list_pin_alias 'PORTA', 'RA'right(val1,1), pin
                           call lineout jalfile, '--'
                           call lineout jalfile, 'procedure' pin"'put"'(bit in x',
                                                            'at' shadow ':' offset') is'
                           call lineout jalfile, '   pragma inline'
                           call lineout jalfile, '   _PORTA =' shadow
                           call lineout jalfile, 'end procedure'
                           call lineout jalfile, '--'
                        end
                        else do                                   /* PIC with LAT registers */
                           PortLetter = right(reg,1)
                           PortLat.PortLetter.offset = PortLetter||offset
                        end
                     end
                  end
                  when reg = 'INTCON' then do
                     if left(val1,2) = 'T0' then
                        call list_bitfield 1, reg'_TMR0'substr(val1,3), reg, offset
                  end
                  when left(reg,3) = 'LAT' then do                /* LATx (10F3xx, 12f752) */
                     PortLetter = substr(reg,4)
                     PinNumber  = right(val1,1)
                     pin = 'pin_'PortLat.PortLetter.offset
                     if PortLat.PortLetter.offset \= 0 then do    /* pin present in PORTx */
                        call list_bitfield 1, pin, 'PORT'PortLetter, offset
                        call list_pin_alias 'PORT'portletter, 'R'PortLat.PortLetter.offset, pin
                        call lineout jalfile, '--'
                     end
                     if substr(val1,2,length(val1)-2) = PortLetter  &,        /* port letter */
                        datatype(PinNumber) = 'NUM'        then do   /* pin number */
                        call lineout jalfile, 'procedure' pin"'put"'(bit in x',
                                                   'at' reg ':' offset') is'
                        call lineout jalfile, '   pragma inline'
                        call lineout jalfile, 'end procedure'
                        call lineout jalfile, '--'
                     end
                  end
                  when reg = 'OPTION_REG' &,
                       (val1 = 'T0CS' | val1 = 'T0SE' | val1 = 'PSA') then do
                     call list_alias 'T0CON_'val1, reg'_'val1
                  end
                  when reg = 'OPTION_REG' & val1 = 'PS2' then do
                     call list_bitfield 1, field, reg, offset
                     call list_alias 'T0CON_T0PS', reg'_'PS
                  end
                  when reg = 'OSCCON'  &  val1 = 'IRCF0' then do
                     call list_bitfield IRCF_bits, reg'_IRCF', reg, offset
                  end
                  when reg = 'PADCFG1'  &  val1 = 'RTSECSEL0' then do
                     call list_bitfield 2, reg'_RTSECSEL', reg, offset
                  end
                  when left(reg,4) = 'PORT' then do
                     if left(val1,1) = 'R'  &,
                        substr(val1,2,length(val1)-2) = right(reg,1) then do  /* prob. I/O pin */
                        if HasLATReg = 0 then do                     /* PIC without LAT registers */
                           shadow = '_PORT'right(reg,1)'_shadow'
                           pin = 'pin_'right(val1,2)
                           call list_bitfield 1, pin, '_'reg, offset
                           call list_pin_alias reg, 'R'right(val1,2), pin
                           call lineout jalfile, '--'
                           call lineout jalfile, 'procedure' pin"'put"'(bit in x',
                                                          'at' shadow ':' offset') is'
                           call lineout jalfile, '   pragma inline'
                           call lineout jalfile, '   _PORT'substr(reg,5) '=' shadow
                           call lineout jalfile, 'end procedure'
                           call lineout jalfile, '--'
                        end
                        else do                                /* PIC with LAT registers */
                           PortLetter = substr(reg,5)
                           PortLat.PortLetter.offset = PortLetter||offset
                        end
                     end
                  end
                  when reg = 'TRISIO' | reg = 'TRISGPIO' then do
                     pin = 'pin_A'right(val1,1)'_direction'
                     call list_alias pin, reg'_'val1
                     call list_pin_direction_alias 'TRISA', 'RA'right(val1,1), pin
                     call lineout jalfile, '--'
                  end
                  when left(reg,4) = 'TRIS'  &,
                       left(val1,4) = 'TRIS'  then do
                     pin = 'pin_'substr(val1,5)'_direction'
                     call list_alias pin, reg'_'val1
                     if substr(val1,5,1) = right(reg,1) then do
                        call list_pin_direction_alias reg, 'R'substr(val1,5), pin
                     end
                     call lineout jalfile, '--'
                  end
               otherwise
                  nop
               end

            end

            call multi_module_bitfield_alias reg, val1

            Offset = Offset + width

         end
      end

   otherwise
      nop
   end

end
return 0



/* ---------------------------------------------------- */
/* procedure to list (only) multiplexed registers       */
/* input:  - nothing                                    */
/* ---------------------------------------------------- */
list_muxed_sfr: procedure expose Pic. Ram. Name. PinMap. PinANMap. ,
                                 Core PicName jalfile BankSize HasMuxedSFR msglevel

SFRaddr = 0                                                 /* start value */

if HasMuxedSFR > 0 then do
  call lineout jalfile,'--'
  call lineout jalfile,'-- ========================================================'
  call lineout jalfile,'--'
  call lineout jalfile,'--  Multiplexed registers'
  call lineout jalfile,'--'
end

do i = 1 to Pic.0  until (word(Pic.i,1) = '<EDC:DATASPACE'   |,
                          word(Pic.i,1) = '<EDC:DATASPACE>')    /* start of data */
   nop
end

do i = i to Pic.0 while word(pic.i,1) \= '</EDC:DATASPACE>'  /* end of SFRs */

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:NMMRPLACE' then do                   /* start of NMMR section */
         do until word(Pic.i,1) = '</EDC:NMMRPLACE>'        /* skip all of it */
            i = i + 1
         end
      end

      when kwd = '<EDC:SFRDATASECTOR' then do               /* start of SFRs */
         parse var Pic.i '<EDC:SFRDATASECTOR' . 'EDC:BEGINADDR="0X' Val1 '"' .
         if Val1 \= '' then
            SFRaddr = X2D(Val1)
      end

      when kwd = '<EDC:MIRROR' then do
         parse var Pic.i '<EDC:MIRROR' 'EDC:NZSIZE="' val1 '"' .
         if Val1 \= '' then do
            val1 = strip(val1)
            if left(val1,2) = '0X' then
               val1 = X2D(substr(val1,3))
            SFRaddr = SFRaddr + Val1
         end
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' val1 '"' .
         if Val1 \= '' then do
            val1 = strip(val1)
            if left(val1,2) = '0X' then
               val1 = X2D(val1)
            SFRaddr = SFRaddr + Val1
         end
      end

      when kwd = '<EDC:MUXEDSFRDEF' then do
         do while word(Pic.i,1) \= '</EDC:MUXEDSFRDEF>'
            if word(Pic.i,1) = '<EDC:SELECTSFR>' then             /* no conditional expression */
               cond = ''
            else if word(Pic.i,1) = '<EDC:SELECTSFR' then do
               parse var Pic.i '<EDC:SELECTSFR' 'EDC:WHEN="' val1 '"' .
               cond = Val1                                        /* condition expression */
            end
            else if word(Pic.i,1) = '<EDC:SFRDEF' then do
               parse var Pic.i '<EDC:SFRDEF' . 'EDC:CNAME="' val1 '"' .
               if val1 \= '' then do
                  if cond \= '' then do                           /* only conditional SFRs */
                     reg = strip(val1)
                     Name.reg = reg                               /* add to collection of names */
                     subst  = '_'reg                              /* substitute name */
                     addr = SFRaddr                               /* decimal */
                     addr = sfr_mirror_address(addr)              /* add mirror addresses */
                     call lineout jalfile, '-- ------------------------------------------------'
                     parse var cond '($0X'val1 val2 '0X'val3')' . '0X' val4 .
                     if debuglevel = 2 then
                        call msg 0, reg 'multiplexed condition:' toascii(cond)

                     if core = '14' then do
                        if reg = 'SSPMSK' then do
                           call lineout jalfile, 'var volatile byte  ' left(subst,25) 'at' addr
                           call lineout jalfile, '-- ----- Address 0x'val1 'assumed to be SSPCON -----'
                           call lineout jalfile, 'procedure' reg"'put"'(byte in x) is'
                           call lineout jalfile, '   var byte _sspcon_saved = SSPCON'
                           call lineout jalfile, '   SSPCON = SSPCON' toascii(val2) '(!0x'val3')'
                           call lineout jalfile, '   SSPCON = SSPCON | 0x'val4
                           call lineout jalfile, '   'subst '= x'
                           call lineout jalfile, '   SSPCON = _sspcon_saved'
                           call lineout jalfile, 'end procedure'
                           call lineout jalfile, 'function' reg"'get"'() return byte is'
                           call lineout jalfile, '   var  byte  x'
                           call lineout jalfile, '   var byte _sspcon_saved = SSPCON'
                           call lineout jalfile, '   SSPCON = SSPCON' toascii(val2) '(!0x'val3')'
                           call lineout jalfile, '   SSPCON = SSPCON | 0x'val4
                           call lineout jalfile, '   x =' subst
                           call lineout jalfile, '   SSPCON = _sspcon_saved'
                           call lineout jalfile, '   return  x'
                           call lineout jalfile, 'end function'
                           call lineout jalfile, '--'
                        end
                        else
                           call msg 3, 'Unexpected multiplexed SFR' reg 'for core' core
                     end

                     else if core = '16' then do
                        if reg = 'SSP1MSK' |,
                           reg = 'SSP2MSK' then do
                           index = substr(reg,4,1)                   /* SSP module number */
                           call lineout jalfile, 'var volatile byte  ' left(subst,25) 'at' addr
                           call lineout jalfile, '-- ----- address 0x'val1 'assumed to be SSP'index'CON1 -----'
                           call lineout jalfile, 'procedure' reg"'put"'(byte in x) is'
                           call lineout jalfile, '   var byte _ssp'index'con1_saved = SSP'index'CON1'
                           call lineout jalfile, '   SSP'index'CON1 = SSP'index'CON1' toascii(val2) '(!0x'val3')'
                           call lineout jalfile, '   SSP'index'CON1 = SSP'index'CON1 | 0x'val4
                           call lineout jalfile, '   'subst '= x'
                           call lineout jalfile, '   SSP'index'CON1 = _ssp'index'con1_saved'
                           call lineout jalfile, 'end procedure'
                           call lineout jalfile, 'function' reg"'get"'() return byte is'
                           call lineout jalfile, '   var  byte  x'
                           call lineout jalfile, '   var  byte  _ssp'index'con1_saved = SSP'index'CON1'
                           call lineout jalfile, '   SSP'index'CON1 = SSP'index'CON1' toascii(val2) '(!0x'val3')'
                           call lineout jalfile, '   SSP'index'CON1 = SSP'index'CON1 | 0x'val4
                           call lineout jalfile, '   x =' subst
                           call lineout jalfile, '   SSP'index'CON1 = _ssp'index'con1_saved'
                           call lineout jalfile, '   return  x'
                           call lineout jalfile, 'end function'
                           call lineout jalfile, '--'
                           if reg = SSP1MSK then
                              call list_alias  'SSPMSK', reg
                        end

                        else if left(reg,6) = 'PMDOUT' then do
                           call list_variable 'byte  ', reg, addr
                        end

                        else if left(reg,5) = 'ODCON' |,
                                left(reg,5) = 'ANCON' |,
                                reg = 'CVRCON'        |,
                                reg = 'MEMCON'        |,
                                reg = 'PADCFG1'       |,
                                reg = 'REFOCON'      then do
                           call lineout jalfile, 'var volatile byte  ' left(subst,25) 'at' addr
                           call lineout jalfile, '-- ----- address 0x'val1 'assumed to be WDTCON -----'
                           call lineout jalfile, 'procedure' reg"'put"'(byte in x) is'
                           call lineout jalfile, '   WDTCON_ADSHR = TRUE'
                           call lineout jalfile, '   'subst '= x'
                           call lineout jalfile, '   WDTCON_ADSHR = FALSE'
                           call lineout jalfile, 'end procedure'
                           call lineout jalfile, 'function' reg"'get"'() return byte is'
                           call lineout jalfile, '   var  byte  x'
                           call lineout jalfile, '   WDTCON_ADSHR = TRUE'
                           call lineout jalfile, '   x =' subst
                           call lineout jalfile, '   WDTCON_ADSHR = FALSE'
                           call lineout jalfile, '   return  x'
                           call lineout jalfile, 'end function'
                           call lineout jalfile, '--'

                           call list_muxed_sfr_subfields i, reg     /* SFR bit fields */

                        end

                        else
                           call msg 3, 'Unexpected multiplexed SFR' reg 'for core' core

                     end

                     else
                        call msg 3, 'Unexpected core' core 'with multiplexed SFR' reg

                  end
               end
               do while word(Pic.i,1) \= '</EDC:SFRDEF>'
                  i = i + 1
               end
            end
            i = i + 1
         end
         SFRaddr = SFRaddr + 1                        /* muxed SFRs count for 1 */
      end

      when kwd = '<EDC:SFRDEF' then do
         do while word(Pic.i,1) \= '</EDC:SFRDEF>'
            i = i + 1
         end
         SFRaddr = SFRaddr + 1
      end

   otherwise
      nop

   end

end
return 0


/* ---------------------------------------------------------- */
/* Formatting of subfields of multiplexed SFRs                */
/* of the 18F series                                          */
/* input:  - index in .pic                                    */
/*         - register name                                    */
/* 16-bit core                                                */
/* ---------------------------------------------------------- */
list_muxed_sfr_subfields: procedure expose Pic. Name. PinMap. PicName jalfile msglevel

parse arg i, reg .

offset = 0

do while word(pic.i,1) \= '</EDC:SFRMODELIST>'

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:SFRMODE' then do                     /* new set of subfields */
         offset = 0                                         /* reset bitfield offset */
         parse var Pic.i '<EDC:SFRMODE' 'EDC:ID="' Val1 '"' .
         if \(left(Val1,3) = 'DS.' | left(Val1,3) = 'LT.') then do
            do until word(pic.i,1) = '</EDC:SFRMODE>'
               i = i + 1
            end
         end
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' Val1 '"' .
         if Val1 \= '' then do
            offset = offset + Val1
         end
      end

      when kwd = '<EDC:SFRFIELDDEF' then do
         parse var Pic.i '<EDC:SFRFIELDDEF' 'EDC:CNAME="' val1 '"' . ,
                          'EDC:MASK="' val3 '"' . 'EDC:NZWIDTH="' val4 '"' .
         if Val1 \= '' then do
            field = reg'_'val1
            width = strip(val4)
            if left(width,2) = '0X' then
               width = X2D(substr(width,3))
            if width \= 8 then do                           /* skip 8-bit width subfields */

               field = reg'_'val1
               Name.field = field                           /* remember name */
               subst = '_'reg                               /* substitute name of SFR */

               if width = 1 then do                         /* single bit */
                  call lineout jalfile, 'procedure' field"'put"'(bit in x) is'
                  call lineout jalfile, '   var  bit   y at' subst ':' offset
                  call lineout jalfile, '   WDTCON_ADSHR = TRUE'
                  call lineout jalfile, '   y = x'
                  call lineout jalfile, '   WDTCON_ADSHR = FALSE'
                  call lineout jalfile, 'end procedure'
                  call lineout jalfile, 'function ' field"'get"'() return bit is'
                  call lineout jalfile, '   var  bit   x at' subst ':' offset
                  call lineout jalfile, '   var  bit   y'
                  call lineout jalfile, '   WDTCON_ADSHR = TRUE'
                  call lineout jalfile, '   y = x'
                  call lineout jalfile, '   WDTCON_ADSHR = FALSE'
                  call lineout jalfile, '   return y'
                  call lineout jalfile, 'end function'
                  call lineout jalfile, '--'
               end
               else if width < 8  then do                   /* multi-bit */
                  call lineout jalfile, 'procedure' field"'put"'(bit*'width 'in x) is'
                  call lineout jalfile, '   var  bit*'width 'y at' subst ':' offset
                  call lineout jalfile, '   WDTCON_ADSHR = TRUE'
                  call lineout jalfile, '   y = x'
                  call lineout jalfile, '   WDTCON_ADSHR = FALSE'
                  call lineout jalfile, 'end procedure'
                  call lineout jalfile, 'function ' field"'get"'() return bit*'width 'is'
                  call lineout jalfile, '   var  bit*'width 'x at' subst ':' offset
                  call lineout jalfile, '   var  bit*'width 'y'
                  call lineout jalfile, '   WDTCON_ADSHR = TRUE'
                  call lineout jalfile, '   y = x'
                  call lineout jalfile, '   WDTCON_ADSHR = FALSE'
                  call lineout jalfile, '   return y'
                  call lineout jalfile, 'end function'
                  call lineout jalfile, '--'
               end
            end
         end
         offset = offset + width
      end

   otherwise
      nop

   end
   i = i + 1                                                /* next record */
end
return 0


/* ---------------------------------------------------- */
/* procedure to list NMMMRs                             */
/* input:  - nothing                                    */
/* Note: - name is stored but not checked on duplicates */
/* ---------------------------------------------------- */
list_nmmr: procedure expose Pic. Ram. Name. PinMap. PinANMap. SharedMem.,
                            Core PicName ADCS_bits jalfile BankSize,
                            HasLATReg NumBanks PinmapMissCount msglevel

do i = 1 to Pic.0  while word(Pic.i,1) \= '<EDC:NMMRPLACE'  /* start ofNMMR specs */
   nop
end

do i = i to Pic.0 while word(pic.i,1) \= '</EDC:NMMRPLACE>'   /* end of NMMRs */

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:SFRDEF' then do
         parse var Pic.i '<EDC:SFRDEF' . 'EDC:CNAME="' Val1 '"' .
         if Val1 \= '' then do
            reg = strip(Val1)
            Name.reg = reg                                        /* add to collection of names */
            field = 'byte  '
            addr = 0
            call lineout jalfile, '-- ------------------------------------------------'

            call list_variable field, reg, addr

            call list_sfr_subfields i, reg                        /* SFR bit fields */

         end
      end

   otherwise
      nop

   end

end
return 0



/* ------------------------------------------------------------- */
/* procedure to add pin alias declarations                       */
/* input:  - register name                                       */
/*         - original pin name (Rx)                              */
/*         - pinname for aliases (pin_Xy)                        */
/* create alias definitions for all synonyms in pinmap.          */
/* create extra aliases for first of multiple I2C or SPI modules */
/* create extra aliases for TX and RX pins of only USART module  */
/* returns index of alias (0 if none)                            */
/* ------------------------------------------------------------- */
list_pin_alias: procedure expose  PinMap. Name. PicName Core PinmapMissCount jalfile msglevel
parse arg reg, PinName, Pin .
PicNameCaps = toupper(PicName)
if PinMap.PicNameCaps.PinName.0 = '?' then do
   call msg 2, 'list_pin_alias() PinMap.'PicNameCaps'.'PinName 'is undefined'
   PinmapMissCount = PinmapMissCount + 1                    /* count misses */
   return 0                                                 /* no alias */
end
if PinMap.PicNameCaps.PinName.0 > 0 then do
   do k = 1 to PinMap.PicNameCaps.PinName.0                    /* all aliases */
      pinalias = 'pin_'PinMap.PicNameCaps.PinName.k
      call list_alias pinalias, Pin
      if pinalias = 'pin_SDA1' |,                           /* 1st I2C module */
         pinalias = 'pin_SDI1' |,                           /* 1st SPI module */
         pinalias = 'pin_SDO1' |,
         pinalias = 'pin_SCK1' |,
         pinalias = 'pin_SCL1' |,
         pinalias = 'pin_SS1'  |,                           /* 1st SPI module */
         pinalias = 'pin_TX1'  |,                           /* TX pin first USART */
         pinalias = 'pin_RX1' then                          /* RX                 */
         call list_alias strip(pinalias,'T',1), Pin
   end
end
return k                                                    /* k-th alias */


/* ------------------------------------------------------------- */
/* procedure to add pin_direction alias declarations             */
/* input:  - register name                                       */
/*         - original pin name (Rx)                              */
/*         - pinname for aliases (pin_Xy)                        */
/* create alias definitions for all synonyms in pinmap           */
/* with '_direction' added!                                      */
/* create extra aliases for first of multiple I2C or SPI modules */
/* returns index of alias (0 if none)                            */
/* ------------------------------------------------------------- */
list_pin_direction_alias: procedure expose  PinMap. Name. PicName,
                            Core jalfile msglevel
parse arg reg, PinName, Pin .
PicNameCaps = toupper(PicName)
if PinMap.PicNameCaps.PinName.0 = '?' then do
   call msg 2, 'list_pin_direction_alias() PinMap.'PicNameCaps'.'PinName 'is undefined'
   return 0                                                 /* ignore no alias */
end
if PinMap.PicNameCaps.PinName.0 > 0 then do
   do k = 1 to PinMap.PicNameCaps.PinName.0                    /* all aliases */
      pinalias = 'pin_'PinMap.PicNameCaps.PinName.k'_direction'
      call list_alias  pinalias, Pin
      if pinalias = 'pin_SDA1_direction' |,              /* 1st I2C module */
         pinalias = 'pin_SDI1_direction' |,              /* 1st SPI module */
         pinalias = 'pin_SDO1_direction' |,
         pinalias = 'pin_SCK1_direction' |,
         pinalias = 'pin_SCL1_direction' then do
         pinalias = delstr(pinalias,8,1)
         call list_alias pinalias, Pin
      end
      else if pinalias = 'pin_SS1_direction' |,          /* 1st SPI module */
              pinalias = 'pin_TX1_direction' |,          /* TX pin first USART */
              pinalias = 'pin_RX1_direction' then do     /* RX   "  "     "    */
         pinalias = delstr(pinalias,7,1)
         call list_alias pinalias, Pin
      end
   end
end
return k


/* ------------------------------------------------------------------ */
/* Adding aliases of registers for PICs with multiple similar modules */
/* Used only for registers which are fully dedicated to a module.     */
/* input:  - index i in Pic.i of line with this register              */
/*         - register                                                 */
/* returns: nothing                                                   */
/* notes:  - add unqualified alias for module 1                       */
/*         - add (modified) alias for modules 2..9                    */
/*         - bitfields are expanded as for 'real' registers           */
/* All cores                                                          */
/* ------------------------------------------------------------------ */
multi_module_register_alias: procedure expose Pic. Name. Core PicName jalfile msglevel

parse upper arg i, reg

alias = ''                                                  /* default: no alias */
select

   when reg = 'BAUDCTL' then do                             /* some midrange, 18f1x20 */
      alias = 'BAUDCON'
   end

   when reg = 'BAUD1CON' then do                            /* 1st USART: reg with index */
      alias = 'BAUDCON'                                     /* remove '1' */
   end

   when reg = 'BAUD2CON'  then do                           /* 2nd USART: reg with suffix */
      alias = 'BAUDCON2'                                    /* make index '2' a suffix */
   end

   when reg = 'BAUDCON1' |,
        reg = 'BAUDCTL1' |,
        reg = 'RCREG1'   |,                                 /* 1st USART: reg with index */
        reg = 'RCSTA1'   |,
        reg = 'SPBRG1'   |,
        reg = 'SPBRGH1'  |,
        reg = 'SPBRGL1'  |,
        reg = 'TXREG1'   |,
        reg = 'TXSTA1'   then do
      alias = strip(reg,'T','1')                            /* remove trailing '1' index */
   end

   when reg = 'RC1REG'   |,                                 /* 1st USART: reg with index */
        reg = 'RC1STA'   |,
        reg = 'SP1BRG'   |,
        reg = 'SP1BRGH'  |,
        reg = 'SP1BRGL'  |,
        reg = 'TX1REG'   |,
        reg = 'TX1STA'   then do
      alias = delstr(reg,3,1)                               /* remove embedded '1' index */
   end

   when reg = 'RC2REG'   |,                                 /* 2nd USART: reg with suffix */
        reg = 'RC2STA'   |,
        reg = 'SP2BRG'   |,
        reg = 'SP2BRGH'  |,
        reg = 'SP2BRGL'  |,
        reg = 'TX2REG'   |,
        reg = 'TX2STA'   then do
      alias = delstr(reg,3,1)'2'                            /* make index '2' a suffix */
   end

   when reg = 'SSPCON'   |,                                 /* unqualified SSPCON */
        reg = 'SSP2CON'  then do
      alias = reg'1'                                        /* add suffix '1' */
   end

   when left(reg,3) = 'SSP'  &  substr(reg,4,1) = '1' then do   /* first or only MSSP module */
      alias = delstr(reg, 4,1)                              /* remove module number */
      if alias = 'SSPCON'   |,                              /* unqualified */
         alias = 'SSP2CON'  then
         alias = alias'1'                                   /* add '1' suffix */
   end

otherwise
   nop                                                      /* ignore other registers */

end

if alias \= '' then do                                      /* alias to be declared */
   call lineout jalfile, '--'                               /* separator line */
   call list_alias alias, reg
   call list_sfr_subfield_alias i, alias, reg               /* declare subfield aliases */
end

return


/* ------------------------------------------------------- */
/* List a line with a volatile variable                    */
/* arguments: - type (byte, word, etc.)                    */
/*            - name                                       */
/*            - address (decimal or string)                */
/* returns:   nothing                                      */
/* Notes:     all cores                                    */
/* ------------------------------------------------------- */
list_variable: procedure expose Core JalFile Name.
parse arg type, var, addr                                   /* addr can be string with spaces */
if addr = '' then do
   call msg 3, 'list_variable(): less than 3 arguments found, no output generated!'
   return
end
if duplicate_name(var, var) \= 0 then                       /* name already declared */
   return
call charout jalfile, 'var volatile' left(type,max(6,length(type))),
                                     left(var,max(25,length(var)))' at '
call lineout jalfile, addr                                  /* string */
return


/* --------------------------------------------------------- */
/* List a line with a volatile bitfield variable             */
/* arguments: - width in bits (1,2, .. 8)                    */
/*            - name of the bit                              */
/*            - register                                     */
/*            - offset within the register                   */
/*            - address (decimal, only for core 14H and 16)  */
/* returns:   nothing                                        */
/* Notes:     all cores                                      */
/* --------------------------------------------------------- */
list_bitfield: procedure expose Core JalFile Name.
parse arg width, bitfield, reg, offset, addr .
if offset = '' then do
   call msg 3, 'list_bitfield(): less than 4 arguments found, no output generated!'
   return
end
if datatype(width) \= 'NUM'  |  width < 1  |  width > 8 then do
   call msg 3, 'list_bitfield(): bitfield width' width 'not supported, no output generated!'
   return
end
if duplicate_name(bitfield, reg) \= 0 then                  /* name already declared */
   return
call charout jalfile, 'var volatile '
if width = 1 then
   call charout jalfile, left('bit',7)
else
   call charout jalfile, left('bit*'width,7)
call lineout jalfile, left(bitfield,max(25,length(bitfield))),
                      'at' reg ':' offset
return


/* ------------------------------------------------------- */
/* List a line with an alias declaration                   */
/* arguments: - name of alias                              */
/*            - name of original variable (or other alias) */
/* returns:   nothing                                      */
/* Notes:     all cores                                    */
/* ------------------------------------------------------- */
list_alias: procedure expose Core JalFile Name. reg msglevel
parse arg alias, original .
if orininal = '' then do
   call msg 3, 'list_alias(): 2 arguments expected, no output generated!'
   return
end
if duplicate_name(alias,reg) = 0 then do
   call lineout jalfile, left('alias',19) left(alias,max(25,length(alias))) 'is' original
end
return


/* ----------------------------------------------------- */
/* Adding aliases of register bitfields related to       */
/* multiple similar modules.                             */
/* Used for registers which happen to contain bitfields  */
/* for multiple similar modules.                         */
/* For - PIE, PIR and IPR registers                      */
/*       USART and SSP interrupt bits                    */
/* input:  - register                                    */
/*         - bitfield                                    */
/* returns: nothing                                      */
/* notes:  - add unqualified alias for module 1          */
/*         - add (modified) alias for modules 2..9       */
/* All cores                                             */
/* ----------------------------------------------------- */
multi_module_bitfield_alias: procedure expose Name. Core jalfile msglevel

parse upper arg reg, bitfield

j = 0                                                    /* default: no multi-module */

if left(reg,3) = 'PIE'  |,                               /* Interrupt register */
   left(reg,3) = 'PIR'  |,
   left(reg,3) = 'IPR'  then do
   if left(bitfield,2) = 'TX'  |,                        /* USART related bitfields */
      left(bitfield,2) = 'RC'  then do
      j = substr(bitfield,3,1)                           /* possibly module number */
      if datatype(j) = 'NUM' then                        /* embedded number */
         strippedfield = delstr(bitfield,3,1)
      else do
         j = right(bitfield,1)                           /* possibly module number */
         if datatype(j) = 'NUM' then                     /* numeric suffix */
            strippedfield = left(bitfield,length(bitfield)-1)
         else                                            /* no module number found */
            j = 0                                        /* no alias required */
      end
   end
   else if left(bitfield,3) = 'SSP' then do              /* SSP related bitfields */
      j = substr(bitfield,4,1)                           /* extract module number */
      if datatype(j) = 'NUM' & j = 1 then                /* first module */
         strippedfield = delstr(bitfield,4,1)            /* remove the number */
      else                                               /* no module number found */
         j = 0                                           /* no alias required */
   end
end

if j = 0 then                                            /* no module number found */
   return                                                /* no alias required */
if j = 1 then                                            /* first module */
   j = ''                                                /* no suffix */
alias = reg'_'strippedfield||j                           /* alias name (with suffix) */
call list_alias alias, reg'_'bitfield                    /* declare alias subfields */
return


/* --------------------------------------------- */
/* Formatting of SFR subfield aliases            */
/* Generates aliases for bitfields               */
/* input:  - index of register line  in .pic     */
/*         - alias of register                   */
/*         - original register                   */
/* --------------------------------------------- */
list_sfr_subfield_alias: procedure expose Pic. Name. PinMap. PinANMap. PortLat. ,
                                          PicName Core jalfile msglevel
parse upper arg i, reg_alias, reg .

do while word(pic.i,1) \= '</EDC:SFRMODELIST>'

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:SFRMODE' then do                     /* new set of subfields */
         offset = 0                                         /* reset bitfield offset */
         parse var Pic.i '<EDC:SFRMODE' 'EDC:ID="' Val1 '"' .
         if ( PicName = '12f609' | PicName = '12f615' | PicName = '12f617' |,
              PicName = '12f629' | PicName = '12f635' | PicName = '12f675' |,
              PicName = '12hv609' | PicName = '12hv615' ) then do
            if Val1 \= 'DS.0'  then do                      /* only SFRmode 'DS.0' */
               do until word(pic.i,1) = '</EDC:SFRMODE>'
                  i = i + 1
               end
            end
         end
         else do                                            /* all SFRmodes DS. and LT. */
            if \(left(Val1,3) = 'DS.' | left(Val1,3) = 'LT.') then do
               do until word(pic.i,1) = '</EDC:SFRMODE>'
                  i = i + 1
               end
            end
         end
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' Val1 '"' .
         if Val1 \= '' then do
            offset = offset + Val1
         end
      end

      when kwd = '<EDC:SFRFIELDDEF' then do
         parse var Pic.i '<EDC:SFRFIELDDEF' 'EDC:CNAME="' val1 '"' . ,
                          'EDC:MASK="' val3 '"' . 'EDC:NZWIDTH="' val4 '"' .
         if val1 \= '' then do
            field = reg'_'val1
            width = strip(val4)
            if left(width,2) = '0X' then
               width = X2D(substr(width,3))
            alias  = ''                                     /* nul alias */
            if width \= 8 then do                           /* skip 8-bit width subfields */
               original = reg'_'val1                        /* original subfield */
               if (left(n.j,4) = 'SSPM' & datatype(substr(val1,5)) = 'NUM') then do
                  if right(val1,1) = '0' then do            /* last enumerated bit */
                     alias = reg_alias'_SSPM'               /* not enumerated */
                     original = reg'_SSPM'                  /* modify original too */
                  end
               end
               else do
                  alias = reg_alias'_'val1
               end
            end
            if alias \= '' then do
               call list_alias alias, original
            end
         end
         offset = offset + width                            /* next offset */
      end
   otherwise
      nop
   end
   i = i + 1                                                /* next record */
end
return 0


/* -------------------------------------------------- */
/* procedure to list non memory mapped registers      */
/* of 12-bit core as pseudo variables.                */
/* Only some selected registers are handled:          */
/* TRISxx and OPTIONxx                                */
/* input:  - nothing                                  */
/* Note: name is stored but not checked on duplicates */
/* 12-bit core                                        */
/* -------------------------------------------------- */
list_nmmr12: procedure expose Pic. Ram. Name. PinMap.  SharedMem. PicName,
                              jalfile BankSize NumBanks msglevel
do i = 1 to Pic.0  while word(Pic.i,1) \= '<EDC:NMMRPLACE'  /* start ofNMMR specs */
   nop
end

do i = i to Pic.0 while word(pic.i,1) \= '</EDC:NMMRPLACE>'   /* end of NMMRs */

   kwd = word(Pic.i,1)
   if kwd = '<EDC:SFRDEF' then do
      parse var Pic.i '<EDC:SFRDEF' . 'EDC:CNAME="' Val1 '"' .
      if Val1 \= '' then do
         reg = strip(Val1)
         Name.reg = reg                                        /* add to collection of names */
         field = 'byte  '

         if left(reg,4) = 'TRIS' then do                       /* handle TRISIO or TRISGPIO */
            Name.reg = reg                                     /* add to collection of names */
            call lineout jalfile, '-- ------------------------------------------------'
            portletter = substr(reg,5)
            if portletter = 'IO' |  portletter = 'GPIO' |  portletter = '' then    /* TRIS[GP][IO] */
               portletter = 'A'                                /* handle as TRISA */
            shadow = '_TRIS'portletter'_shadow'
            if sharedmem.0 < 1 then do
               call msg 1, 'No (more) shared memory for' shadow
               call lineout jalfile, 'var volatile byte  ' left(shadow,25) '= 0b1111_1111    -- all input'
            end
            else do
               shared_addr = sharedmem.2
               call lineout jalfile, 'var volatile byte  ' left(shadow,25) 'at 0x'D2X(shared_addr),
                                      '= 0b1111_1111    -- all input'
               sharedmem.2 = sharedmem.2 - 1
               sharedmem.0 = sharedmem.0 - 1
            end
            call lineout jalfile, '--'
            call lineout jalfile, 'procedure PORT'portletter"_direction'put(byte in x",
                                                                           'at' shadow') is'
            call lineout jalfile, '   pragma inline'
            call lineout jalfile, '   asm movf' shadow',W'
            if reg = 'TRISIO' | reg = 'TRISGPIO' then          /* TRIS[GP]IO (small PIC) */
               call lineout jalfile, '   asm tris 6'
            else                                               /* TRISx */
               call lineout jalfile, '   asm tris' 5 + C2D(portletter) - C2D('A')
            call lineout jalfile, 'end procedure'
            call lineout jalfile, '--'
            half = 'PORT'portletter'_low_direction'
            call lineout jalfile, 'procedure' half"'put"'(byte in x) is'
            call lineout jalfile, '   'shadow '= ('shadow '& 0xF0) | (x & 0x0F)'
            call lineout jalfile, '   asm movf _TRIS'portletter'_shadow,W'
            if reg = 'TRISIO' then                             /* TRISIO (small PICs) */
               call lineout jalfile, '   asm tris 6'
            else                                               /* TRISx */
               call lineout jalfile, '   asm tris' 5 + C2D(portletter) - C2D('A')
            call lineout jalfile, 'end procedure'
            call lineout jalfile, '--'
            half = 'PORT'portletter'_high_direction'
            call lineout jalfile, 'procedure' half"'put"'(byte in x) is'
            call lineout jalfile, '   'shadow '= ('shadow '& 0x0F) | (x << 4)'
            call lineout jalfile, '   asm movf _TRIS'portletter'_shadow,W'
            if reg = 'TRISIO' then                             /* TRISIO (small PICs) */
               call lineout jalfile, '   asm tris 6'
            else                                               /* TRISx */
               call lineout jalfile, '   asm tris' 5 + C2D(portletter) - C2D('A')
            call lineout jalfile, 'end procedure'
            call lineout jalfile, '--'
            call list_nmmr_sub12_tris i, reg                   /* individual TRIS bits */
         end

         else if reg = 'OPTION_REG' | reg = OPTION2 then do    /* option */
            Name.reg = reg                                      /* add to collection of names */
            call lineout jalfile, '-- ------------------------------------------------'
            shadow = '_'reg'_shadow'
            if sharedmem.0 < 1 then do
               call msg 1, 'No (more) shared memory for' shadow
               call lineout jalfile, 'var volatile byte  ' left(shadow,25) '= 0b1111_1111    -- at reset'
            end
            else do
               shared_addr = sharedmem.2
               call lineout jalfile, 'var volatile byte  ' left(shadow,25) 'at 0x'D2X(shared_addr),
                                      '= 0b1111_1111    -- at reset'
               sharedmem.2 = sharedmem.2 - 1
               sharedmem.0 = sharedmem.0 - 1
            end
            call lineout jalfile, '--'
            call lineout jalfile, 'procedure' reg"'put(byte in x at" shadow') is'
            call lineout jalfile, '   pragma inline'
            call lineout jalfile, '   asm movf' shadow',0'
            if reg = 'OPTION_REG' then                          /* OPTION_REG */
               call lineout jalfile, '   asm option'
            else                                                /* OPTION2 */
               call lineout jalfile, '   asm tris 7'
            call lineout jalfile, 'end procedure'
            call list_nmmr_sub12_option i, reg                  /* subfields */
         end

      end

   end
end
return 0


/* ---------------------------------------- */
/* Formatting of non memory mapped register */
/* subfields of TRISx                       */
/* input:  - index in .pic                  */
/*         - port letter                    */
/* 12-bit core                              */
/* ---------------------------------------- */
list_nmmr_sub12_tris: procedure expose Pic. Name. PinMap. PicName,
                                       jalfile msglevel
parse arg i, reg .
i = i + 1

do while word(pic.i,1) \= '</EDC:SFRMODELIST>'

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:SFRMODE' then do                     /* new set of subfields */
         offset = 0                                         /* bitfield offset */
         parse var Pic.i '<EDC:SFRMODE' 'EDC:ID="' Val1 '"' .
         if left(Val1,3) \= 'DS.' then do
            do until word(pic.i,1) = '</EDC:SFRMODE>'
               i = i + 1
            end
         end
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' Val1 '"' .
         if Val1 \= '' then
            offset = offset + Val1
      end

      when kwd = '<EDC:SFRFIELDDEF' then do
         parse var Pic.i '<EDC:SFRFIELDDEF' 'EDC:CNAME="' val1 '"' . ,
                          'EDC:MASK="' val3 '"' . 'EDC:NZWIDTH="' val4 '"' .
         if val1 \= '' then do                              /* found */
            val1 = strip(val1)
            portletter = substr(reg,5)
            if portletter = 'IO' | portletter = 'GPIO' then     /* TRIS(GP)IO */
               portletter = 'A'                             /* handle as TRISA */
            shadow = '_TRIS'portletter'_shadow'
            call lineout jalfile, 'procedure pin_'portletter||offset"_direction'put(bit in x",
                                                      'at' shadow ':' offset') is'
            call lineout jalfile, '   pragma inline'
            call lineout jalfile, '   asm movf _TRIS'portletter'_shadow,W'
            if reg = 'TRISIO' | reg = 'TRISGPIO' then       /* TRIS(GP)IO */
               call lineout jalfile, '   asm tris 6'
            else                                            /* TRISx */
               call lineout jalfile, '   asm tris' 5 + C2D(portletter) - C2D('A')
            call lineout jalfile, 'end procedure'
            call list_pin_direction_alias reg, 'R'portletter||right(val1,1),,
                                  'pin_'portletter||right(val1,1)'_direction'
            call lineout jalfile, '--'
            if left(val4,2) = '0X' then
               val4 = X2D(substr(val4,3))
            offset = offset + val4
         end
      end

   otherwise
      nop

   end
   i = i + 1                                                /* next record */
end
return 0


/* ------------------------------------------------- */
/* Formatting of non memory mapped registers:        */
/* OPTION_REG and OPTION2                            */
/* input:  - index in .pic                           */
/*         - register name                           */
/* Generates names for pins or bits                  */
/* 12-bit core                                       */
/* ------------------------------------------------- */
list_nmmr_sub12_option: procedure expose Pic. Name. PinMap. PicName,
                                         jalfile msglevel
parse arg i, reg .
i = i + 1

do while word(pic.i,1) \= '</EDC:SFRMODELIST>'

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:SFRMODE' then do                     /* new set of subfields */
         offset = 0                                         /* bitfield offset */
         parse var Pic.i '<EDC:SFRMODE' 'EDC:ID="' Val1 '"' .
         if left(Val1,3) \= 'DS.' then do
            do until word(pic.i,1) = '</EDC:SFRMODE>'
               i = i + 1
            end
         end
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' Val1 '"' .
         if Val1 \= '' then
            offset = offset + Val1
      end

      when kwd = '<EDC:SFRFIELDDEF' then do
         parse var Pic.i '<EDC:SFRFIELDDEF' 'EDC:CNAME="' val1 '"' . ,
                          'EDC:MASK="' val3 '"' . 'EDC:NZWIDTH="' val4 '"' .
         if val1 \= '' then do                              /* found */
            call lineout jalfile, '--'
            field = reg'_'val1
            Name.field = field                              /* remember name */
            if left(val4,2) = '0X' then
               val4 = X2D(substr(val4,3))
            shadow = '_'reg'_shadow'
            if val4 = 1 then
               call lineout jalfile, 'procedure' field"'put"'(bit in x',
                                                 'at' shadow ':' offset') is'
            else
               call lineout jalfile, 'procedure' field"'put"'(bit*'val4 'in x',
                                                 'at' shadow ':' offset') is'
            call lineout jalfile, '   pragma inline'
            call lineout jalfile, '   asm movf' shadow',0'
            if reg = 'OPTION_REG' then                      /* OPTION_REG */
               call lineout jalfile, '   asm option'
            else                                            /* OPTION2 */
               call lineout jalfile, '   asm tris 7'
            call lineout jalfile, 'end procedure'
            if reg = 'OPTION_REG' then do
               if val1 = 'T0CS' | val1 = 'T0SE' | val1 = 'PSA' then
                  call list_alias 'T0CON_'val1, reg'_'val1
               else if val1 = 'PS' then
                  call list_alias 'T0CON_T0'val1, reg'_'val1
            end
         end
         offset = offset + val4
      end

   otherwise
      nop

   end
   i = i + 1                                                /* next record */
end
return 0


/* ---------------------------------------------------------------- */
/* procedure to list 'shared memory' SFRs of the midrange (NMMRs)   */
/* (in this case 'shared' is in the datasheet meaning:              */
/*  using the same memory address!)                                 */
/* input:  - nothing                                                */
/* output: - pseudo variables are declared                          */
/*         - subfields are expanded (separate procedure)            */
/* 14-bit core                                                      */
/* ---------------------------------------------------------------- */
list_nmmr14: procedure expose Pic. Ram. Name. jalfile BankSize NumBanks msglevel
do i = 1 to Pic.0
   if word(Pic.i,1) \= 'NMMR' then
      iterate
   parse var Pic.i 'NMMR' '(KEY=' val1 'MAPADDR=0X' val2 ' ADDR=0X' val0 'SIZE=' val3 .
   if val1 \= '' then do
      reg = strip(val1)                                     /* register name */
      Name.reg = reg                                        /* remember */
      subst  = '_'reg                                       /* substitute name */
      addr = strip(val2)                                    /* (mapped) address */
      size = strip(val3)                                    /* # bytes */
      if reg = 'SSPMSK' then do
         call lineout jalfile, '-- ------------------------------------------------'
         call lineout jalfile, 'var volatile byte  ' left(subst,25) 'at 0x'addr
         call lineout jalfile, '--'
         call lineout jalfile, 'procedure' reg"'put"'(byte in x) is'
         call lineout jalfile, '   var byte _sspcon_saved = SSPCON'
         call lineout jalfile, '   SSPCON_SSPM = 0b1001'
         call lineout jalfile, '   'subst '= x'
         call lineout jalfile, '   SSPCON = _sspcon_saved'
         call lineout jalfile, 'end procedure'
         call lineout jalfile, 'function' reg"'get"'() return byte is'
         call lineout jalfile, '   var  byte  x'
         call lineout jalfile, '   var byte _sspcon_saved = SSPCON'
         call lineout jalfile, '   SSPCON_SSPM = 0b1001'
         call lineout jalfile, '   x =' subst
         call lineout jalfile, '   SSPCON = _sspcon_saved'
         call lineout jalfile, '   return  x'
         call lineout jalfile, 'end function'
         call lineout jalfile, '--'
      end

/*    call list_nmmr_sub14 i, reg     */                    /* declare subfields */

   end
end
return 0


/* ------------------------------------------------------------ */
/* procedure to list 'shared memory' SFRs of the 18Fs (NMMRs)   */
/* (in this case 'shared' is in the datasheet meaning:          */
/*  using the same memory address!)                             */
/* input:  - nothing                                            */
/* output: - pseudo variables are declared                      */
/*         - subfields are expanded (separate procedure)        */
/* 16-bit core                                                  */
/* ------------------------------------------------------------ */
list_nmmr16: procedure expose Pic. Ram. Name. jalfile BankSize NumBanks msglevel,
                              Core
do i = 1 to Pic.0
   if word(Pic.i,1) \= 'NMMR' then
      iterate
   if pos('_INTERNAL',Pic.i) > 0  |,                        /* skip TMRx_internal */
      pos('_PRESCALE',Pic.i) > 0 then                       /* TMRx_prescale */
      iterate
   parse var Pic.i 'NMMR' '(KEY=' val1 'MAPADDR=0X' val2 ' ADDR=0X' val0 'SIZE=' val3 .
   if val1 \= '' then do
      reg = strip(val1)                                     /* register name */
      Name.reg = reg                                        /* remember */
      subst  = '_'reg                                       /* substitute name */
      addr = strip(val2)                                    /* (mapped) address */
      size = strip(val3)                                    /* # bytes */
      if reg = 'SSP1MSK' | reg = 'SSP2MSK' then do
         index = substr(reg,4,1)                            /* SSP module number */
         call lineout jalfile, '-- ------------------------------------------------'
         call lineout jalfile, 'var volatile byte  ' left(subst,25) 'at 0x'addr
         call lineout jalfile, '--'
         call lineout jalfile, 'procedure' reg"'put"'(byte in x) is'
         call lineout jalfile, '   var byte _ssp'index'con1_saved = SSP'index'CON1'
         call lineout jalfile, '   SSP'index'CON1_SSPM = 0b1001'
         call lineout jalfile, '   'subst '= x'
         call lineout jalfile, '   SSP'index'CON1 = _ssp'index'con1_saved'
         call lineout jalfile, 'end procedure'
         call lineout jalfile, 'function' reg"'get"'() return byte is'
         call lineout jalfile, '   var  byte  x'
         call lineout jalfile, '   var  byte  _ssp'index'con1_saved = SSP'index'CON1'
         call lineout jalfile, '   SSP'index'CON1_SSPM = 0b1001'
         call lineout jalfile, '   x =' subst
         call lineout jalfile, '   SSP'index'CON1 = _ssp'index'con1_saved'
         call lineout jalfile, '   return  x'
         call lineout jalfile, 'end function'
         call lineout jalfile, '--'
         if reg = SSP1MSK then
            call list_alias  'SSPMSK', reg
      end
      else if left(reg,6) = 'PMDOUT' then do
         call lineout jalfile, '-- ------------------------------------------------'
         call list_variable 'byte', reg, X2D(addr)               /* normal SFR! */
      end
      else do
         call lineout jalfile, '-- ------------------------------------------------'
         call lineout jalfile, 'var volatile byte  ' left(subst,25) 'at 0x'addr
         call lineout jalfile, '--'
         call lineout jalfile, 'procedure' reg"'put"'(byte in x) is'
         call lineout jalfile, '   WDTCON_ADSHR = TRUE'
         call lineout jalfile, '   'subst '= x'
         call lineout jalfile, '   WDTCON_ADSHR = FALSE'
         call lineout jalfile, 'end procedure'
         call lineout jalfile, 'function' reg"'get"'() return byte is'
         call lineout jalfile, '   var  byte  x'
         call lineout jalfile, '   WDTCON_ADSHR = TRUE'
         call lineout jalfile, '   x =' subst
         call lineout jalfile, '   WDTCON_ADSHR = FALSE'
         call lineout jalfile, '   return  x'
         call lineout jalfile, 'end function'
         call lineout jalfile, '--'
         call list_nmmr_sub16 i, reg                        /* declare subfields */
      end

   end
end
return 0


/* ----------------------------------------------- */
/* convert ANSEL-bit to JANSEL_number              */
/* input: - register  (ANSELx,ADCONx,ANCONx, etc.) */
/*        - Name of bit (ANSy)                     */
/* returns channel number                          */
/* All cores                                       */
/* This procedure has to be evaluated              */
/* with every additional PIC(-group)               */
/* Return value 99 indicates 'no JANSEL number'    */
/* ----------------------------------------------- */
ansel2j: procedure expose Core PicName PinMap. PinANMap. msglevel
parse upper arg reg, ans .                                  /* ans is name of bitfield! */

if datatype(right(ans,2),'W') = 1 then                      /* name ends with 2 digits */
   ansx = right(ans,2)                                      /* 2 digits seq. nbr. */
else                                                        /* 1 digit assumed */
   ansx = right(ans,1)                                      /* single digit seq. nbr. */

if core = '12' | core = '14' then do                        /* baseline, classic midrange */
   select
      when reg = 'ANSELH' | reg = 'ANSEL1' then do
         if ansx < 8 then                                   /* continuation of ANSEL[0|A] */
            ansx = ansx + 8
      end
      when reg = 'ANSELG' then do
         if ansx < 8 then
            ansx = ansx + 8
      end
      when reg = 'ANSELE' then do
         if left(PicName,5) = '16f70' | left(PicName,6) = '16lf70' |,
            left(PicName,5) = '16f72' | left(PicName,6) = '16lf72' then
            ansx = ansx + 5
         else
            ansx = ansx + 20
      end
      when reg = 'ANSELD' then do
         if left(PicName,5) = '16f70' | left(PicName,6) = '16lf70' |,
            left(PicName,5) = '16f72' | left(PicName,6) = '16lf72' then
            ansx = 99                                       /* not for ADC */
         else
            ansx = ansx + 12
      end
      when reg = 'ANSELC' then do
         if left(PicName,5) = '16f70' | left(PicName,6) = '16lf70' then
            ansx = 99
         else if right(PicName,4) = 'f720' | right(PicName,4) = 'f721' then
            ansx = word('4 5 6 7 99 99 8 9', ansx + 1)
         else
            ansx = ansx + 12
      end
      when reg = 'ANSELB' then do
         if right(PicName,4) = 'f720' | right(PicName,4) = 'f721' then
            ansx = ansx + 6
         else if left(PicName,5) = '16f70' | left(PicName,6) = '16lf70' |,
                 left(PicName,5) = '16f72' | left(PicName,6) = '16lf72' then
            ansx = word('12 10 8 9 11 13 99 99', ansx + 1)
         else
            ansx = ansx + 6
      end
      when reg = 'ANSELA' | reg = 'ANSEL' | reg = 'ANSEL0' | reg = 'ADCON0' then do
         if right(PicName,4) = 'f752' | right(PicName,5) = 'hv752' |,
            right(PicName,4) = 'f720' | right(PicName,4) = 'f721' then
            ansx = word('0 1 2 99 3 99 99 99', ansx + 1)
         else if left(PicName,5) = '16f70' | left(PicName,6) = '16lf70' |,
                 left(PicName,5) = '16f72' | left(PicName,6) = '16lf72' then
            ansx = word('0 1 2 3 99 4 99 99', ansx + 1)
         else
            ansx = ansx + 0                                 /* no change of ansx */
      end
   otherwise
      call msg 3, 'Unsupported ADC register for' PicName ':' reg
      ansx = 99
   end
end

else if core = '14H' then do                                /* enhanced midrange */
   select
      when reg = 'ANSELG' then do
         ansx = word('99 15 14 13 12 99 99 99', ansx + 1)
      end
      when reg = 'ANSELF' then do
         ansx = word('16 6 7 8 9 10 11 5', ansx + 1)
      end
      when reg = 'ANSELE' then do
         if left(PicName,6) = '16f151'  | left(PicName,7) = '16lf151' |,
            left(PicName,6) = '16f178'  | left(PicName,7) = '16lf178' |,
                                          left(PicName,7) = '16lf190' |,
            left(PicName,6) = '16f193'  | left(PicName,7) = '16lf193' then
            ansx = ansx + 5
         else if left(PicName,6) = '16f152' | left(PicName,7) = '16lf152' then
            ansx = word('27 28 29 99 99 99 99 99', ansx + 1)
         else if left(PicName,6) = '16f194' | left(PicName,7) = '16lf194' then
            ansx = 99                              /* none */
         else
            ansx = ansx + 20
      end
      when reg = 'ANSELD' then do
         if left(PicName,6) = '16f151' | left(PicName,7) = '16lf151' then
            ansx = ansx + 20
         else if left(PicName,6) = '16f152' | left(PicName,7) = '16lf152' then
            ansx = word('23 24 25 26 99 99 99 99', ansx + 1)
         else
            ansx = 99                              /* none */
      end
      when reg = 'ANSELC' then do
         if left(PicName,6) = '16f151' | left(PicName,7) = '16lf151' then
            ansx = word('99 99 14 15 16 17 18 19', ansx + 1)
         else if left(PicName,6) = '16f145' | left(PicName,7) = '16lf145' |,
                 left(PicName,6) = '16f150' | left(PicName,7) = '16lf150' |,
                 left(PicName,6) = '16f182' | left(PicName,7) = '16lf182' then
            ansx = word('4 5 6 7 99 99 8 9', ansx + 1)
         else
            ansx = 99                              /* none */
      end
      when reg = 'ANSELB' then do
         if PicName = '16f1826' | PicName = '16lf1826' |,
            PicName = '16f1827' | PicName = '16lf1827' |,
            PicName = '16f1847' | PicName = '16lf1847' then
            ansx = word('99 11 10 9 8 7 5 6', ansx + 1)
         else if left(PicName,6) = '16f145' | left(PicName,7) = '16lf145' then
            ansx = word('99 99 99 99 10 11 99 99', ansx + 1)
         else if left(PicName,6) = '16f150' | left(PicName,7) = '16lf150' |,
                 left(PicName,6) = '16f182' | left(PicName,7) = '16lf182' then
            ansx = word('99 99 99 99 10 11 99 99 ', ansx + 1)
         else if left(PicName,6) = '16f151' | left(PicName,7) = '16lf151' |,
                 left(PicName,6) = '16f178' | left(PicName,7) = '16lf178' |,
                 left(PicName,7) = '16lf190'                              |,
                 left(PicName,6) = '16f193' | left(PicName,7) = '16lf193' then
            ansx = word('12 10 8 9 11 13 99 99', ansx + 1)
         else if left(PicName,6) = '16f152' | left(PicName,7) = '16lf152' then
            ansx = word('17 18 19 20 21 22 99 99', ansx + 1)
      end
      when reg = 'ANSELA' then do
         if PicName = '16f1826' | PicName = '16lf1826' |,
            PicName = '16f1827' | PicName = '16lf1827' |,
            PicName = '16f1847' | PicName = '16lf1847' then
            ansx = ansx + 0
         else if left(PicName,6) = '16f145' | left(PicName,7) = '16lf145' then
            ansx = word('99 99 99 99 3 99 99 99', ansx + 1)
         else if left(PicName,6) = '12lf15' then
            ansx = word('0 1 2 99 3 4 99 99', ansx + 1)
         else if left(PicName,6) = '12f150' | left(PicName,7) = '12lf150' |,
                 left(PicName,6) = '12f182' | left(PicName,7) = '12lf182' |,
                 left(PicName,6) = '12f184' | left(PicName,7) = '12lf184' |,
                 left(PicName,6) = '16f150' | left(PicName,7) = '16lf150' |,
                 left(PicName,6) = '16f182' | left(PicName,7) = '16lf182' then
            ansx = word('0 1 2 99 3 99 99 99', ansx + 1)
         else if left(PicName,6) = '16f151' | left(PicName,7) = '16lf151' |,
                 left(PicName,6) = '16f152' | left(PicName,7) = '16lf152' |,
                 left(PicName,6) = '16f178' | left(PicName,7) = '16lf178' |,
                 left(PicName,7) = '16lf190'                              |,
                 left(PicName,6) = '16f193' | left(PicName,7) = '16lf193' |,
                 left(PicName,6) = '16f194' | left(PicName,7) = '16lf194' then
            ansx = word('0 1 2 3 99 4 99 99', ansx + 1)
      end
   otherwise
      call msg 3, 'Unsupported ADC register for' PicName ':' reg
      ansx = 99
   end
end

else if core = '16' then do                                 /* 18F series */
   select
      when reg = 'ANCON3' then do
         if ansx < 8 then do
            if right(PicName, 3) = 'j94' | right(PicName, 3) = 'j99' then
               ansx = ansx + 16
            else
               ansx = ansx + 24
         end
      end
      when reg = 'ANCON2' then do
         if ansx < 8 then do
            if right(PicName, 3) = 'j94' | right(PicName, 3) = 'j99' then
               ansx = ansx + 8
            else
               ansx = ansx + 16
         end
      end
      when reg = 'ANCON1' then do
         if ansx < 8 then do
            if right(PicName, 3) = 'j94' | right(PicName, 3) = 'j99' then
               ansx = ansx + 0
            else
               ansx = ansx + 8
         end
      end
      when reg = 'ANCON0' then do
         if ansx < 8 then
            ansx = ansx + 0
      end
      when reg = 'ANSELH' | reg = 'ANSEL1' then do
         if ansx < 8 then
            ansx = ansx + 8
      end
      when reg = 'ANSELE' then do
         ansx = ansx + 5
      end
      when reg = 'ANSELD' then do
         ansx = ansx + 20
      end
      when reg = 'ANSELC' then do
         ansx = ansx + 12
      end
      when reg = 'ANSELB' then do
         ansx = word('12 10 8 9 11 13 99 99', ansx + 1)
      end
      when reg = 'ANSELA' | reg = 'ANSEL' | reg = 'ANSEL0' then do
         if PicName = '18f13k22' | PicName = '18lf13k22' |,
            PicName = '18f14k22' | PicName = '18lf14k22' then
            nop                                             /* consecutive */
         else if PicName = '18f24k50' | PicName = '18lf24k50' |,
                 PicName = '18f25k50' | PicName = '18lf25k50' |,
                 PicName = '18f45k50' | PicName = '18lf45k50' then
            ansx = word('0 1 2 3 99 4 99 99', ansx + 1)
         else if right(PicName,3) = 'k22' & ansx = 5 then
            ansx = 4                                        /* jump */
      end
   otherwise
      call msg 3, 'Unsupported ADC register for' PicName ':' reg
      ansx = 99
    end
end

PicNameCaps = toupper(PicName)
aliasname    = 'AN'ansx
if ansx < 99 & PinANMap.PicNameCaps.aliasname = '-' then do  /* no match */
   call msg 2, 'No "pin_AN'ansx'" alias in pinmap'
   ansx = 99                                                /* error indication */
end
return ansx


/* --------------------------------------------------- */
/* procedure to create port shadowing functions        */
/* for full byte, lower- and upper-nibbles             */
/* For 12- and 14-bit core                             */
/* input:  - Port register                             */
/* shared memory is allocated from high to low address */
/* --------------------------------------------------- */
list_port1x_shadow: procedure expose jalfile sharedmem. msglevel
parse upper arg reg .
shadow = '_PORT'substr(reg,5)'_shadow'
call lineout jalfile, '--'
call lineout jalfile, 'var          byte  ' left('PORT'substr(reg,5),25) 'at _PORT'substr(reg,5)
if sharedmem.0 < 1 then do
   call msg 1, 'No (more) shared memory for' shadow
   call lineout jalfile, 'var volatile byte  ' left(shadow,25)
end
else do
   shared_addr = sharedmem.2
   call lineout jalfile, 'var volatile byte  ' left(shadow,25) 'at 0x'D2X(shared_addr)
   sharedmem.2 = sharedmem.2 - 1
   sharedmem.0 = sharedmem.0 - 1
end
call lineout jalfile, '--'
call lineout jalfile, 'procedure' reg"'put"'(byte in x at' shadow') is'
call lineout jalfile, '   pragma inline'
call lineout jalfile, '   _PORT'substr(reg,5) '=' shadow
call lineout jalfile, 'end procedure'
call lineout jalfile, '--'
half = 'PORT'substr(reg,5)'_low'
call lineout jalfile, 'procedure' half"'put"'(byte in x) is'
call lineout jalfile, '   'shadow '= ('shadow '& 0xF0) | (x & 0x0F)'
call lineout jalfile, '   _PORT'substr(reg,5) '=' shadow
call lineout jalfile, 'end procedure'
call lineout jalfile, 'function' half"'get()" 'return byte is'
call lineout jalfile, '   return ('reg '& 0x0F)'
call lineout jalfile, 'end function'
call lineout jalfile, '--'
half = 'PORT'substr(reg,5)'_high'
call lineout jalfile, 'procedure' half"'put"'(byte in x) is'
call lineout jalfile, '   'shadow '= ('shadow '& 0x0F) | (x << 4)'
call lineout jalfile, '   _PORT'substr(reg,5) '=' shadow
call lineout jalfile, 'end procedure'
call lineout jalfile, 'function' half"'get()" 'return byte is'
call lineout jalfile, '   return ('reg '>> 4)'
call lineout jalfile, 'end function'
call lineout jalfile, '--'
return


/* ------------------------------------------------ */
/* procedure to force use of LATx with 16-bits core */
/* for full byte, lower- and upper-nibbles          */
/* input:  - LATx register                          */
/* ------------------------------------------------ */
list_port16_shadow: procedure expose jalfile
parse upper arg lat .
port = 'PORT'substr(lat,4)                                  /* corresponding port */
call lineout jalfile, '--'
call lineout jalfile, 'procedure' port"'put"'(byte in x at' lat') is'
call lineout jalfile, '   pragma inline'
call lineout jalfile, 'end procedure'
call lineout jalfile, '--'
half = 'PORT'substr(lat,4)'_low'
call lineout jalfile, 'procedure' half"'put"'(byte in x) is'
call lineout jalfile, '   'lat '= ('lat '& 0xF0) | (x & 0x0F)'
call lineout jalfile, 'end procedure'
call lineout jalfile, 'function' half"'get()" 'return byte is'
call lineout jalfile, '   return ('port '& 0x0F)'
call lineout jalfile, 'end function'
call lineout jalfile, '--'
half = 'PORT'substr(lat,4)'_high'
call lineout jalfile, 'procedure' half"'put"'(byte in x) is'
call lineout jalfile, '   'lat '= ('lat '& 0x0F) | (x << 4)'
call lineout jalfile, 'end procedure'
call lineout jalfile, 'function' half"'get()" 'return byte is'
call lineout jalfile, '   return ('port '>> 4)'
call lineout jalfile, 'end function'
call lineout jalfile, '--'
return


/* ---------------------------------------------- */
/* procedure to create TRIS functions             */
/* for lower- and upper-nibbles only              */
/* input:  - TRIS register                        */
/* ---------------------------------------------- */
list_tris_nibbles: procedure expose jalfile
parse upper arg reg .
call lineout jalfile, '--'
half = 'PORT'substr(reg,5)'_low_direction'
call lineout jalfile, 'procedure' half"'put"'(byte in x) is'
call lineout jalfile, '   'reg '= ('reg '& 0xF0) | (x & 0x0F)'
call lineout jalfile, 'end procedure'
call lineout jalfile, 'function' half"'get()" 'return byte is'
call lineout jalfile, '   return ('reg '& 0x0F)'
call lineout jalfile, 'end function'
call lineout jalfile, '--'
half = 'PORT'substr(reg,5)'_high_direction'
call lineout jalfile, 'procedure' half"'put"'(byte in x) is'
call lineout jalfile, '   'reg '= ('reg '& 0x0F) | (x << 4)'
call lineout jalfile, 'end procedure'
call lineout jalfile, 'function' half"'get()" 'return byte is'
call lineout jalfile, '   return ('reg '>> 4)'
call lineout jalfile, 'end function'
call lineout jalfile, '--'
return


/* ----------------------------------------------------- */
/* procedure to list SFR subfields                       */
/* input: - start index in pic.                          */
/* Note:  - name is stored but not checked on duplicates */
/* ----------------------------------------------------- */
list_status: procedure expose Pic. Name. Core PicName jalfile msglevel
parse arg i .

offset = 0

do i = i while word(pic.i,1) \= '</EDC:SFRDEF>'

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:SFRMODE' then do
         offset = 0                                         /* bitfield offset */
      end

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' Val1 '"' .
         if Val1 \= '' then
            offset = offset + Val1
      end

      when kwd = '<EDC:SFRFIELDDEF' then do
         parse var Pic.i '<EDC:SFRFIELDDEF' 'EDC:CNAME="' val1 '"' . ,
                          'EDC:MASK="' val3 '"' . 'EDC:NZWIDTH="' val4 '"' .
         if val1 \= '' then do
            val1 = tolower(strip(val1))
            val4 = strip(val4)
            if left(val4,2) = '0X' then
               val4 = X2D(substr(val4,3))
            if val4 = 1 then do
               if val1 = 'nto' then
                  call lineout jalfile, 'const        byte  ' left('_not_to',25) '= ' offset
               else if val1 = 'npd' then
                  call lineout jalfile, 'const        byte  ' left('_not_pd',25) '= ' offset
               else
                  call lineout jalfile, 'const        byte  ' left('_'val1,25) '= ' offset
               offset = offset + 1
            end
            else
               offset = offset + val4                       /* skip multibit fields */
         end
      end

   otherwise
      nop
   end

end

if Core = '16' then do
   call lineout jalfile, 'const        byte  ' left('_banked',25) '=  1'
   call lineout jalfile, 'const        byte  ' left('_access',25) '=  0'
end

return 0


/* ---------------------------------------------------- */
/* procedure to list fusedef specifications             */
/* input:  - nothing                                   */
/* ---------------------------------------------------- */
list_fusedef: procedure expose Pic. Ram. Name. Fuse_def. Core PicName jalfile,
                             msglevel CfgAddr.

call lineout jalfile, '--'
call lineout jalfile, '-- ============================================='
call lineout jalfile, '--'
call lineout jalfile, '-- Symbolic Fuse Definitions'
call lineout jalfile, '-- -------------------------'


FuseAddr = 0                                                /* start value */

do i = 1 to Pic.0  until (word(Pic.i,1) = '<EDC:CONFIGFUSESECTOR' |,
                          word(Pic.i,1) = '<EDC:WORMHOLESECTOR')    /* fusedefs */
   nop
end

if word(Pic.i,1) = '<EDC:CONFIGFUSESECTOR' then
   parse var Pic.i '<EDC:CONFIGFUSESECTOR' 'EDC:BEGINADDR="0X' Val1 '"' .
else
   parse var Pic.i '<EDC:WORMHOLESECTOR' 'EDC:BEGINADDR="0X' Val1 '"' .

if Val1 \= '' then
   FuseAddr = X2D(Val1)                                     /* start address */

FuseStart = FuseAddr

do i = i to Pic.0 until (word(pic.i,1) = '</EDC:CONFIGFUSESECTOR>' |,
                         word(pic.i,1) = '</EDC:WORMHOLESECTOR>')   /* end of fusedefs */

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' val1 '"' .
         if Val1 \= '' then do
            val1 = strip(val1)
            if left(val1,2) = '0X' then
               val1 = X2D(val1)
            FuseAddr = FuseAddr + Val1
         end
      end

      when kwd = '<EDC:DCRDEF' then do
         parse var Pic.i '<EDC:DCRDEF' . 'EDC:CNAME="' Val1 '"' ,
                          'EDC:DEFAULT="0X' val2 '"' . 'EDC:NZWIDTH=' val3 '"' .
         if Val1 \= '' then do
            call lineout jalfile, '--'
            call lineout jalfile, '--' strip(val1) '(0x'D2X(FuseAddr)')'
            call lineout jalfile, '--'
            call list_fusedef_fielddefs i, FuseAddr - FuseStart   /* fusedef bit fields */
         end
         FuseAddr = FuseAddr + 1
         do while word(Pic.i,1) \= '</EDC:DCRDEF>'
            i = i + 1                                       /* skip inner statements */
         end
      end

   otherwise
      nop
   end

end
call lineout jalfile, '--'
return 0


/* ---------------------------------------------------- */
/* procedure to list Fusedef subfields                  */
/* input:  - index in Pic.                              */
/*         - fuse byte/word index                       */
/* ---------------------------------------------------- */
list_fusedef_fielddefs: procedure expose Pic. CfgAddr. Fuse_Def. PicName Core jalfile msglevel
parse arg i, index .

do i = i to Pic.0  while word(Pic.i,1) \= '<EDC:DCRMODE'     /* fusedef subfields */
   nop
end

offset = 0                                                  /* bit offset */

do i = i while word(pic.i,1) \= '</EDC:DCRMODE>'

   kwd = word(Pic.i,1)

   select

      when kwd = '<EDC:ADJUSTPOINT' then do
         parse var Pic.i '<EDC:ADJUSTPOINT' 'EDC:OFFSET="' Val1 '"' .
         if Val1 \= '' then do
            offset = offset + Val1                          /* bit offset */
         end
      end

      when kwd = '<EDC:DCRFIELDDEF' then do
         parse var Pic.i '<EDC:DCRFIELDDEF' 'EDC:CNAME="' val1 '"' 'EDC:DESC="' val2 '"',
                          'EDC:MASK="0X' val3 '"' . 'EDC:NZWIDTH="' val4 '"' .
         if Val1 \= ''  &  Val1 \= 'RESERVED'  &  val2 \= 'RESERVED' then do
            key = normalize_fusedef_key(Val1)               /* uniform key */
            if \(key = 'OSC' & left(PicName,5) = '10f20') then do   /* no an exception */
               mask = strip(B2X(X2B(val3)||copies('0',offset)),'L','0')    /* bit alignment */
               if CfgAddr.0 = 1 then                        /* single byte/word */
                  str = 'pragma fuse_def' key '0x'mask '{'
               else                                         /* multi byte/word */
                  str = 'pragma fuse_def' key':'index '0x'mask '{'
               call lineout jalfile, left(str, 42) '--' tolower(val2)
               call list_fusedef_fieldsemantics i, offset, key
               call lineout jalfile, '       }'
            end
            if left(val4,2) = '0X' then
               val4 = X2D(substr(val4,3))
            offset = offset + val4                          /* adjust bit offset */
         end
      end

   otherwise
      nop
   end

end
return


/* ---------------------------------------------------- */
/* procedure to list Fusedef subfields                  */
/* input:  - index in Pic.                              */
/*         - bitfield offset                            */
/* ---------------------------------------------------- */
list_fusedef_fieldsemantics: procedure expose Pic. Fuse_Def. Core PicName jalfile msglevel
parse arg i, offset, key .

do i = i to Pic.0  while word(Pic.i,1) \= '<EDC:DCRFIELDSEMANTIC'     /* fusedef subfields */
   nop
end

kwdname. = '-'                                           /* no key names collected yet */

do i = i while word(pic.i,1) \= '</EDC:DCRFIELDDEF>'
   if word(Pic.i,1) = '<EDC:DCRFIELDSEMANTIC' then do
      parse var Pic.i '<EDC:DCRFIELDSEMANTIC' 'EDC:CNAME="' val1 '"',
                       'EDC:DESC="' val2 '"' 'EDC:WHEN="' . '==' '0X' val3 '"' .
      if val1 = '' then do                               /* try without cname */
         parse var Pic.i '<EDC:DCRFIELDSEMANTIC' ,
                       'EDC:DESC="' val2 '"' 'EDC:WHEN="' . '==' '0X' val3 '"' .
      end
      if val2 \= '' then do
         val2 = toascii(val2)                            /* replace xml meta */
         kwd = normalize_fusedef_keyword(key, val1, '"'val2'"')      /* normalize keyword */
         if kwd = '' then                                /* probably reserved */
            iterate
         mask = strip(B2X(X2B(val3)||copies('0',offset)),'L','0')    /* bit alignment */
         if mask = '' then
            mask = '0'
         if kwdname.kwd \= '-' then do                   /* duplicate */
            call msg 2, 'Duplicate fuse_def' key '{'kwd '= 0x'mask'}, skipped!'
         end
         else do
            kwdname.kwd = kwd                            /* remember name */
            call lineout jalfile, left('       'kwd '= 0x'mask, 42) '--' tolower(val2)
         end
      end
   end
end
return


/* ---------------------------------------------------- */
/* procedure to normalize fusedef keywords              */
/* input:  - keyword                                    */
/* returns - normalized keyword                         */
/* ---------------------------------------------------- */
normalize_fusedef_key: procedure expose PicName
parse arg key .

if key \= '' then do                               /* key value found */
                                                   /* skip some superfluous bits */
   if ( key = 'RES' | key = 'RES1' | left(key,8) = 'RESERVED' )    |,
      ( pos('ENICPORT',key) > 0 )                          |,
      ( (key = 'CPD' | key = 'WRTD')  &,
        (PicName = '18f2410' | PicName = '18f2510' |,
         PicName = '18f2515' | PicName = '18f2610' |,
         PicName = '18f4410' | PicName = '18f4510' |,
         PicName = '18f4515' | PicName = '18f4610') )      |,
      ( (key = 'EBTR_3' | key = 'CP_3' | key = 'WRT_3') &,
        (PicName = '18f4585') )                            |,
      ( (key = 'EBTR_4' | key = 'CP_4' | key = 'WRT_4' |,
         key = 'EBTR_5' | key = 'CP_5' | key = 'WRT_5' |,
         key = 'EBTR_6' | key = 'CP_6' | key = 'WRT_6' |,
         key = 'EBTR_7' | key = 'CP_7' | key = 'WRT_7')  &,
        (PicName = '18f6520' | PicName = '18f8520') )      then do
      return key
   end

   select                                          /* reduce synonyms and */
                                                   /* correct MPLAB-X errors */
      when key = 'ADDRBW' then
         key = 'ABW'
      when key = 'BACKBUG' | key = 'BKBUG' then
         key = 'DEBUG'
      when key = 'BBSIZ0' then
         key = 'BBSIZ'
      when key = 'BODENV' | key = 'BOR4V' | key = 'BORV' then
         key = 'VOLTAGE'
      when key = 'BODEN' | key = 'BOREN' | key = 'DSBOREN' | key = 'BOD' | key = 'BOR' then
         key = 'BROWNOUT'
      when key = 'CANMX' then
         key = 'CANMUX'
      when left(key,3) = 'CCP' & right(key,2) = 'MX' then do
         key = left(key,pos('MX',key)-1)'MUX'      /* CCP(x)MX -> CCP(x)MUX */
         if key = 'CCPMUX' then
            key = 'CCP1MUX'                        /* compatibility */
      end
      when key = 'CPDF' | key = 'CPSW' then
         key = 'CPD'
      when left(key,3) = 'CP_' & datatype(substr(key,4),'W') = 1 then
         key = 'CP'substr(key,4)                   /* remove underscore */
      when key = 'DATABW' then
         key = 'BW'
      when left(key,4) = 'EBRT' then               /* typo in .pic files */
         key = 'EBTR'substr(key,5)
      when left(key,5) = 'EBTR_' & datatype(substr(key,6),'W') = 1 then
         key = 'EBTR'substr(key,6)                 /* remove underscore */
      when key = 'ECCPMX' | key = 'ECCPXM' then
         key = 'ECCPMUX'                           /* ECCPxMX -> ECCPxMUX */
      when key = 'EXCLKMX' then
         key = 'EXCLKMUX'
      when key = 'FLTAMX' then
         key = 'FLTAMUX'
      when key = 'FOSC' | key = 'FOSC0' then
         key = 'OSC'
      when key = 'FSCKM' | key = 'FSCM' then
         key = 'FCMEN'
      when key = 'MCLRE' then
         key = 'MCLR'
      when key = 'MSSP7B_EN' | key = 'MSSPMSK' then
         key = 'MSSPMASK'
      when key = 'P2BMX' then
         key = 'P2BMUX'
      when key = 'PLL_EN' | key = 'CFGPLLEN' | key = 'PLLCFG' then
         key = 'PLLEN'
      when key = 'MODE' | key = 'PM' then
         key = 'PMODE'
      when key = 'PMPMX' then
         key = 'PMPMUX'
      when key = 'PWM4MX' then
         key = 'PWM4MUX'
      when key = 'PUT' | key = 'PWRT' | key = 'PWRTEN' |,
           key = 'NPWRTE' | key = 'NPWRTEN' then
         key = 'PWRTE'
      when key = 'RTCSOSC' then
         key = 'RTCOSC'
      when key = 'SOSCEL' then
         key = 'SOSCSEL'
      when key = 'SSPMX' then
         key = 'SSPMUX'
      when key = 'STVREN' then
         key = 'STVR'
      when key = T0CKMX then
         key = 'T0CKMUX'
      when key = 'T1OSCMX' then
         key = 'T1OSCMUX'
      when key = 'T3CMX' then
         key = 'T3CMUX'
      when key = 'T3CKMX' then
         key = 'T3CKMUX'
      when key = 'USBDIV'  &,                      /* compatibility */
           (left(PicName,6) = '18f245' | left(PicName,6) = '18f255' |,
            left(PicName,6) = '18f445' | left(PicName,6) = '18f455' ) then
         key = 'USBPLL'
      when key = 'WDTEN' | key = 'WDTE' then
         key = 'WDT'
      when key = 'WDPS' then
         key = 'WDTPS'
      when key = 'WRT_ENABLE' | key = 'WRTEN' then
         key = 'WRT'
      when left(key,4) = 'WRT_' & datatype(substr(key,5),'W') = 1 then
         key = delstr(key,4,1)                     /* remove underscore from 'WRT_x' */
   otherwise
      nop                                          /* accept any other key asis */
   end

end

return key

end


/* ------------------------------------------------------------------------ */
/* Detailed formatting of fusedef keywords                                  */
/* input:  - fuse_def keyword                                               */
/*         - value                                                          */
/*         - value description                                              */
/* returns normalized keyword                                               */
/*                                                                          */
/* notes: val2 contains keyword description with undesired chars and blanks */
/*        val2u is val2 with all these replaced by a single underscore      */
/* ------------------------------------------------------------------------ */
normalize_fusedef_keyword: procedure expose Pic. Fuse_Def. jalfile Fuse_Def.,
                                          Core PicName msglevel
parse upper arg key, val, desc

desc = strip(desc, 'B', '"')                             /* strip double quoted */
desc = toascii(desc)                                     /* replace xml meta by ASCII char */
descu = translate(desc, '                 ',,            /* to blank */
                        '+-:;.,<>{}[]()=/?')             /* from special char */
descu = space(descu,,'_')                                /* blanks -> single underscore */

kwd = ''                                                 /* null keyword */

select                                                   /* key specific formatting */

   when val = 'RESERVED' then do                         /* reserved values to be skipped */
      return ''
   end

   when key = 'ADCSEL'  |,                               /* ADC resolution */
        key = 'ABW'     |,                               /* address bus width */
        key = 'BW'    then do                            /* external memory bus width */
      parse value word(desc,1) with kwd '-' .            /* assign number */
      kwd = 'B'kwd                                       /* add prefix */
   end

   when key = 'BBSIZ' then do
      if desc = 'ENABLED' then do
         kwd = desc
      end
      else if desc = 'DISABLED' then do
         kwd = desc
      end
      else do j=1 to words(desc)
         if left(word(desc,j),1) >= '0' & left(word(desc,j),1) <= '9' then do
            kwd = 'W'word(desc,j)                          /* found leading digit */
            leave
         end
      end
      if datatype(substr(kwd,2),'W') = 1  &,             /* second char numeric */
          pos('KW',descu) > 0 then do                    /* contains KW */
         kwd = kwd'K'                                    /* append 'K' */
      end
   end

   when key = 'BG' then do                               /* band gap */
      if word(desc,1) = 'HIGHEST' | word(desc,1) = 'LOWEST' then
         kwd = word(desc,1)
      else if word(desc,1) = 'ADJUST' then do
         if pos('-',desc) > 0 then                       /* negative voltage */
            kwd = word(desc,1)'_NEG'
         else
            kwd = word(desc,1)'_POS'
      end
      else if descu = '' then
         kwd = 'MEDIUM'val
      else
         kwd = descu
   end

   when key = 'BORPWR' then do                           /* BOR power mode */
      if pos('ZPBORMV',descu) > 0 then
         kwd = 'ZERO'
      else if pos('HIGH_POWER',descu) > 0 then
         kwd = 'HP'
      else if pos('MEDIUM_POWER',descu) > 0 then
         kwd = 'MP'
      else if pos('LOW_POWER',descu) > 0 then
         kwd = 'LP'
      else
         kwd = descu
   end

   when key = 'BROWNOUT' then do
      if  pos('SLEEP',descu) > 0 & pos('DEEP_SLEEP',descu) = 0 then
         kwd = 'RUNONLY'
      else if pos('HARDWARE_ONLY',descu) > 0 then do
         kwd = 'ENABLED'
      end
      else if pos('CONTROL',descu) > 0 then
         kwd = 'CONTROL'
      else if pos('ENABLED',descu) > 0 | descu = 'ON' then
         kwd = 'ENABLED'
      else do
         kwd = 'DISABLED'
      end
   end

   when key = 'CANMUX' then do
      if pos('_RB', descu) > 0 then
         kwd = 'pin_'substr(descu, pos('_RB', descu) + 2, 2)
      else if pos('_RC', descu) > 0 then
         kwd = 'pin_'substr(descu, pos('_RC', descu) + 2, 2)
      else if pos('_RE', descu) > 0 then
         kwd = 'pin_'substr(descu, pos('_RE', descu) + 2, 2)
      else
         kwd = descu
   end

   when left(key,3) = 'CCP' & right(key,3) = 'MUX' then do /* CCPxMUX */
      if pos('MICRO',descu) > 0 then                     /* Microcontroller mode */
         kwd = 'pin_E7'                                  /* valid for all current PICs */
      else if val = 'ON'  | descu = 'ENABLED'  then
         kwd = 'ENABLED'
      else if val = 'OFF' | descu = 'DISABLED' then
         kwd = 'DISABLED'
      else
         kwd = 'pin_'right(descu,2)                      /* last 2 chars */
   end

   when key = 'CINASEL' then do
      if pos('DEFAULT',descu) > 0 then                   /* Microcontroller mode */
         kwd = 'DEFAULT'
      else
         kwd = 'MAPPED'
   end

   when key = 'CP' |,                                    /* code protection */
       ( left(key,2) = 'CP' &,
           (datatype(substr(key,3),'W') = 1 |,
            substr(key,3,1) = 'D'           |,
            substr(key,3,1) = 'B') )       then do
      if val = 'OFF' | pos('NOT',desc) > 0 | pos('DISABLED',desc) > 0  |  pos('OFF',desc) > 0 then
         kwd = 'DISABLED'
      else if left(val,5) = 'UPPER' | left(val,5) = 'LOWER'  | val = 'HALF' then
         kwd = val
      else if pos('ALL_PROT', descu) > 0 then            /* all protected */
         kwd = 'ENABLED'
      else if left(desc,1) = '0' then do                 /* probably a range */
         kwd = word(desc,1)                              /* begin(-end) of range */
         if word(desc,2) = 'TO' then                     /* splitted words */
            kwd = kwd'-'word(desc,3)                     /* add end of range */
         kwd = 'R'translate(kwd,'_','-')                 /* format */
      end
      else
         kwd = 'ENABLED'
   end

   when key = 'CPUDIV' then do
      if word(desc,1) = 'NO' then
         kwd = 'P1'                                      /* no division */
      else if pos('DIVIDE',desc) > 0 & wordpos('BY',desc) > 0 then
         kwd = 'P'word(desc,words(desc))                 /* last word */
      else if pos('DIVIDE',desc) > 0 & wordpos('(NO',desc) > 0 then
         kwd = 'P'1                                      /* no divide */
      else if pos('/',desc) > 0 then
         kwd = 'P'substr(desc,pos('/',desc)+1,1)         /* digit after '/' */
      else
         kwd = descu
   end

   when key = 'DSBITEN' then do
      if val = 'ON' then
         kwd = 'ENABLED'
      else
         kwd = 'DISABLED'
   end

   when key = 'DSWDTOSC' then do
      if pos('INT',descu) > 0 then
         kwd = 'INTOSC'
      else if pos('LPRC',descu) > 0 then
         kwd = 'LPRC'
      else if pos('SOSC',descu) > 0 then
         kwd = 'SOSC'
      else
         kwd = 'T1'
   end

   when key = 'DSWDTPS'   |,
        key = 'WDTPS' then do
      parse var desc p0 ':' p1                           /* split */
      kwd = translate(word(p1,1),'      ','.,()=/')      /* 1st word, cleaned */
      kwd = space(kwd,0)                                 /* remove all spaces */
      do j=1 while kwd >= 1024
         kwd = kwd / 1024                                /* reduce to K, M, G, T */
      end
      kwd = 'P'format(kwd,,0)||substr(' KMGT',j,1)
   end

   when key = 'EBTR' |,
        left(key,4) = 'EBTR'  &,
           (datatype(substr(key,5),'W') = 1 |,
            substr(key,5,1) = 'B')       then do
      if val = 'OFF' then
         kwd = 'DISABLED'                                /* not protected */
      else
         kwd = 'ENABLED'
   end

   when key = 'ECCPMUX' then do
      if pos('_R',descu) > 0 then                       /* check for _R<pin> */
         kwd = 'pin_'substr(descu,pos('_R',descu)+2,2)  /* 2 chars after '_R' */
      else
         kwd = descu
   end

   when key = 'EMB' then do
      if pos('12',desc) > 0 then                        /* 12-bit mode */
         kwd = 'B12'
      else if pos('16',desc) > 0 then                   /* 16-bit mode */
         kwd = 'B16'
      else if pos('20',desc) > 0 then                   /* 20-bit mode */
         kwd = 'B20'
      else
         kwd = 'DISABLED'                               /* no en/disable balancing */
   end

   when key = 'ETHLED' then do
      if val = 'ON' | pos('ENABLED',desc) > 0  then     /* LED enabled */
         kwd = 'ENABLED'
      else
         kwd = 'DISABLED'
   end

   when key = 'EXCLKMUX' then do                         /* Timer0/5 clock pin */
      if pos('_R',descu) > 0 then                       /* check for _R<pin> */
         kwd = 'pin_'substr(descu,pos('_R',descu)+2,2)  /* 2 chars after '_R' */
      else
         kwd = descu
   end

   when key = 'FLTAMUX' then do
      if pos('_R',descu) > 0 then                       /* check for _R<pin> */
         kwd = 'pin_'substr(descu,pos('_R',descu)+2,2)  /* 2 chars after '_R' */
      else
         kwd = descu
   end

   when key = 'FOSC2' then do
      if pos('INTRC', descu) > 0  |,
         desc = 'ENABLED' then
         kwd = 'INTOSC'
      else
         kwd = 'OSC'
   end

   when key = 'FCMEN'  |,                                /* Fail safe clock monitor */
        key = 'FSCKM' then do
      x1 = pos('ENABLED', descu)
      x2 = pos('DISABLED', descu)
      if x1 > 0 & x2 > 0 & x2 > x1 then
         kwd  = 'SWITCHING'
      else if x1 > 0 & x2 = 0 then
         kwd  = 'ENABLED'
      else if x1 = 0 & x2 > 0 then
         kwd  = 'DISABLED'
      else
         kwd = descu
   end

   when key = 'HFOFST' then do
      if val = 'ON' | pos('NOT_DELAYED',descu) > 0 then
         kwd = 'ENABLED'
      else
         kwd = 'DISABLED'
   end

   when key = 'INTOSCSEL' then do
      if pos('HIGH_POWER',descu) > 0 then
         kwd = 'HP'
      else if pos('LOW_POWER',descu) > 0 then
         kwd = 'LP'
      else
         kwd = descu
   end

   when key = 'IOL1WAY' then do
      if val = 'ON' then
         kwd = 'ENABLED'
      else
         kwd = 'DISABLED'
   end

   when key = 'IOSCFS' then do
      if pos('MHZ',descu) > 0 then do
         if pos('8',descu) > 0 then                       /* 8 MHz */
            kwd = 'F8MHZ'
         else
            kwd = 'F4MHZ'                                /* otherwise */
      end
      else if descu = 'ENABLED' then
         kwd = 'F8MHZ'
      else if descu = 'DISABLED' then
         kwd = 'F4MHZ'                                   /* otherwise */
      else do
         kwd = descu
         if left(kwd,1) >= '0' & left(kwd,1) <= '9' then
            kwd = 'F'kwd                                 /* prefix when numeric */
      end
   end

   when key = 'LPT1OSC' then do
      if pos('LOW',descu) > 0 | pos('ENABLE',descu) > 0 then
         kwd = 'LOW_POWER'
      else
         kwd = 'HIGH_POWER'
   end

   when key = 'LS48MHZ' then do
      if pos('TO_4',descu) > 0 then
         kwd = 'P4'
      else if pos('TO_8',descu) > 0 then
         kwd = 'P8'
      else if pos('BY_2',descu) > 0 then
         kwd = 'P2'
      else if pos('BY_1',descu) > 0 then
         kwd = 'P1'
      else
         kwd = descu
   end

   when key = 'LVP' then do
      if pos('ENABLE',desc) > 0 then
         kwd = 'ENABLED'
      else
         kwd = 'DISABLED'
   end

   when key = 'MCLR' then do
      if val = 'OFF' then
         kwd = 'INTERNAL'
      else if val = 'ON'                  |,
         pos('EXTERN',desc) > 0           |,
         pos('MCLR ENABLED',desc) > 0     |,
         pos('MCLR PIN ENABLED',desc) > 0 |,
         pos('MASTER',desc) > 0           |,
         pos('AS MCLR',desc) > 0          |,
         pos('IS MCLR',desc) > 0          |,
         desc = 'MCLR'                    |,
         desc = 'ENABLED'   then
         kwd = 'EXTERNAL'
      else
         kwd = 'INTERNAL'
   end

   when key = 'MSSPMASK'  |,
        key = 'MSSPMSK1'  |,
        key = 'MSSPMSK2' then do
      if left(desc,1) >= 0  &  left(desc,1) <= '9' then
         kwd = 'B'left(desc, 1)                          /* digit 5 or 7 expected */
      else
         kwd = descu
   end

   when key = 'OSC' then do
      kwd = Fuse_Def.Osc.descu
      if kwd = '?' then do
         call msg 2, 'No mapping for fuse_def' key':' descu
      end
      else if descu = 'INTOSC'  & ,
             (PicName = '16f913' | PicName = '16f914'|,
              PicName = '16f916' | PicName = '16f917') then do /* exception */
         kwd = 'INTOSC_CLKOUT'                           /* correction of map: NOCLKOUT */
      end
   end

   when key = 'P2BMUX' then do
      if substr(descu,length(descu)-3,2) = '_R' then     /* check for _R<pin> */
         kwd = 'pin_'right(descu,2)
      else
         kwd = descu
   end

   when key = 'PBADEN' then do
      if pos('ANALOG',descu) > 0  |  desc = 'ENABLED' then
         kwd = 'ANALOG'
      else
         kwd = 'DIGITAL'
   end

   when key = 'PCLKEN' then do
      if val = 'ON' then
         kwd = 'ENABLED'
      else
         kwd = 'DISABLED'
   end

   when key = 'PLLDIV' then do
      if descu = 'RESERVED' then
         kwd = '   '                                     /* to be ignored */
      else if left(descu,6) = 'NO_PLL' then
         kwd = 'P0'                                      /* no PLL */
      else if right(word(desc,1),1) = 'X' then
         kwd = 'X'||strip(word(desc,1),'T','X')          /* multiplier */
      else if left(descu,9) = 'DIVIDE_BY' then
         kwd = 'P'||word(desc,3)                         /* 3rd word */
      else if wordpos('DIVIDED BY', desc) > 0 then
         kwd = 'P'||word(desc, wordpos('DIVIDED BY', desc) + 2)    /* word after 'devided by' */
      else if word(desc,1) = 'NO' |,
              pos('NO_DIVIDE', descu) > 0 then
         kwd = 'P1'
      else
         kwd = descu
   end

   when key = 'PLLEN' then do
      if pos('MULTIPL',desc) > 0 then
         kwd = 'P'word(desc, words(desc))                /* last word */
      else if pos('500 KHZ',desc) > 0  |  pos('500KHZ',desc) > 0 then
         kwd = 'F500KHZ'
      else if pos('16 MHZ',desc) > 0  |  pos('16MHZ',desc) > 0 then
         kwd = 'F16MHZ'
      else if pos('DIRECT',desc) > 0 | pos('DISABLED',desc) > 0 | pos('SOFTWARE',desc) > 0 then
         kwd = 'P1'
      else if pos('ENABLED',desc) > 0 then
         kwd = 'P4'
      else if datatype(left(desc,1),'W') = 1 then
         kwd = 'F'descu
      else
         kwd = descu
   end

   when key = 'PMODE' then do
      if pos('EXT',desc) > 0 then do
         if pos('-BIT', desc) > 0 then
            kwd = 'B'substr(desc, pos('-BIT',desc)-2, 2) /* # bits */
         else
            kwd = 'EXT'
      end
      else if pos('PROCESSOR',desc) > 0 then do
         kwd = 'MICROPROCESSOR'
         if pos('BOOT',descu) > 0 then
            kwd = kwd'_BOOT'
      end
      else
         kwd = 'MICROCONTROLLER'
   end

   when key = 'PMPMUX' then do
      if wordpos('ON',desc) > 0 then                     /* contains ' ON ' */
         kwd = left(word(desc, wordpos('ON',desc) + 1),5)
      else if wordpos('ELSEWHERE',desc) > 0  |,          /* contains ' ELSEWHERE ' */
              wordpos(' NOT ',desc) > 0 then             /* contains ' NOT ' */
         kwd = 'ELSEWHERE'
      else if wordpos('NOT',desc) = 0 then               /* does not contain ' NOT ' */
         kwd = left(word(desc, wordpos('TO',desc) + 1),5)
      else
         kwd = descu
   end

   when key = 'POSCMD' then do                           /* primary osc */
      if pos('DISABLED',descu) > 0 then                  /* check for _R<pin> */
         kwd = 'DISABLED'
      else if pos('HS', descu) > 0 then
         kwd = 'HS'
      else if pos('MS', descu) > 0 then
         kwd = 'MS'
      else if pos('EXTERNAL', descu) > 0 then
         kwd = 'EC'
      else
         kwd = descu
   end

   when key = 'PWM4MUX' then do
      if pos('_R',descu) > 0 then                       /* check for _R<pin> */
         kwd = 'pin_'substr(descu,pos('_R',descu)+2,2)  /* 2 chars after '_R' */
      else
         kwd = descu
   end

   when key = 'RETEN' then do
      if val = 'OFF' then
         kwd = 'DISABLED'
      else
         kwd = 'ENABLED'
   end

   when key = 'RTCOSC' then do
      if pos('INTRC',descu) > 0 then
         kwd = 'INTRC'
      else
         kwd = 'T1OSC'
   end

   when key = 'SIGN' then do
      if pos('CONDUC',descu) > 0 then
         kwd = 'NOT_CONDUCATED'
      else
         kwd = 'AREA_COMPLETE'
   end

   when key = 'SOSCSEL' then do
      if val = 'HIGH' | pos('HIGH_POWER',descu) > 0 then
         kwd = 'HP'
      else if val = 'DIG' | pos('DIGITAL',descu) then
         kwd = 'DIG'
      else if val = 'LOW' | pos('LOW_POWER',descu) > 0 then
         kwd = 'LP'
      else if pos('SECURITY',descu) > 0 then
         kwd = 'HS_CP'
      else
         kwd = descu
   end

   when key = 'SSPMUX' then do
      offset1 = pos('_MULTIPLEX',descu)
      if offset1 > 0 then do                             /* 'multiplexed' found */
         offset2 = pos('_R',substr(descu,offset1))       /* first pin */
         if offset2 > 0 then
            kwd = 'pin_'substr(descu,offset1+offset2+1,2)
         else
            kwd = 'ENABLED'
      end
      else
         kwd = 'DISABLED'                                /* no en/disable balancing */
   end

   when key = 'STVR' then do
      if pos('NOT', desc) > 0 | pos('DISABLED',desc) > 0 then   /* no stack overflow */
         kwd = 'DISABLED'
      else
         kwd = 'ENABLED'
   end

   when key = 'T0CKMUX' then do
      if pos('_RB', descu) > 0 then
         kwd = 'pin_'substr(descu, pos('_RB', descu) + 2, 2)
      else if pos('_RG', descu) > 0 then
         kwd = 'pin_'substr(descu, pos('_RG', descu) + 2, 2)
      else
         kwd = descu
   end

   when key = 'T1OSCMUX' then do
      if left(right(descu,4),2) = '_R' then
         kwd = 'pin_'right(descu,2)                      /* last 2 chars */
      else if val = 'ON' then
         kwd = 'LP'
      else if val = 'OFF' then
         kwd = 'STANDARD'
      else
         kwd = descu
   end

   when key = 'T1DIG' then do
      if val = 'ON' then
         kwd = 'ENABLED'
      else if val = 'OFF' then
         kwd = 'DISABLED'
      else
         kwd = descu
   end

   when key = 'T3CKMUX' then do
      if pos('_RB', descu) > 0 then
         kwd = 'pin_'substr(descu, pos('_RB', descu) + 2, 2)
      else if pos('_RG', descu) > 0 then
         kwd = 'pin_'substr(descu, pos('_RG', descu) + 2, 2)
      else
         kwd = descu
   end

   when key = 'T3CMUX' then do
      if pos('_R',descu) > 0 then                        /* check for _R<pin> */
         kwd = 'pin_'substr(descu,pos('_R',descu)+2,2)   /* 2 chars after '_R' */
      else
         kwd = descu
   end

   when key = 'T5GSEL' then do
      if pos('T3G',descu) > 0 then
         kwd = 'T3G'
      else
         kwd = 'T5G'
   end

   when key = 'USBDIV' then do                           /* mplab >= 8.60 (was USBPLL) */
      if descu = 'ENABLED' | pos('96_MH',descu) > 0 | pos('DIVIDED_BY',descu) > 0 then
         kwd = 'P4'                                  /* compatibility */
      else
         kwd = 'P1'                                      /* compatibility */
   end

   when key = 'USBLSCLK' then do
      if pos('48',descu) > 0 then
         kwd = 'F48MHZ'
      else
         kwd = 'F24MHZ'
   end

   when key = 'USBPLL' then do
      if pos('PLL',descu) > 0 then
         kwd = 'F48MHZ'
      else
         kwd = 'OSC'
   end

   when key = 'VCAPEN' then do
      if pos('DISABLED',desc) > 0 then
         kwd = 'DISABLED'
      else if pos('ENABLED_ON',descu) > 0 then do
         x = wordpos('ON',desc)
         kwd = word(desc, x + 1)                         /* last word */
         if left(kwd,1) = 'R' then                       /* pinname Rxy */
            kwd = 'pin_'substr(kwd,2)                    /* make it pin_xy */
         else
            kwd = 'ENABLED'
      end
      else
         kwd = 'ENABLED'                                 /* probably never reached */
   end

   when key = 'VOLTAGE' then do
      do j=1 to words(desc)                              /* scan word by word */
         if left(word(desc,j),1) >= '0' & left(word(desc,j),1) <= '9' then do
            if pos('.',word(desc,j)) > 0 then do         /* select digits */
               kwd = 'V'left(word(desc,j),1,1)||substr(word(desc,j),3,1)
               if kwd = 'V21' then
                  kwd = 'V20'                            /* compatibility */
               leave                                     /* done */
            end
         end
      end
      if j > words(desc) then do                        /* no voltage value found */
         if pos('MINIMUM',desc) > 0  |,
            pos(' LOW ',desc) > 0 then
            kwd = 'MINIMUM'
         else if pos('MAXIMUM',desc) > 0 |,
            pos(' HIGH ',desc) > 0 then
            kwd = 'MAXIMUM'
         else if descu = '' then
            kwd = 'MEDIUM'val
         else
            kwd = descu
      end
   end

   when key = 'WAIT' then do
      if val = 'OFF' | pos('NOT',desc) > 0 | pos('DISABLE',desc) > 0 then
         kwd = 'DISABLED'
      else
         kwd = 'ENABLED'
   end

   when key = 'WDT' then do                              /* Watchdog */
      pos_en = pos('ENABLE', desc)
      pos_dis = pos('DISABLE', desc)
      if pos('RUNNING', desc) > 0 |,
         pos('DISABLED_IN_SLEEP', descu) > 0 then
         kwd = 'RUNONLY'
      else if descu = 'OFF' | (pos_dis > 0 & (pos_en = 0 | pos_en > pos_dis)) then do
         kwd = 'DISABLED'
      end
      else if pos('HARDWARE', desc) > 0 then do
         kwd = 'HARDWARE'
      end
      else if pos('CONTROL', desc) > 0  then do
         if core = '16' then                             /* can only be en- or dis-abled */
            kwd = 'DISABLED'                             /* all 18Fs */
         else
            kwd = 'CONTROL'
      end
      else if descu = 'ON' | (pos_en > 0 & (pos_dis = 0 | pos_dis > pos_en)) then do
         kwd = 'ENABLED'
      end
      else
         kwd = descu                                     /* normalized description */
   end

   when key = 'WDTCLK' then do
      if pos('ALWAYS',descu) > 0 then do
         if pos('INTOSC', descu) > 0 then
             kwd = 'INTOSC'
         else
             kwd = 'SOCS'
      end
      else if pos('FRC',descu) > 0 then
         kwd = 'FRC'
      else if pos('FOSC_4',descu) > 0 then
         kwd = 'FOSC'
      else
         kwd = descu
   end

   when key = 'WDTCS' then do
      if pos('LOW',descu) > 0 then
         kwd = 'LOW_POWER'
      else
         kwd = 'STANDARD'
   end

   when key = 'WDTWIN' then do
      x = pos('WIDTH_IS', descu)
      if x > 0 then
         kwd = 'P'substr(descu, x + 9, 2)                 /* percentage */
      else
         kwd = descu
   end

   when key = 'WPCFG' then do
      if val = 'ON' | val = 'WPCFGEN' then
         kwd = 'ENABLED'
      else
         kwd = 'DISABLED'
   end

   when key = 'WPDIS' then do
      if val = 'ON' | val = 'WPEN' then
         kwd = 'ENABLED'
      else
         kwd = 'DISABLED'
   end

   when key = 'WPEND' then do
      if pos('PAGES_0', descu) > 0  | pos('PAGE_0', descu) > 0  then
         kwd = 'P0_WPFP'
      else
         kwd = 'PWPFP_END'
   end

   when key = 'WPFP' then do
      kwd = 'P'word(desc, words(desc))                   /* last word */
   end

   when key = 'WPSA' then do
      x = pos(':', desc)                                 /* fraction */
      if x > 0 then
         kwd = 'P'substr(desc, x + 1)                    /* divisor */
      else
         kwd = descu
   end

   when key = 'WRT'  |,
      ( left(key,3) = 'WRT'  &,
           (datatype(substr(key,4),'W') = 1 |,
            substr(key,4,1) = 'B'           |,
            substr(key,4,1) = 'C'           |,
            substr(key,4,1) = 'D') )     then do
      if pos('NOT',desc) > 0  |  val = 'OFF' then
         kwd = 'DISABLED'                                /* not protected */
      else if val = 'BOOT' then
         kwd = 'BOOT_BLOCK'                              /* boot block protected */
      else if val = 'HALF' then
         kwd = 'HALF'                                    /* 1/2 of memory protected */
      else if val = 'FOURTH' | val = '1FOURTH' then
         kwd = 'FOURTH'                                  /* 1/4 of memory protected */
      else if datatype(val) = 'NUM' then
         kwd = 'W'val                                    /* number of words */
      else
         kwd = 'ENABLED'                                 /* whole memory protected */
   end

   when key = 'WURE' then do
      if val = 'ON' then
         kwd = 'CONTINUE'
      else
         kwd = 'RESET'
   end

otherwise                                                /* generic formatting */
   if val = 'OFF' | val = 'DISABLED' then
      kwd = 'DISABLED'
   else if val = 'ON' | val = 'DISABLED' then
      kwd = 'ENABLED'
   else if pos('ACTIVE',desc) > 0 then do
      if pos('HIGH',desc) > pos('ACTIVE',desc) then
         kwd = 'ACTIVE_HIGH'
      else if pos('LOW',desc) > pos('ACTIVE',desc) then
         kwd = 'ACTIVE_LOW'
      else do
         kwd = 'ENABLED'
      end
   end
   else if pos('ENABLE',desc) > 0 | desc = 'ON' | desc = 'ALL' then do
      kwd = 'ENABLED'
   end
   else if pos('DISABLE',desc) > 0 | desc = 'OFF' | pos('SOFTWARE',desc) > 0 then do
      kwd = 'DISABLED'
   end
   else if pos('ANALOG',desc) > 0 then
      kwd = 'ANALOG'
   else if pos('DIGITAL',desc) > 0 then
      kwd = 'DIGITAL'
   else do
      if left(desc,1) >= '0' & left(desc,1) <= '9' then do /* starts with digit */
         if pos('HZ',desc) > 0  then                     /* probably frequency (range) */
            kwd = 'F'word(desc,1)                        /* 'F' prefix */
         else if pos(' TO ',desc) > 0  |,                /* probably a range */
                 pos('0 ',  desc) > 0  |,
                 pos(' 0',  desc) > 0  |,
                 pos('H-',  desc) > 0  then do
            if pos(' TO ',desc) > 0  then do
               kwd = delword(desc,4)                     /* keep 1st three words */
               kwd = delword(kwd,2,1)                    /* keep only 'from' and 'to' */
               kwd = translate(kwd, ' ','H')             /* replace 'H' by space */
               kwd = space(kwd,1,'_')                    /* single underscore */
            end
            else
               kwd = word(desc,1)                        /* keep 1st word */
            kwd = 'R'translate(kwd,'_','-')              /* 'R' prefix, hyphen->underscore */
         end
         else do                                         /* probably a number */
            kwd = 'N'word(desc,1)                        /* 1st word, 'N' prefix */
         end
      end
      else
         kwd = descu                                     /* if no alternative! */
   end
end

if kwd = '   ' then                                      /* special ('...') */
   nop                                                   /* ignore */
else if kwd = '' then                                    /* empty keyword */
   call msg 3, 'No keyword found for fuse_def' key '('desc')'
else if length(kwd) > 22  then
   call msg 2, 'fuse_def' key 'keyword excessively long: "'kwd'"'

return kwd


/* ----------------------------------------------------------------------------- *
 * Generate functions w.r.t. analog modules.                                     *
 * First individual procedures for different analog modules                      *
 * to put the  corresponding pins in digital-I/O mode,                           *
 * then the procedure 'enable_digital_io()' which invokes these procedures       *
 * as far as present in this device file.                                        *
 *                                                                               *
 * Possible combinations for the different PICS:                                 *
 * ANSEL   [ANSELH]                                                              *
 * ANSEL0  [ANSEL1]                                                              *
 * ANSELA  [ANSELB  ANSELC  ANSELD  ANSELE  ANSELF  ANSELG]                      *
 * ANCON0  [ANCON1  ANCON2  ANCON3]                                              *
 * ADCON0  [ADCON1  ADCON2  ADCON3]                                              *
 * CMCON                                                                         *
 * CMCON0  [CMCON1]                                                              *
 * CM1CON  [CM2CON]                                                              *
 * CM1CON0 [CM1CON1  CM2CON0 CM2CON1 CM3CON0 CM3CON1]                            *
 * CM1CON1 [CM2CON1]                                                             *
 * Between brackets not always present.                                          *
 * - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - *
 * PICs are classified in groups for ADC module settings.                        *
 * Below the register settings for all-digital I/O:                              *
 * ADC_V0    ADCON0 = 0b0000_0000 [ADCON1 = 0b0000_0000]                         *
 *           ANSEL0 = 0b0000_0000  ANSEL1 = 0b0000_0000  (or ANSEL_/H,A/B/D/E)   *
 * ADC_V1    ADCON0 = 0b0000_0000  ADCON1 = 0b0000_0111                          *
 * ADC_V2    ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111                          *
 * ADC_V3    ADCON0 = 0b0000_0000  ADCON1 = 0b0111_1111                          *
 * ADC_V4    ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111                          *
 * ADC_V5    ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111                          *
 * ADC_V6    ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111                          *
 * ADC_V7    ADCON0 = 0b0000_0000  ADCON1 = 0b0000_0000  ADCON2 = 0b0000_0000    *
 *           ANSEL0 = 0b0000_0000  ANSEL1 = 0b0000_0000                          *
 * ADC_V7_1  ADCON0 = 0b0000_0000  ADCON1 = 0b0000_0000  ADCON2 = 0b0000_0000    *
 *           ANSEL  = 0b0000_0000 [ANSELH = 0b0000_0000]                         *
 * ADC_V8    ADCON0 = 0b0000_0000  ADCON1 = 0b0000_0000  ADCON2 = 0b0000_0000    *
 *           ANSEL  = 0b0000_0000  ANSELH = 0b0000_0000                          *
 * ADC_V9    ADCON0 = 0b0000_0000  ADCON1 = 0b0000_0000                          *
 *           ANCON0 = 0b1111_1111  ANCON1 = 0b1111_1111                          *
 * ADC_V10   ADCON0 = 0b0000_0000  ADCON1 = 0b0000_0000                          *
 *           ANSEL  = 0b0000_0000  ANSELH = 0b0000_0000                          *
 * ADC_V11   ADCON0 = 0b0000_0000  ADCON1 = 0b0000_0000                          *
 *           ANCON0 = 0b1111_1111  ANCON1 = 0b1111_1111                          *
 * ADC_V11_1 ADCON0 = 0b0000_0000  ADCON1 = 0b0000_0000                          *
 *           ANCON0 = 0b1111_1111  ANCON1 = 0b1111_1111                          *
 * ADC_V12   ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111  ADCON2 = 0b0000_0000    *
 * ADC_V13   ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111  ADCON2 = 0b0000_0000    *
 * ADC_V13_1 ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111  ADCON2 = 0b0000_0000    *
 * ADC_V13_2 ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111  ADCON2 = 0b0000_0000    *
 * ADC_V14   ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111  ADCON2 = 0b0000_0000    *
 * ADC_V14_1 ADCON0 = 0b0000_0000  ADCON1 = 0b0000_1111  ADCON2 = 0b0000_0000    *
 * ----------------------------------------------------------------------------- */
list_analog_functions: procedure expose jalfile Name. Core DevSpec. PinMap. ,
                                        ADCS_bits ADC_highres PicName msglevel
call lineout jalfile, '--'
call lineout jalfile, '-- ==================================================='
call lineout jalfile, '--'
call lineout jalfile, '-- Special (device specific) constants and procedures'
call lineout jalfile, '--'
PicNameCaps = toupper(PicName)
if DevSpec.PicNameCaps.ADCgroup = '?' then do               /* no ADC group specified */
   if (Name.ADCON \= '-' | Name.ADCON0 \= '-' | Name.ADCON1 \= '-') then do
      call msg 3, 'PIC has ADCONx register, but no ADCgroup found in devicespecific.json!'
   end
   ADC_group = '0'                                          /* no ADC module */
   ADC_res = '0'                                            /* # bits */
end
else do                                                     /* ADC group specified */
   ADC_group = DevSpec.PicNameCaps.ADCgroup
   if DevSpec.PicNameCaps.ADCMAXRESOLUTION = '?' then do    /* # bits not specified */
      if ADC_highres = 0  &  Core < 16  then                /* base/mid range without ADRESH */
         ADC_res = '8'
      else
         ADC_res = '10'                                     /* default max res */
   end
   else
      ADC_res = DevSpec.PicNameCaps.ADCMAXRESOLUTION        /* specified ADC bits */
end

if  PinMap.PicNameCaps.ANCOUNT = '?' |,                     /* PIC not in pinmap.cmd? */
    ADC_group = '0'  then                                   /* PIC has no ADC module */
   PinMap.PicNameCaps.ANCOUNT = 0
call charout jalfile, 'const      ADC_GROUP          =' ADC_group
if ADC_group = '0' then
   call charout jalfile, '        -- no ADC module present'
call lineout jalfile, ''
call lineout jalfile, 'const byte ADC_NTOTAL_CHANNEL =' PinMap.PicNameCaps.ANCOUNT
call lineout jalfile, 'const byte ADC_ADCS_BITCOUNT  =' ADCS_bits
call lineout jalfile, 'const byte ADC_MAX_RESOLUTION =' ADC_res
call lineout jalfile, '--'

if DevSpec.PicNameCaps.PPSgroup = '?' then
   call lineout jalfile, 'const PPS_GROUP  = PPS_0        -- no Peripheral Pin Selection'
else
   call lineout jalfile, 'const PPS_GROUP  = 'DevSpec.PicNameCaps.PPSgroup,
                         '       -- PPS group' right(DevSpec.PicNameCaps.PPSgroup,1)
call lineout jalfile, '--'

if Name.UCON \= '-' then do                                 /* USB module present */
   if DevSpec.PicNameCaps.USBBDT \= '?' then
      call lineout jalfile, 'const word USB_BDT_ADDRESS    = 0x'DevSpec.PicNameCaps.USBBDT
   else
      call msg 2, PicName 'has USB module but USB_BDT_ADDRESS not specified'
   call lineout jalfile, '--'
end

if (ADC_group = '0'  & PinMap.PicNameCaps.ANCOUNT > 0) |,
   (ADC_group \= '0' & PinMap.PicNameCaps.ANCOUNT = 0) then do
   call msg 2, 'Possible conflict between ADC-group ('ADC_group')',
          'and number of ADC channels ('PinMap.PicNameCaps.ANCOUNT')'
end
analog. = '-'                                               /* no analog modules */

if Name.ANSEL  \= '-' |,                                    /*                       */
   Name.ANSEL1 \= '-' |,                                    /*                       */
   Name.ANSELA \= '-' |,                                    /* any of these declared */
   Name.ANSELC \= '-' |,                                    /*                       */
   Name.ANCON0 \= '-' |,                                    /*                       */
   Name.ANCON1 \= '-' then do                               /*                       */
   analog.ANSEL = 'analog'                                  /* analog functions present */
   call lineout jalfile, '-- - - - - - - - - - - - - - - - - - - - - - - - - - -'
   call lineout jalfile, '-- Change analog I/O pins into digital I/O pins.'
   call lineout jalfile, 'procedure analog_off() is'
   call lineout jalfile, '   pragma inline'
   if Name.ANSEL \= '-' then                                /* ANSEL declared */
      call lineout jalfile, '   ANSEL  = 0b0000_0000       -- digital I/O'
   do i = 0 to 9                                            /* ANSEL0..ANSEL9 */
      qname = 'ANSEL'i                                      /* qualified name */
      if Name.qname \= '-' then                             /* ANSELi declared */
         call lineout jalfile, '   'qname '= 0b0000_0000       -- digital I/O'
   end
   suffix = XRANGE('A','Z')                                 /* suffix letters A..Z */
   do i = 1 to length(suffix)
      qname = 'ANSEL'substr(suffix,i,1)                     /* qualified name */
      if Name.qname \= '-' then                             /* ANSELx declared */
         call lineout jalfile, '   'qname '= 0b0000_0000        -- digital I/O'
   end
   do i = 0 to 9                                            /* ANCON0..ANCON9 */
      qname = 'ANCON'i                                      /* qualified name */
      if Name.qname \= '-' then do                          /* ANCONi declared */
         do j = (8 * i) to (8 * 1 + 7)                      /* all PCFG bits */
            bitname = qname'_PCFG'j
            if Name.bitname \= '-' then do                  /* ANCON has a PCFG bit */
               call lineout jalfile, '   'qname '= 0b1111_1111     -- digital I/O'
               leave
            end
         end
         if Name.bitname = '-' then do                      /* ANCON has no  PCFG bit */
            do j = (8 * i) to (8 * i + 7)                   /* try ANSEL bits */
               bitname = qname'_ANSEL'j                     /* ANSEL bit */
               if Name.bitname \= '-' then do               /* ANCONi has ANSEL bit(s) */
                  call lineout jalfile, '   'qname '= 0b0000_0000        -- digital I/O'
                  leave
               end
            end
         end
      end
   end
   call lineout jalfile, 'end procedure'
   call lineout jalfile, '--'
end

if Name.ADCON0 \= '-' |,                                    /* check on presence */
   Name.ADCON  \= '-' then do
   analog.ADC = 'adc'                                       /* ADC module present */
   call lineout jalfile, '-- - - - - - - - - - - - - - - - - - - - - - - - - - -'
   call lineout jalfile, '-- Disable ADC module'
   call lineout jalfile, 'procedure adc_off() is'
   call lineout jalfile, '   pragma inline'
   if Name.ADCON0 \= '-' then
      call lineout jalfile, '   ADCON0 = 0b0000_0000         -- disable ADC'
   else
      call lineout jalfile, '   ADCON  = 0b0000_0000         -- disable ADC'
   if Name.ADCON1 \= '-' then do                            /* ADCON1 declared */
      if ADC_group = 'ADC_V1' then
         call lineout jalfile, '   ADCON1 = 0b0000_0111         -- digital I/O'
      else if ADC_group = 'ADC_V2'     |,
              ADC_group = 'ADC_V4'     |,
              ADC_group = 'ADC_V5'     |,
              ADC_group = 'ADC_V6'     |,
              ADC_group = 'ADC_V12'    then
         call lineout jalfile, '   ADCON1 = 0b0000_1111'
      else if ADC_group = 'ADC_V3' then
         call lineout jalfile, '   ADCON1 = 0b0111_1111'
      else do                                               /* all other ADC groups */
         call lineout jalfile, '   ADCON1 = 0b0000_0000'
         if Name.ADCON1_PCFG \= '-' then
            call msg 2, 'ADCON1_PCFG field present: PIC maybe in wrong ADC_GROUP'
      end
      if Name.ADCON2 \= '-' then                            /* ADCON2 declared */
         call lineout jalfile, '   ADCON2 = 0b0000_0000'    /* all groups */
   end
   call lineout jalfile, 'end procedure'
   call lineout jalfile, '--'
end

if Name.CMCON   \= '-' |,
   Name.CMCON0  \= '-' |,
   Name.CM1CON  \= '-' |,
   Name.CM1CON0 \= '-' |,
   Name.CM1CON1 \= '-' then do
   analog.CMCON = 'comparator'                              /* Comparator present */
   call lineout jalfile, '-- - - - - - - - - - - - - - - - - - - - - - - - - - -'
   call lineout jalfile, '-- Disable comparator module'
   call lineout jalfile, 'procedure comparator_off() is'
   call lineout jalfile, '   pragma inline'
   select
      when Name.CMCON \= '-' then
         if Name.CMCON_CM \= '-' then
            call lineout jalfile, '   CMCON  = 0b0000_0111        -- disable comparator'
         else
            call lineout jalfile, '   CMCON  = 0b0000_0000        -- disable comparator'
      when Name.CMCON0 \= '-' then do
         if Name.CMCON0_CM \= '-' then
            call lineout jalfile, '   CMCON0 = 0b0000_0111        -- disable comparator'
         else
            call lineout jalfile, '   CMCON0 = 0b0000_0000        -- disable comparator'
         if Name.CMCON1 \= '-' then
            call lineout jalfile, '   CMCON1 = 0b0000_0000'
      end
      when Name.CM1CON \= '-' then do
         if Name.CM1CON_CM \= '-' then
            call lineout jalfile, '   CM1CON = 0b0000_0111        -- disable comparator'
         else
            call lineout jalfile, '   CM1CON = 0b0000_0000        -- disable comparator'
         if Name.CM2CON \= '-' then
            call lineout jalfile, '   CM2CON = 0b0000_0000        -- digital I/O'
         if Name.CM3CON \= '-' then
            call lineout jalfile, '   CM3CON = 0b0000_0000'
      end
      when Name.CM1CON0 \= '-' then do
         call lineout jalfile, '   CM1CON0 = 0b0000_0000       -- disable comparator'
         if Name.CM1CON1 \= '-' then
            call lineout jalfile, '   CM1CON1 = 0b0000_0000'
         if Name.CM2CON0 \= '-' then do
            call lineout jalfile, '   CM2CON0 = 0b0000_0000       -- disable 2nd comparator'
            if Name.CM2CON1 \= '-' then
               call lineout jalfile, '   CM2CON1 = 0b0000_0000'
         end
         if Name.CM3CON0 \= '-' then do
            call lineout jalfile, '   CM3CON0 = 0b0000_0000        -- disable 3rd comparator'
            if Name.CM3CON1 \= '-' then
               call lineout jalfile, '   CM3CON1 = 0b0000_0000'
         end
      end
      when Name.CM1CON1 \= '-' then do
         call lineout jalfile, '   CM1CON1 = 0b0000_0000       -- disable comparator'
         if Name.CM2CON1 \= '-' then
            call lineout jalfile, '   CM2CON1 = 0b0000_0000       -- disable 2nd comparator'
      end
   otherwise                                                /* not possible with 'if' at top */
      nop
   end
   call lineout jalfile, 'end procedure'
   call lineout jalfile, '--'
end

call lineout jalfile, '-- - - - - - - - - - - - - - - - - - - - - - - - - - -'
call lineout jalfile, '-- Switch analog ports to digital mode (if analog module present).'
call lineout jalfile, 'procedure enable_digital_io() is'
call lineout jalfile, '   pragma inline'

if analog.ANSEL \= '-' then
   call lineout jalfile, '   analog_off()'
if analog.ADC \= '-' then
   call lineout jalfile, '   adc_off()'
if analog.CMCON \= '-' then
   call lineout jalfile, '   comparator_off()'

if core = 12 then do                                        /* baseline PIC */
   call lineout jalfile, '   OPTION_REG_T0CS = OFF        -- T0CKI pin input + output'
end
call lineout jalfile, 'end procedure'
return


/* --------------------------------------------------------- */
/* Generate common header                                    */
/* shared memory for _pic_accum and _pic_isr_w is allocated  */
/* - for core 12, 14 and 14H from high to low address        */
/* - for core 16 from low to high address                    */
/* --------------------------------------------------------- */
list_head:
call lineout jalfile, '-- ==================================================='
call lineout jalfile, '-- Title: JalV2 device include file for PIC'toupper(PicName)
call list_copyright_etc jalfile
call lineout jalfile, '-- Description:'
call lineout Jalfile, '--    Device include file for pic'PicName', containing:'
call lineout jalfile, '--    - Declaration of ports and pins of the chip.'
if HasLATreg \= 0 then do                                   /* PIC has LATx register(s)  */
   call lineout jalfile, '--    - Procedures to force the use of the LATx register'
   call lineout jalfile, '--      for output when PORTx or pin_xy is addressed.'
end
else do                                                     /* for the 18F series */
   call lineout jalfile, '--    - Procedures for shadowing of ports and pins'
   call lineout jalfile, '--      to circumvent the read-modify-write problem.'
end
call lineout jalfile, '--    - Symbolic definitions for configuration bits (fuses)'
call lineout jalfile, '--    - Some device dependent procedures for common'
call lineout jalfile, '--      operations, like:'
call lineout jalfile, '--      . enable_digital_io()'
call lineout jalfile, '--'
call lineout jalfile, '-- Sources:'
call lineout jalfile, '--  - {MPLAB-X' MPlabxVersion%100'.'MPLabxVersion//100'}',
                             'crownking.edc.jar/content/edc/PIC'PicName'.PIC'
call lineout jalfile, '--'
call lineout jalfile, '-- Notes:'
call lineout jalfile, '--  - Created with Pic2Jal Rexx script version' ScriptVersion
call lineout jalfile, '--  - File creation date/time:' date('N') left(time('N'),5)
call lineout jalfile, '--'
call lineout jalfile, '-- ==================================================='
call lineout jalfile, '--'
call lineout jalfile, 'const word DEVICE_ID   = 0x'DevID
call list_devID_chipdef                                     /* special for Chipdef_jallib */
call lineout jalfile, 'const byte PICTYPE[]   = "'PicNameCaps'"'
call SysFileSearch DevSpec.PicNameCaps.DataSheet, DataSheetFile, 'sheet.'    /* search actual DS */
if sheet.0 > 0 then
   call lineout jalfile, 'const byte DATASHEET[] = "'word(sheet.1,1)'"'
if DevSpec.PicNameCaps.PgmSpec \= '-' then do
   call SysFileSearch DevSpec.PicNameCaps.PgmSpec, DataSheetFile, 'sheet.'
   if sheet.0 > 0 then
      call lineout jalfile, 'const byte PGMSPEC[]   = "'word(sheet.1,1)'"'
end
call stream DataSheetFile, 'c', 'close'                     /* not needed anymore */
call lineout jalfile, '--'
call lineout jalfile, '-- Vdd Range:' VddRange 'Nominal:' VddNominal
call lineout jalfile, '-- Vpp Range:' VppRange 'Default:' VppDefault
call lineout jalfile, '--'
call lineout jalfile, '-- ---------------------------------------------------'
call lineout jalfile, '--'
call lineout jalfile, 'include chipdef_jallib                  -- common constants'
call lineout jalfile, '--'
call lineout jalfile, 'pragma  target  cpu   PIC_'Core '           -- (banks='Numbanks')'
call lineout jalfile, 'pragma  target  chip  'PicName
call lineout jalfile, 'pragma  target  bank  0x'D2X(BankSize,4)
if core = '12' | core = '14' | core = '14H' then
  call lineout jalfile, 'pragma  target  page  0x'D2X(PageSize,4)
call lineout jalfile, 'pragma  stack   'StackDepth
if OSCCALaddr > 0 then                                      /* has OSCCAL word in high mem */
   call lineout jalfile, 'pragma  code    'CodeSize-1'                     -- (excl high mem word)'
else
   call lineout jalfile, 'pragma  code    'CodeSize
if EEspec \= '' then                                        /* any EEPROM present */
   call lineout jalfile, 'pragma  eeprom  'EESpec
if IDSpec \= '' then                                        /* PIC has ID memory */
   call lineout jalfile, 'pragma  ID      'IDSpec

drange = DevSpec.PicNameCaps.DATA
do while length(drange) > 50                                /* split large string */
   splitpoint = pos(',', drange, 49)                        /* first comma beyond 50 */
   if splitpoint = 0 then                                   /* no more commas */
      leave
   call lineout jalfile, 'pragma  data    'left(drange, splitpoint - 1)
   drange = substr(drange, splitpoint + 1)                  /* remainder */
end
call lineout jalfile, 'pragma  data    'drange              /* last or only line */

srange = DevSpec.PicNameCaps.SHARED                         /* shared GPR range */
if core = '16' then
   call lineout jalfile, 'pragma  shared  'srange',0xF'D2X(AccessBankSplitOffset)'-0xFFF'
else if core = '14H' then
   call lineout jalfile, 'pragma  shared  0x00-0x0B,'srange
else
   call lineout jalfile, 'pragma  shared  'srange

call lineout jalfile, '--'
if Core = '12'  |  Core = '14' then do
   if sharedmem.0 < 2 then                         /* not enough shared memory */
      call msg 3, 'At least 2 bytes of shared memory required! Found:' sharedmem.0
   else do
      call lineout jalfile, 'var volatile byte _pic_accum at',
                               '0x'D2X(sharedmem.2)'      -- (compiler)'
      sharedmem.2 = sharedmem.2 - 1
      call lineout jalfile, 'var volatile byte _pic_isr_w at',
                               '0x'D2X(sharedmem.2)'      -- (compiler)'
      sharedmem.2 = sharedmem.2 - 1
      sharedmem.0 = sharedmem.0 - 2                /* 2 bytes shared memory used */
   end
end
else do
   if sharedmem.0 < 1 then                         /* not enough shared memory */
      call msg 3, 'At least 1 byte of shared memory required! Found:' sharedmem.0
   else if Core = '14H' then do
      call lineout jalfile, 'var volatile byte _pic_accum at',
                               '0x'D2X(sharedmem.2)'      -- (compiler)'
      sharedmem.2 = sharedmem.2 - 1
   end
   else do
      call lineout jalfile, 'var volatile byte _pic_accum at',
                               '0x'D2X(sharedmem.1)'      -- (compiler)'
      sharedmem.1 = sharedmem.1 + 1
   end
   sharedmem.0 = sharedmem.0 - 1                   /* 1 byte shared memory used */
end
call lineout jalfile, '--'

return


/* ------------------------------------------------- */
/* List common constants in ChipDef.Jal              */
/* input:  - nothing                                 */
/* ------------------------------------------------- */
list_chipdef_header:
call lineout chipdef, '-- =================================================================='
call lineout chipdef, '-- Title: Common Jallib include file for device files'
call list_copyright_etc chipdef
call lineout chipdef, '-- Sources:'
call lineout chipdef, '--'
call lineout chipdef, '-- Description:'
call lineout chipdef, '--    Common Jallib include files for device files'
call lineout chipdef, '--'
call lineout chipdef, '-- Notes:'
call lineout chipdef, '--    - Created with Pic2Jal Rexx script version' ScriptVersion
call lineout chipdef, '--    - File creation date/time:' date('N') left(time('N'),5)
call lineout chipdef, '--'
call lineout chipdef, '-- ---------------------------------------------------'
call lineout chipdef, '--'
call lineout chipdef, '-- JalV2 compiler required constants'
call lineout chipdef, '--'
call lineout chipdef, 'const       PIC_12            = 1'
call lineout chipdef, 'const       PIC_14            = 2'
call lineout chipdef, 'const       PIC_16            = 3'
call lineout chipdef, 'const       SX_12             = 4'
call lineout chipdef, 'const       PIC_14H           = 5'
call lineout chipdef, '--'
call lineout chipdef, 'const bit   PJAL              = 1'
call lineout chipdef, '--'
call lineout chipdef, 'const byte  W                 = 0'
call lineout chipdef, 'const byte  F                 = 1'
call lineout chipdef, '--'
call lineout chipdef, 'include  constants_jallib                     -- common Jallib library constants'
call lineout chipdef, '--'
call lineout chipdef, '-- =================================================================='
call lineout chipdef, '--'
call lineout chipdef, '-- Values assigned to const "target_chip" by'
call lineout chipdef, '--    "pragma target chip" in device files'
call lineout chipdef, '-- can be used for conditional compilation, for example:'
call lineout chipdef, '--    if (target_chip == PIC_16F88) then'
call lineout chipdef, '--      ....                                  -- for 16F88 only'
call lineout chipdef, '--    endif'
call lineout chipdef, '--'
return


/* ------------------------------------------------- */
/* Add copyright, etc to header in all created files */
/* input: filespec of destination file               */
/* returns: nothing                                  */
/* ------------------------------------------------- */
list_copyright_etc:
parse arg listfile .
call lineout listfile, '--'
call lineout listfile, '-- Author:' ScriptAuthor', Copyright (c) 2008..2013,',
                       'all rights reserved.'
call lineout listfile, '--'
call lineout listfile, '-- Adapted-by:'
call lineout listfile, '--'
call lineout listfile, '-- Revision: $Revision$'
call lineout listfile, '--'
call lineout listfile, '-- Compiler:' CompilerVersion
call lineout listfile, '--'
call lineout listfile, '-- This file is part of jallib',
                       ' (http://jallib.googlecode.com)'
call lineout listfile, '-- Released under the ZLIB license',
                       ' (http://www.opensource.org/licenses/zlib-license.html)'
call lineout listfile, '--'
return


/* --------------------------------------------------- */
/* Read file with Device Specific data                 */
/* Interpret contents: fill compound variable DevSpec. */
/* (simplyfied implementation of reading a JSON file)  */
/* --------------------------------------------------- */
file_read_devspec: procedure expose DevSpecFile DevSpec. msglevel
if stream(DevSpecFile, 'c', 'open read') \= 'READY:' then do
   call msg 3, 'Could not open file with device specific data' DevSpecFile
   return 1                                                 /* zero records */
end

call msg 2, 'Reading device specific data items from' DevSpecFile '...'
f_size  = chars(DevSpecFile)                                /* determine filesize */
f_input = charin(DevSpecFile, 1, f_size)                    /* read file as a whole */
call stream DevSpecFile, 'c', 'close'                       /* done */
f_index = 0                                                 /* start index */

do until x = '{' | x = 0                                    /* search begin of pinmap */
   x = json_newchar()
end
do until x = '}' | x = 0                                    /* end of pinmap */
   do until x = '}' | x = 0                                 /* end of pic */
      PicName = json_newstring()                            /* new PIC */
      do until x = '{' | x = 0                              /* search begin PIC specs */
         x = json_newchar()
      end
      do until x = '}' | x = 0                              /* this PIC's specs */
         ItemName = json_newstring()
         value = json_newstring()
         DevSpec.PicName.ItemName = value
         x = json_newchar()
      end
      x = json_newchar()
   end
   x = json_newchar()
end
return 0


/* --------------------------------------------------- */
/* Read file with pin alias information (JSON format)  */
/* Fill compound variable PinMap. and PinANMap.        */
/* (simplyfied implementation of reading a JSON file)  */
/* --------------------------------------------------- */
file_read_pinmap: procedure expose PinMapFile PinMap. PinANMap. msglevel
if stream(PinMapFile, 'c', 'open read') \= 'READY:' then do
   call msg 3, 'Could not open file with Pin Alias information' PinMapFile
   return                                                   /* zero records */
end

call msg 2, 'Reading pin alias names from' PinMapFile '...'
f_size  = chars(PinMapFile)
f_input = charin(PinMapFile, 1, f_size)
call stream DevSpecFile, 'c', 'close'
f_index = 0                                                 /* start index */

do until x = '{' | x = 0                                    /* search begin of pinmap */
   x = json_newchar()
end
do until x = '}' | x = 0                                    /* end of pinmap */
   do until x = '}' | x = 0                                 /* end of pic */
      PicName = json_newstring()                            /* new PIC */
      PinMap.PicName = PicName                              /* PIC listed in JSON file */
      do until x = '{' | x = 0                              /* search begin PIC specs */
        x = json_newchar()
      end
      ANcount = 0                                           /* zero ANxx count this PIC */
      do until x = '}' | x = 0                              /* this PICs specs */
         pinname = json_newstring()
         i = 0                                              /* no aliases (yet) */
         do until x = '[' | x = 0                           /* search pin aliases */
           x = json_newchar()
         end
         do until x = ']' | x = 0                           /* end of aliases this pin */
            aliasname = json_newstring()
            if aliasname = '' then do                       /* no (more) aliases */
               x = ']'                                      /* must have been last char read! */
               iterate
            end
            if right(aliasname,1) = '-' then                /* handle trailing '-' character */
               aliasname = strip(aliasname,'T','-')'_NEG'
            else if right(aliasname,1) = '+' then           /* handle trailing '+' character */
               aliasname = strip(aliasname,'T','+')'_POS'
            i = i + 1
            PinMap.PicName.pinname.i = aliasname
            if left(aliasname,2) = 'AN' & datatype(substr(aliasname,3)) = 'NUM' then do
               ANcount = ANcount + 1
               PinANMap.PicName.aliasname = PinName         /* pin_ANx -> RXy */
            end
            x = json_newchar()
         end
         PinMap.PicName.pinname.0 = i
         x = json_newchar()
      end
      ANCountName = 'ANCOUNT'
      PinMap.PicName.ANCountName = ANcount
      x = json_newchar()
   end
   x = json_newchar()
end
return 0


/* -------------------------------- */
json_newstring: procedure expose f_input f_index f_size

do until x = '"' | x = ']' | x = '}' | x = 0                /* start new string or end of everything */
   x = json_newchar()
end
if x \= '"' then                                            /* no string found */
   return ''
str = ''
x = json_newchar()                                          /* first char */
do while x \= '"'
   str = str||x
   x = json_newchar()
end
return str


/* -------------------------------- */
json_newchar: procedure expose f_input f_index f_size
do while f_index < f_size
   f_index = f_index + 1
   x = substr(f_input,f_index,1)                            /* next character */
   if x <= ' ' then                                         /* white space */
      iterate
   return x
end
return 0                                                    /* dummy (end of file) */


/* ---------------------------------------------------- */
/* Read file with oscillator name mapping               */
/* Interpret contents: fill compound variable Fuse_Def. */
/* ---------------------------------------------------- */
file_read_fusedef: procedure expose FuseDefFile Fuse_Def. msglevel
if stream(FuseDefFile, 'c', 'open read') \= 'READY:' then do
   call msg 3, 'Could not open file with fuse_def mappings' FuseDefFile
   return 1                                                 /* zero records */
end
call msg 1, 'Reading Fusedef Names from' FuseDefFile '... '
do while lines(FuseDefFile) > 0                             /* whole file */
   interpret linein(FuseDefFile)                            /* read and interpret line */
end
call stream FuseDefFile, 'c', 'close'                       /* done */
return 0


/* --------------------------------------------------------- */
/* procedure to extend address with mirrored addresses       */
/* input:  - register number (decimal)                       */
/*         - address  (decimal)                              */
/* returns string of addresses between {}                    */
/* (only for Core 12 and 14)                                 */
/* --------------------------------------------------------- */
sfr_mirror_address: procedure expose Ram. BankSize NumBanks Core
parse upper arg addr .
addr_list = '{ 0x'D2X(addr)                                 /* open bracket, orig. addr */
if Core = '12' | Core = '14' then do
   MaxBanks = NumBanks
   if NumBanks > 4 then
      MaxBanks = 4
   do i = (addr + BankSize) to (MaxBanks * BankSize - 1) by BankSize  /* avail ram */
      if addr = Ram.i then                                  /* matching reg number */
         addr_list = addr_list',0x'D2X(i)                   /* concatenate to string */
   end
end
return addr_list' }'                                        /* complete string */


/* --------------------------------------------- */
/* Signal duplicates names                       */
/* Arguments: - new name                         */
/*            - register                         */
/* Return - 0 when name is unique                */
/*        - 1 when name is duplicate             */
/* Collect all names in Name. compound variable  */
/* --------------------------------------------- */
duplicate_name: procedure expose Name. PicName msglevel
parse arg newname, reg .
if newname = '' then                                        /* no name specified */
   return 1                                                 /* not acceptable */
if Name.newname = '-' then do                               /* name not in use yet */
   Name.newname = reg                                       /* mark in use by which reg */
   return 0                                                 /* unique */
end
if reg \= newname then do                                   /* not alias of register */
   call msg 2, 'Duplicate name:' newname 'in' reg'. First occurence:' Name.newname
   return 1                                                 /* duplicate */
end
return 0


/* -------------------------------------------------- */
/* translate string to lower or upper case            */
/* translate (capital) meta-characters to ASCII chars */
/* -------------------------------------------------- */

tolower: procedure
return translate(arg(1), xrange('a','z'), xrange('A','Z'))

toupper: procedure
return translate(arg(1), xrange('A','Z'), xrange('a','z'))

toascii: procedure
xml.1.1 = '&LT;'
xml.1.2 = '<'
xml.2.1 = '&GT;'
xml.2.2 = '>'
xml.3.1 = '&AMP;'
xml.3.2 = '&'
xml.0 = 3
parse arg ln
do i = 1 to xml.0
   lx = ln
   ln = ''
   x = pos(xml.i.1, lx)
   do while x > 0
      ln = ln||left(lx,x-1)||xml.i.2                        /* meta -> ASCII-char */
      lx = substr(lx, x + length(xml.i.1))                  /* remainder of line */
      x = pos(xml.i.1, lx)
   end
   ln = ln||lx                                              /* last part */
end
return ln



/* ---------------------------------------------- */
/* message handling, depending on msglevel        */
/* ---------------------------------------------- */
msg: procedure expose msglevel
parse arg lvl, txt
   if lvl = 0 then                                          /* used for continuation lines */
      say txt                                               /* for continuation lines, etc. */
   else if lvl >= msglevel then do
      if lvl = 1 then                                       /* info level */
         say '   Info: 'txt
      else if lvl = 2 then                                  /* warning level */
         say '   Warning: 'txt
      else                                                  /* error level */
         say '   Error: 'txt
   end
return lvl


/* ---------------------------------------------- */
/* Some procedures to help script debugging       */
/* ---------------------------------------------- */
catch_error:
Say 'Rexx Execution error, rc' rc 'at script line' SIGL
if rc > 0 & rc < 100 then                                   /* msg text only for rc 1..99 */
  say ErrorText(rc)
return rc

catch_syntax:
if rc = 4 then                                              /* interrupted */
   exit
Say 'Rexx Syntax error, rc' rc 'at script line' SIGL":"
if rc > 0 & rc < 100 then                                   /* rc 1..99 */
  say ErrorText(rc)
Say SourceLine(SIGL)
return rc

