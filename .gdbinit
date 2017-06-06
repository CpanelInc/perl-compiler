# From http://cpansearch.perl.org/src/GOZER/mod_perl-1.31/.gdbinit

#some handy debugging macros, hopefully you'll never need them
#some don't quite work, like dump_hv and hv_fetch,
#where's the bloody manpage for .gdbinit syntax?

set history save on
set print pretty on
set pagination off
set confirm off

# experimental
# https://sourceware.org/gdb/onlinedocs/gdb/Print-Settings.html
set print array on
set print array-indexes on

# unsafe but can load .gdbinit from a local directory
#set auto-load safe-path /

macro define __builtin_offsetof(T, F) ((int) &(((T *) 0)->F))

define dumphv
    set $n = ((XPVHV*)  ($arg0)->sv_any)->xhv_keys
    set $i = 0
    set $key = 0
    set $klen = 0
    call Perl_hv_iterinit($arg0)
    while $i <= $n
        set $sv = call Perl_hv_iternextsv($arg0, &$key, &$klen)
        printf "%s = `%s'\n", $key, ((XPV*) ($sv)->sv_any )->xpv_pv
        set $i = $i + 1
    end
end

define thttpd
   run -X -f `pwd`/t/conf/httpd.conf -d `pwd`/t
#   set $sv = perl_eval_pv("$Apache::ErrLog = '/tmp/mod_perl_error_log'",1)
end

define httpd
   run -X -d `pwd`
   set $sv = perl_eval_pv("$Apache::ErrLog = Apache->server_root_relative('logs/error_log')", 1)
   #printf "error_log = %s\n", ((XPV*) ($sv)->sv_any )->xpv_pv
end

define STpvx
   print ((XPV*) (PL_stack_base [ax + ($arg0)] )->sv_any )->xpv_pv
end

define TOPs
    print ((XPV*) (**sp)->sv_any )->xpv_pv
end

define curstash
   print ((XPVHV*) (PL_curstash)->sv_any)->xhv_name
end

define defstash
   print ((XPVHV*) (PL_defstash)->sv_any)->xhv_name
end

define curinfo
   printf "%d:%s\n", PL_curcop->cop_line, \
   ((XPV*)(*(XPVGV*)PL_curcop->cop_filegv->sv_any)\
   ->xgv_gp->gp_sv->sv_any)->xpv_pv
end

define SvPVX
print ((XPV*) ($arg0)->sv_any )->xpv_pv
end

define SvCUR
   print ((XPV*)  ($arg0)->sv_any )->xpv_cur
end

define SvLEN
   print ((XPV*)  ($arg0)->sv_any )->xpv_len
end

define SvEND
   print (((XPV*)  ($arg0)->sv_any )->xpv_pv + ((XPV*)($arg0)->sv_any )->xpv_cur) - 1
end

define SvSTASH
   print ((XPVHV*)((XPVMG*)($arg0)->sv_any )->xmg_stash)->sv_any->xhv_name
end

define SvTAINTED
   print ((($arg0)->sv_flags  & (0x00002000 |0x00004000 |0x00008000 ))  && Perl_sv_tainted ($arg0))
end

define SvTRUE
   print (	!$arg0	? 0	:    (($arg0)->sv_flags  & 0x00040000 ) 	?   ((PL_Xpv  = (XPV*)($arg0)->sv_any ) &&	(*PL_Xpv ->xpv_pv > '0' ||	PL_Xpv ->xpv_cur > 1 ||	(PL_Xpv ->xpv_cur && *PL_Xpv ->xpv_pv != '0'))	? 1	: 0)	:	(($arg0)->sv_flags  & 0x00010000 ) 	? ((XPVIV*)  ($arg0)->sv_any )->xiv_iv  != 0	:   (($arg0)->sv_flags  & 0x00020000 ) 	? ((XPVNV*)($arg0)->sv_any )->xnv_nv  != 0.0	: Perl_sv_2bool ($arg0) )
end

