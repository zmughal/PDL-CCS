# -*- Mode: CPerl -*-
# t/03_ufuncs.t
use Test::More tests => 2*4*17;

##-- common subs
my $TEST_DIR;
BEGIN {
  use File::Basename;
  use Cwd;
  $TEST_DIR = Cwd::abs_path dirname( __FILE__ );
  eval qq{use lib ("$TEST_DIR/$_/blib/lib","$TEST_DIR/$_/blib/arch");} foreach (qw(../.. ..));
  do "$TEST_DIR/common.plt" or  die("$0: failed to load $TEST_DIR/common.plt: $@");
}

##-- common modules
use PDL;
use PDL::CCS::Nd;

use version;
my $HAVE_PDL_2_014 = version->parse($PDL::VERSION) >= version->parse("2.014");

##--------------------------------------------------------------
## ufunc test

##-- i..(i+2): test_ufunc($ufunc_name, $missing_val)
sub test_ufunc {
  my ($ufunc_name, $missing_val) = @_;
  print "test_ufunc($ufunc_name, $missing_val)\n";

  my $pdl_ufunc = PDL->can("${ufunc_name}")
    or die("no PDL Ufunc ${ufunc_name} defined!");
  my $ccs_ufunc = PDL::CCS::Nd->can("${ufunc_name}")
    or die("no CCS Ufunc PDL::CCS::Nd::${ufunc_name} defined!");

  $missing_val = 0 if (!defined($missing_val));
  $missing_val = PDL->topdl($missing_val);
  if ($missing_val->isbad) { $a = $a->setbadif($abad); }
  else                     { $a->where($abad) .= $missing_val; $a->badflag(0); }

  ##-- sorting with bad values doesn't work right in PDL-2.015 ; ccs/vv sorts BAD as minimal, PDL sort BAD as maximal: wtf?
  if ($ufunc_name =~ /qsort/ && $missing_val->isbad) {
    my $inf = $^O =~ /MSWin32/i ? (99**99)**99 : 'inf';
    $missing_val = $inf;
    $a->inplace->setbadtoval($inf);
  }

  my $ccs      = $a->toccs($missing_val);
  $ccs->_whichND($ccs->_whichND->ccs_indx()) if ($ccs->_whichND->type != PDL::ccs_indx());
  my $dense_rc = $pdl_ufunc->($a);
  my $ccs_rc   = $ccs_ufunc->($ccs);

  if ($ufunc_name =~ /_ind$/) {
    ##-- hack: adjust $dense_rc for maximum_ind, minimum_ind
    $dense_rc->where( $a->index2d($dense_rc,sequence($a->dim(1))) == $missing_val ) .= -1;
  } elsif ($ufunc_name =~ /qsorti$/) {
    ##-- hack: adjust $dense_rc for qsorti()
    my $ccs_mask = $dense_rc->zeroes;
    $ccs_mask->indexND( scalar($ccs_rc->whichND) ) .= 1;
    $dense_rc->where( $ccs_mask->not ) .= $ccs_rc->missing;
  }
  my $label = "${ufunc_name}:missing=$missing_val";

  ##-- check output type
 SKIP: {
    skip("${label}:type - only for PDL >= v2.014",1) if (!$HAVE_PDL_2_014);
    isok("${label}:type", $ccs_rc->type, $dense_rc->type);
  }

  ##-- check output values
 SKIP: {
    ##-- RT bug #126294 (ses also analogous tests in CCS/Ufunc/t/01_ufunc.t)
    skip("RT #126294 - PDL::borover() appears to be broken", 1)
      if ($label eq 'borover:missing=BAD' && pdl([10,0,-2])->setvaltobad(0)->borover->sclr != -2);

    pdlok("${label}:vals", $ccs_rc->decode, $dense_rc);
  }

}


##--------------------------------------------------------------
## all tests
our ($BAD);
foreach $missing (0,1,255,$BAD) { ##-- *4
  foreach $ufunc (
		  qw(sumover prodover dsumover dprodover),  ## *17
		  qw(andover orover bandover borover),
		  qw(maximum minimum),
		  qw(maximum_ind minimum_ind),
		  qw(nbadover ngoodover), #nnz
		  qw(average),
		  qw(qsort qsorti)
		 )
    {
      test_ufunc($ufunc,$missing);
    }
}

print "\n";
# end of t/*.t