define GvHV
   set $hv = (((((XPVGV*)($arg0)->sv_any ) ->xgv_gp) )->gp_hv)
end

define GvSV
 print ((XPV*) ((((XPVGV*)($arg0)->sv_any ) ->xgv_gp) ->gp_sv )->sv_any )->xpv_pv
end

define GvNAME
   print (((XPVGV*)($arg0)->sv_any ) ->xgv_name)
end

define GvFILEGV
   print ((XPV*) ((((XPVGV*)$arg0->filegv)->xgv_gp)->gp_sv)->sv_any)->xpv_pv
end

define CvNAME
   print ((XPVGV*)(((XPVCV*)($arg0)->sv_any)->xcv_gv)->sv_any)->xgv_name
end

define CvSTASH
   print ((XPVHV*)(((XPVGV*)(((XPVCV*)($arg0)->sv_any)->xcv_gv)->sv_any)->xgv_stash)->sv_any)->xhv_name
end

define CvDEPTH
   print ((XPVCV*)($arg0)->sv_any )->xcv_depth
end

define CvFILEGV
   print ((XPV*) ((((XPVGV*)((XPVCV*)($arg0)->sv_any )->xcv_filegv)->xgv_gp)->gp_sv)->sv_any)->xpv_pv
end

define SVOPpvx
   print ((XPV*) ( ((SVOP*)$arg0)->op_sv)->sv_any )->xpv_pv
end

define HvNAME
   print ((XPVHV*)$arg0->sv_any)->xhv_name
end

define HvKEYS
   print ((XPVHV*)  ($arg0)->sv_any)->xhv_keys
end

define AvFILL
   print ((XPVAV*)  ($arg0)->sv_any)->xav_fill
end

define dumpav
    set $n = ((XPVAV*)  ($arg0)->sv_any)->xav_fill
    set $i = 0
    while $i <= $n
        set $sv = *Perl_av_fetch($arg0, $i, 0)
        printf "[%u] -> `%s'\n", $i, ((XPV*) ($sv)->sv_any )->xpv_pv
        set $i = $i + 1
    end
end

define svflags
    set $flags = ((SV*) ($arg0))->sv_flags
    dflags $flags
end
document svflags
Print a human readable version of the flags set
in one SV*. (perl 5.24)

Usage svflags SV*

also view dflags
end

define dflags
    set $flags = $arg0
    printf "Flags value: 0x%x = %d\n", $flags, $flags
    # type
    set $type = 0xf & $flags
    printf "Type:  %d - ", $type
    if $type == 0
        printf "SVt_NULL"
    end
    if $type == 1
        printf "SVt_IV"
    end
    if $type == 2
        printf "SVt_NV"
    end
    if $type == 3
        printf "SVt_PV"
    end
    if $type == 4
        printf "SVt_INVLIST"
    end
    if $type == 5
        printf "SVt_PVIV"
    end
    if $type == 6
        printf "SVt_PVNV"
    end
    if $type == 7
        printf "SVt_PVMG"
    end
    if $type == 8
        printf "SVt_REGEXP"
    end
    if $type == 9
        printf "SVt_PVGV"
    end
    if $type == 10
        printf "SVt_PVLV"
    end
    if $type == 11
        printf "SVt_PVAV"
    end
    if $type == 12
        printf "SVt_PVHV"
    end
    if $type == 13
        printf "SVt_PVCV"
    end
    if $type == 14
        printf "SVt_PVFM"
    end
    if $type == 15
        printf "SVt_PVIO"
    end

    printf "\nFlags:"

    # flags
    if ($flags & 0x00000100)
        printf " SVf_IOK"
    end
    if ($flags & 0x00000200)
        printf " SVf_NOK"
    end
    if ($flags & 0x00000400)
        printf " SVf_POK"
    end
    if ($flags & 0x00000800)
        printf " SVf_ROK"
    end
    if ($flags & 0x00001000)
        printf " SVp_IOK"
    end
    if ($flags & 0x00002000)
        printf " SVp_NOK"
    end
    if ($flags & 0x00004000)
        printf " SVp_POK"
    end
    if ($flags & 0x00008000)
        printf " SVp_SCREAM"
    end
    if ($flags & 0x00010000)
        printf " SVf_PROTECT"
    end
    if ($flags & 0x00020000)
        printf " SVs_PADTMP"
    end
    if ($flags & 0x00040000)
        printf " SVs_PADSTALE"
    end
    if ($flags & 0x00080000)
        printf " SVs_TEMP"
    end
    if ($flags & 0x00100000)
        printf " SVs_OBJECT"
    end
    if ($flags & 0x00200000)
        printf " SVs_GMG"
    end
    if ($flags & 0x00400000)
        printf " SVs_SMG"
    end
    if ($flags & 0x00800000)
        printf " SVs_RMG"
    end
    if ($flags & 0x01000000)
        printf " SVf_FAKE"
    end
    if ($flags & 0x02000000)
        printf " SVf_OOK (Aux struct for HV)"
    end
    if ($flags & 0x04000000)
        printf " SVf_BREAK"
    end
    if ($flags & 0x08000000)
        printf " SVf_READONLY"
    end
    if ($flags & 0x10000000)
        printf " SVf_IsCOW|SVf_AMAGIC"
    end
    if ($flags & 0x20000000)
        printf " SVf_UTF8|SVphv_SHAREKEYS"
    end
    if ($flags & 0x40000000)
        printf " SVpav_REAL|SVphv_LAZYDEL|SVpbm_VALID|SVrepl_EVAL"
    end
    if ($flags & 0x80000000)
        printf " SVf_IVisUV|SVpav_REIFY|SVphv_HASKFLAGS|SVprv_WEAKREF"
    end

    printf "\n"
end
document dflags
Convert a numerical value for perl 5.24 flags
to a human readable version.
Usage: dflags NUM

also view svflags
end

define dumphv
    set $n = ((XPVHV*)  ($arg0)->sv_any)->xhv_keys
    set $i = 0
    set $key = 0
    set $klen = 0
    Perl_hv_iterinit($arg0)
    while $i <= $n
        set $sv = Perl_hv_iternextsv($arg0, &$key, &$klen)
        printf "%s = `%s'\n", $key, ((XPV*) ($sv)->sv_any )->xpv_pv
        set $i = $i + 1
    end
end

define dump_defstash
  print "# PL_defstash:\n"
  dump_hv PL_defstash
end

define _show_index_for
  set $svany = (int) $arg0
  set $name  = $arg1
  set $list  = $arg2
  set $max   = (int) $arg3

  set $first = (int) &($list[0])
  set $size  = (int) sizeof($list[0])
  set $last = $first + $max

  #printf "first:%d ; last:%d ; size:%d ; SV:%d", $first, $last, $size, $svany

  if $svany && $svany >= $first && $svany <= $last
    printf "%s[%d] = ", $name, (int) ( ($svany - $first) / $size )
  end

end


define dump_sv
  set $sv        = (SV*) $arg0
  set $showxpv = 1

  if $argc >= 2
    set $showxpv = (int) $arg1
  end

  svflags $sv
  printf "====== SV =====\n"
  _show_index_for $sv "sv_list" sv_list sizeof(sv_list)
  print *(SV*) $sv

  set $flags = ((SV*) ($sv))->sv_flags
  set $type = 0xf & $flags
  set $svany = $sv->sv_any

  if $svany > 0 && $showxpv
    if $type == 2
        printf "====== SvANY:XPVNV =====\nSvANY(sv) = "
        _show_index_for $svany "xpvnv_list" xpvnv_list sizeof(xpvnv_list)
        p *(XPVNV*) $svany
    end

    if $type == 3
        printf "====== SvANY:XPV =====\nSvANY(sv) = "
        _show_index_for $svany "xpv_list" xpv_list sizeof(xpv_list)
        p *(XPV*) $svany
    end

    if $type == 11
        printf "====== SvANY:XPVAV =====\nSvANY(sv) = "
        _show_index_for $svany "xpvav_list" xpvav_list sizeof(xpvav_list)
        p *(XPVAV*) $svany
    end

    if $type == 12
        printf "====== SvANY:XPVHV =====\n"
        _show_index_for $svany "xpvhv_list" xpvhv_list sizeof(xpvhv_list)
        p *(XPVHV*) $svany
    end

    if $type == 13
        printf "====== SvANY:XPVCV =====\n"
        _show_index_for $svany "xpvcv_list" xpvcv_list sizeof(xpvcv_list)
        p *(XPVCV*) $svany
    end
  end

end

define dump_hv
  set $hv   = (HV*) $arg0
  set $keys = (int) ( ((XPVHV*)  ($hv)->sv_any)->xhv_keys )
  set $max = (int) ( ((XPVHV*)  ($hv)->sv_any)->xhv_max )

  set $i = 0
  printf "HV 0x%x: keys=%d ; max=%d\n", $hv, $keys, $max
  if $hv == PL_defstash
    printf "... HV is PL_defstash\n"
  end
  if $hv == PL_curstash
    printf "... HV is PL_curstash\n"
  end

  set $h = (($hv)->sv_u.svu_hash)
  # check all buckets, max included as this is = X^2 - 1

  if $h
    while $i <= $max
      # only show used buckets
      if $h[$i]
        set $c = 1
        set $next = $h[$i]->hent_next
        while $next
          set $c = $c + 1
          set $next = $next->hent_next
        end
        # generic stats for the bucket
        printf "bucket #%d: 0x%x [ %d element(s) ]\n", $i, $h[$i], $c

        # display all keys in the bucket
        set $next = $h[$i]
        printf "  "
        while $next
          printf "%s ", ((HEK*) ( (HE*) $next)->hent_hek)->hek_key
          set $next = $next->hent_next
        end
        printf "\n"

        #p (char *) ((HEK*) ( (HE*) 0x618810)->hent_hek)->hek_key

      end
      set $i = $i + 1
    end
  end

end


define find_and_dump_gv
   find_and_dump_gv_from_hv $arg0 PL_defstash
end

define find_and_dump_gv_from_hv
  set $search = (char*) $arg0
  set $hv     = (HV*) $arg1
  set $max = (int) ( ((XPVHV*)  ($hv)->sv_any)->xhv_max )

  set $i = 0
  set $h = (($hv)->sv_u.svu_hash)

  while $i <= $max
    if $h[$i]
      # display all keys in the bucket
      set $next = $h[$i]
      while $next
        set $key  = ((HEK*) ( (HE*) $next)->hent_hek)->hek_key
        if strcmp($key, $search) == 0
          printf "Found '%s' HE=0x%x\n", $search, $next
          dump_gv_from_he $next
          return
        end

        set $next = $next->hent_next
      end
    end
    set $i = $i + 1
  end
end

define dump_gv_from_he
  set $he  = (HE*) $arg0
  set $key = ((HEK*) ((HE*) $he)->hent_hek)->hek_key
  set $gv  = (GV*) ((HE*) $he)->he_valu.hent_val

  printf "*** HEK key='%s'\n", $key
  dump_gv $gv

end

define dump_gv
  set $gv    = (GV*) $arg0
  set $gp    = (GP*) $gv->sv_u.svu_gp
  set $xpvgv = (XPVGV*) $gv->sv_any
  # p *(GP*) ((GV*) ((HE*) 0x69a528)->he_valu.hent_val)->sv_u.svu_gp
  printf "GV: 0x%x = ", $gv
  _show_index_for $gv "gv_list" gv_list sizeof(gv_list)
  # could also use a simple print
  #p *$gv
  printf "{ sv_any=0x%x, refcnt=%d, flags=0x%x, gp=0x%x}\n", $gv->sv_any, $gv->sv_refcnt, $gv->sv_flags, $gv->sv_u.svu_gp
  printf "\n"
  svflags $gv
  printf "\n"
  if ( $xpvgv )
    printf "SvANY(gv)=XPVGV: 0x%x = { stash=0x%x, magic=0x%x, cur=%d, len=%d, namehek=0x%x, xgv_stash=0x%x }\n", $xpvgv, $xpvgv->xmg_stash, $xpvgv->xmg_u.xmg_magic, $xpvgv->xpv_cur, $xpvgv->xpv_len_u.xpvlenu_len, $xpvgv->xiv_u.xivu_namehek, $xpvgv->xnv_u.xgv_stash
  end
  #p *$xpvgv
  printf "GP: 0x%x -> ", $gp
  if $gp
    p *$gp

    _show_index_for $gp "gp_list" gp_list sizeof(gp_list)
    printf "sv.gp\n"

    _show_index_for $gp.gp_sv "sv_list" sv_list sizeof(sv_list)
    printf "sv.gp.gp_sv\n"

    _show_index_for $gp.gp_cv "sv_list" sv_list sizeof(sv_list)
    printf "sv.gp.gp_cv\n"

    _show_index_for $gp.gp_hv "sv_list" sv_list sizeof(sv_list)
    printf "sv.gp.gp_hv\n"

    _show_index_for $gp.gp_av "sv_list" sv_list sizeof(sv_list)
    printf "sv.gp.gp_av\n"

    # .... show keys from the hash
    set $gp_hv = (HV*) $gp->gp_hv
    printf "\nKeys from gp_hv=0x%x\n", $gp_hv
    dump_hv $gp_hv
  end
end

define hvfetch
   set $klen = strlen($arg1)
   set $sv = *Perl_hv_fetch($arg0, $arg1, $klen, 0)
   printf "%s = `%s'\n", $arg1, ((XPV*) ($sv)->sv_any )->xpv_pv
end

define hvINCval
   set $hv = (((((XPVGV*)(PL_incgv)->sv_any)->xgv_gp))->gp_hv)
   set $klen = strlen($arg0)
   set $sv = *Perl_hv_fetch($hv, $arg0, $klen, 0)
   printf "%s = `%s'\n", $arg0, ((XPV*) ($sv)->sv_any )->xpv_pv
end

define dumpany
   set $sv = Perl_newSVpv("use Data::Dumper; Dumper \\",0)
   set $void = Perl_sv_catpv($sv, $arg0)
   set $dump = perl_eval_pv(((XPV*) ($sv)->sv_any )->xpv_pv, 1)
   printf "%s = `%s'\n", $arg0, ((XPV*) ($dump)->sv_any )->xpv_pv
end

define dumpanyrv
   set $rv = Perl_newRV((SV*)$arg0)
   set $rvpv = perl_get_sv("main::DumpAnyRv", 1)
   set $void = Perl_sv_setsv($rvpv, $rv)
   set $sv = perl_eval_pv("use Data::Dumper; Dumper $::DumpAnyRv",1)
   printf "`%s'\n", ((XPV*) ($sv)->sv_any )->xpv_pv
end

define svpeek
   set $pv = Perl_sv_peek((SV*)$arg0)
   printf "%s\n", $pv
end

define caller
   set $sv = perl_eval_pv("scalar caller", 1)
   printf "caller = %s\n", ((XPV*) ($sv)->sv_any )->xpv_pv
end

define cluck
   set $sv = perl_eval_pv("Carp::cluck(); `tail '$Apache::ErrLog'`", 1)
   printf "%s\n", ((XPV*) ($sv)->sv_any )->xpv_pv
end

define longmess
   set $sv = perl_eval_pv("Carp::longmess()", 1)
   printf "%s\n", ((XPV*) ($sv)->sv_any )->xpv_pv
end

define shortmess
   set $sv = perl_eval_pv("Carp::shortmess()", 1)
   printf "%s\n", ((XPV*) ($sv)->sv_any )->xpv_pv
end

define perl_get_sv
    set $sv = perl_get_sv($arg0, 0)
    printf "%s\n", $sv ? ((XPV*) ((SV*)$sv)->sv_any)->xpv_pv : "undef"
end
#directory /usr/src/perl/perl-5.10.1/perl-5.10.1
#directory /usr/src/perl/perl-5.6.2

set breakpoint pending on
#break XS_B__CC__autovivification
break __asan_report_error
#break B.xs:1398
#break B.c:2044
#break B.xs:1858
#break oplist
#break Perl_do_openn
# require %INC
#break pp_ctl.c:3599
#run
#p/x sv_list[3299]

define run10plc
  run -Mblib -MByteLoader -Dtv bytecode10.plc
end
#set args -Dtv -Mblib -MByteLoader bytecode10.plc
# grep -Hn PL_no_modify *.c|perl -ne'/^([\w.]+:\d+)/ && print "break $1\n";'
#define break_no_modify
#  break av.c:342
#  break av.c:435
#  break av.c:540
#  break av.c:579
#  break av.c:648
#  break av.c:720
#  break av.c:851
#  break doop.c:640
#  break doop.c:1025
#  break doop.c:1111
#  break mg.c:615
#  break mg.c:2361
#  break pp.c:161
#  break pp.c:864
#  break pp.c:881
#  break pp.c:903
#  break pp_hot.c:401
#  break pp_hot.c:2098
#  break pp_hot.c:2966
#  break pp_sort.c:1569
#  break pp_sys.c:1027
#  break regcomp.c:4924
#  break regcomp.c:5225
#  break sv.c:3247
#  break sv.c:3365
#  break sv.c:3424
#  break sv.c:4331
#  break sv.c:4349
#  break sv.c:4748
#  break sv.c:6950
#  break sv.c:7113
#  break sv.c:8390
#  break universal.c:1353
#  break universal.c:1375
#  break universal.c:1396
#  break util.c:3430
#  break util.c:3433
#end

# break Dynaloader.xs:190
# break byteloader_filter
# break perl_destruct
# break byterun.c:77
# break byterun.c:1128
# break Perl_av_extend
# break byterun
# break bl_getc
# break Perl_pp_match
# break Perl_pad_new

# stack dump, sp or PL_sp or my_perl->Istack_sp?
define sp_dump
  if (my_perl && my_perl->broiled)
    p/x **my_perl->Istack_sp
    call Perl_sv_dump(my_perl, *my_perl->Istack_sp)
  else
    p/x **PL_sp
    Perl_sv_dump(*PL_sp)
  end
end
document sp_dump
 => Perl_sv_dump(PL_sp)
end

define op_dump
  if (my_perl && my_perl->broiled)
    p/x *my_perl->Iop
    call Perl_op_dump(my_perl, my_perl->Iop)
  else
    p/x *PL_op
    call Perl_op_dump(PL_op)
  end
end
document op_dump
 => Perl_op_dump(PL_op)
see `odump op`
end

define sv_dump
  p/x *sv
  call Perl_sv_dump(sv)
end
document sv_dump
 => Perl_sv_dump(sv)
see `sdump sv`
end

define tsv_dump
  p/x *sv
  call Perl_sv_dump(my_perl, sv)
end
document tsv_dump
 => Perl_sv_dump(sv)
see `sdump sv`
end

define odump
  p/x *$arg0
  call Perl_op_dump($arg0)
end
document odump
odump op => p/x *op; Perl_op_dump(op)
see `help op_dump` for PL_op
end

define todump
  p/x *$arg0
  call Perl_op_dump(my_perl, $arg0)
end
document todump
todump op => p/x *op; Perl_op_dump(op)
see `help op_dump` for PL_op
end

define sdump
  p/x *$arg0
  call Perl_sv_dump($arg0)
end
document sdump
sdump sv => p/x *sv; Perl_sv_dump(sv)
see `help tsdump`
end

define tsdump
  p/x *$arg0
  call Perl_sv_dump(my_perl, $arg0)
end
document tsdump
tsdump sv => p/x *sv; Perl_sv_dump(my_perl, sv)
see `help sdump`
end
