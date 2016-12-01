##############################################
# $Id: 32_LedController.pm 0 2016-05-01 12:00:00Z herrmannj $

# TODO
# I'm fully aware of this http://xkcd.com/1695/
# 
# 

# versions
# 00 POC
# 01 initial working version
# 02 stabilized, transitions working, initial use of attrs

# verbose level
# 0: quit
# 1: error
# 2: warning
# 3: user command
# 4: 1st technical level (detailed internal reporting)
# 5: 2nd technical level (full internal reporting)

package main;

use strict;
use warnings;

use Time::HiRes;
use Time::HiRes qw(usleep nanosleep);
use JSON;
use Data::Dumper;

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

sub
LedController_Initialize(@) {

  my ($hash) = @_;

  $hash->{DefFn}        = 'LedController_Define';
  $hash->{UndefFn}      = 'LedController_Undef';
  $hash->{ShutdownFn}   = 'LedController_Undef';
  $hash->{SetFn}        = 'LedController_Set';
  $hash->{GetFn}        = 'LedController_Get';
  $hash->{AttrFn}       = 'LedController_Attr';
  $hash->{NotifyFn}     = 'LedController_Notify';
  $hash->{ReadFn}       = 'LedController_Read';
  $hash->{AttrList}     = "defaultRamp defaultColor colorTemp"
                          ." $readingFnAttributes";
  require "HttpUtils.pm";
  
  # initialize message bus and process framework
  #require "Broker.pm";
  #my %service = (
  #  'functions' => {
  #    'connectFn' => 'LedControllerService_Initialize'
  #  }
  #);
  #'LedController_InitializeChild'
  #Broker::RESPONSEService('LedControllerService', \%service);
  
  return undef;
}

sub
LedController_Define($$) {

  my ($ledDevice, $def) = @_;
  my @a = split("[ \t][ \t]*", $def); 
  my $name = $a[0];
  
  $ledDevice->{IP} = $a[2];
  
  @{$ledDevice->{helper}->{cmdQueue}} = ();
  $ledDevice->{helper}->{isBusy} = 0;
  # TODO remove, fixeg loglevel 5 only for debugging
  $attr{$ledDevice->{NAME}}{verbose} = 5;
  LedController_GetConfig($ledDevice);
  
  return undef;
  return "wrong syntax: define <name> LedController <type> <ip-or-hostname>" if(@a != 4);  
  return "$ledDevice->{LEDTYPE} is not supported at $ledDevice->{CONNECTION} ($ledDevice->{IP})";
}

sub
LedController_Undef(@) {
  return undef;
}

sub
LedController_Set(@) {

	my ($ledDevice, $name, $cmd, @args) = @_;
  
	return "Unknown argument $cmd, choose one of hsv rgb state update hue sat val dim on off rotate raw" if ($cmd eq '?');

	my $descriptor = '';
	my $colorTemp = AttrVal($ledDevice->{NAME},'colorTemp',0);
	$colorTemp = ($colorTemp)?$colorTemp:2700;
	Log3 ($ledDevice, 5, "$ledDevice->{NAME} (Set) called with $cmd, busy flag is $ledDevice->{helper}->{isBusy}\n name is $name, args ".Dumper(@args));
	Log3 ($ledDevice, 3, "$ledDevice->{NAME} (Set) called with $cmd, busy flag is $ledDevice->{helper}->{isBusy}");  
  
	if ($cmd eq 'hsv') {

		my ($h, $s, $v) = split ',', $args[0];
		my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[1], $args[2]);
		LedController_SetHSVColor($ledDevice, $h, $s, $v, $colorTemp, $t, (($t==0)?'solid':'fade'), $q, $d);
   
	} elsif ($cmd eq 'rgb') {
		# the native mode of operation for those controllers is HSV
		# I am converting RGB into HSV and then set that
		# This is to make use of the internal color compensation of the controller
		return "RGB is required hex RRGGBB" if (defined($args[0]) && $args[0] !~ /^[0-9A-Fa-f]{6}$/);
		my $r = hex(substr($args[0],0,2));
		my $g = hex(substr($args[0],2,2));
		my $b = hex(substr($args[0],4,2));
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} raw: $args[0], r: $r, g: $g, b: $b");
		my ($h, $s, $v) = LedController_RGB2HSV($ledDevice, $r, $g, $b);
		my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[1], $args[2]);
		LedController_SetHSVColor($ledDevice, $h, $s, $v, $colorTemp, $t, (($t==0)?'solid':'fade'), $q, $d);

	} elsif ($cmd eq 'rotate'){
	  
		my $rot = $args[0];
	  	
	  	my $h=ReadingsVal($ledDevice->{NAME}, "hue", 0);
		$h = ($h + $rot)%360;
		
		my $v = ReadingsVal($ledDevice->{NAME}, "val", 0);
		my $s = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting HUE to $h, keeping VAL $v and SAT $s");
		my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[1], $args[2]);
		LedController_SetHSVColor($ledDevice, $h, $s, $v, $colorTemp, $t, (($t==0)?'solid':'fade'), $q, $d);
	  		
	} elsif ($cmd eq 'on') {
		# added an attr "defaultColor" as a h,s,v tupel. This will be used as the default "on" color
		# if you want to keep the hue/sat from before, use "dim" or it's equivalent "val"
		#
		my $defaultColor=AttrVal($ledDevice->{NAME},'defaultColor',0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} defaultColor: $defaultColor");
		my ($h, $s, $v) = (($defaultColor) eq (0))?(0,0,100):split(',',$defaultColor );
   	Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting VAL to $v, SAT to $s and HUE $h");
   	Log3 ($ledDevice, 5, "$ledDevice->{NAME} args[0] = $args[0], args[1] = $args[1]");
   	my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[0], $args[1]);
   	LedController_SetHSVColor($ledDevice, $h, $s, $v, $colorTemp, $t, (($t==0)?'solid':'fade'), $q, $d);


	} elsif ($cmd eq 'off') {

		my $v = 0;
		my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $s = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting VAL to $v, keeping HUE $h and SAT $s");
		my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[0], $args[1]);
		LedController_SetHSVColor($ledDevice, $h, $s, $v, $colorTemp, $t, (($t==0)?'solid':'fade'), $q, $d);

	} elsif ($cmd eq 'val'||$cmd eq "dim") {
      
		my $v = $args[0];
		my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $s = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting VAL to $v, keeping HUE $h and SAT $s");
		my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[1], $args[2]);
		LedController_SetHSVColor($ledDevice, $h, $s, $v, $colorTemp, $t, (($t==0)?'solid':'fade'), $q, $d);
	        
	} elsif ($cmd eq 'sat') {
      
		my $s = $args[0];
		my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $v = ReadingsVal($ledDevice->{NAME}, "val", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting SAT to $s, keeping HUE $h and VAL $v");
		my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[1], $args[2]);
		LedController_SetHSVColor($ledDevice, $h, $s, $v, $colorTemp, $t, (($t==0)?'solid':'fade'), $q, $d);

	} elsif ($cmd eq 'hue') {
      
		my $h = $args[0];
		my $v = ReadingsVal($ledDevice->{NAME}, "val", 0);
		my $s = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting HUE to $h, keeping VAL $v and SAT $s");
		my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[1], $args[2]);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} got extended args: t = $t, q = $q, d=$d");
      
		LedController_SetHSVColor($ledDevice, $h, $s, $v, $colorTemp, $t, (($t==0)?'solid':'fade'), $q, $d);

	} elsif ($cmd eq 'pause'){
		my $v = ReadingsVal($ledDevice->{NAME}, "val", 0);
		my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $s = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[0], $args[1]);
		
		LedController_SetHSVColor($ledDevice, $h, $s, $v, $colorTemp, $t, 'solid', $q, $d);
		
	} elsif ( $cmd eq 'raw' ) {

		my ($r, $g, $b, $ww, $cw) = split ',',$args[0];
		my ($t, $q, $d) = LedController_ArgsHelper($ledDevice, $args[1], $args[2]);
		LedController_SetRAWColor($ledDevice, $r, $g, $b, $ww, $cw, $colorTemp, $t, (($t==0)?'solid':'fade'), $q, $d);

	} elsif ($cmd eq 'update') {
		LedController_GetHSVColor($ledDevice);
	}
	return undef;
}


sub
LedController_Get(@) {

  my ($ledDevice, $name, $cmd, @args) = @_;
  my $cnt = @args;
  
  return undef;
}

sub
LedController_Attr(@) {

  my ($cmd, $device, $attribName, $attribVal) = @_;
  my $ledDevice = $defs{$device};

  if ($cmd eq 'set' && $attribName eq 'colorTemp'){
  return "colorTemp must be between 2000 and 10000" if ($attribVal <2000 || $attribVal >10000);
  }
  Log3 ($ledDevice, 4, "$ledDevice->{NAME} attrib $attribName $cmd $attribVal") if $attribVal; 
  return undef;
}

# restore previous settings (as set statefile)
sub
LedController_Notify(@) {

  my ($ledDevice, $eventSrc) = @_;
  my $events = deviceEvents($eventSrc, 1);
  my ($hue, $sat, $val);

}

sub
LedController_GetConfig(@) {

  my ($ledDevice) = @_;
  my $ip = $ledDevice->{IP};
  
  my $param = {
    url        => "http://$ip/info",
    timeout    => 30,
    hash       => $ledDevice,
    method     => "GET",
    header     => "User-Agent: fhem\r\nAccept: application/json",
    parser     =>  \&LedController_ParseConfig,
    callback   =>  \&LedController_callback
  };
  Log3 ($ledDevice, 4, "$ledDevice->{NAME}: get config request");
  LedController_addCall($ledDevice, $param);
  return undef;
}

sub
LedController_ParseConfig(@) {

  #my ($param, $err, $data) = @_;
  #my ($ledDevice) = $param->{hash};
  my ($ledDevice, $err, $data) = @_;
  my $res;
  
  Log3 ($ledDevice, 4, "$ledDevice->{NAME}: got config response");
  
  if ($err) {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error $err retriving config");
  } elsif ($data) {
    Log3 ($ledDevice, 5, "$ledDevice->{NAME}: config response data $data");
    eval { 
      $res = JSON->new->utf8(1)->decode($data);
    };
    if ($@) {
     Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error decoding config response $@");
    } else {
      $ledDevice->{DEVICEID} = $res->{deviceid};
      $ledDevice->{FIRMWARE} = $res->{firmware};
      $ledDevice->{MAC} = $res->{connection}->{mac};
      LedController_GetHSVColor($ledDevice);
    } 
  } else {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error <empty data received> retriving config"); 
  }
  return undef;
}

sub
LedController_GetHSVColor(@) {

  my ($ledDevice) = @_;
  my $ip = $ledDevice->{IP};
  
  my $param = {
    url        => "http://$ip/color?mode=HSV",
    timeout    => 30,
    hash       => $ledDevice,
    method     => "GET",
    header     => "User-Agent: fhem\r\nAccept: application/json",
    parser     =>  \&LedController_ParseHSVColor,
    callback   =>  \&LedController_callback
  };
  Log3 ($ledDevice, 4, "$ledDevice->{NAME}: get HSV color request");
  LedController_addCall($ledDevice, $param);
  return undef;
}

sub
LedController_ParseHSVColor(@) {

  #my ($param, $err, $data) = @_;
  #my ($ledDevice) = $param->{hash};
  my ($ledDevice, $err, $data) = @_;
  my $res;
  
  Log3 ($ledDevice, 4, "$ledDevice->{NAME}: got HSV color response");
  
  if ($err) {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error $err retriving HSV color");
  } elsif ($data) {
    Log3 ($ledDevice, 5, "$ledDevice->{NAME}: HSV color response data $data");
    eval { 
      $res = JSON->new->utf8(1)->decode($data);
    };
    if ($@) {
     Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error decoding HSV color response $@");
    } else {
 		# not sure when this would happen
 		# answer herrmannj: this is the place for a valid response, aka we got mail ;)
    } 
  } else {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error <empty data received> retriving HSV color"); 
  }
  return undef;
}

sub
LedController_SetHSVColor(@) {

  my ($ledDevice, $h, $s, $v, $ct, $t, $c, $q, $d) = @_;
  Log3 ($ledDevice, 5, "$ledDevice->{NAME}: called SetHSVColor $h, $s, $v, $ct, $t, $c, $q, $d)");
  my $ip = $ledDevice->{IP};
  my $data; 
  my $cmd;
  
  $cmd->{hsv}->{h}  = $h;
  $cmd->{hsv}->{s}  = $s;
  $cmd->{hsv}->{v}  = $v;
  $cmd->{hsv}->{ct} = $ct;
  $cmd->{cmd}       = $c;
  $cmd->{t}         = $t;
  $cmd->{q}         = $q;
  $cmd->{d}         = $d;
  
  eval { 
    $data = JSON->new->utf8(1)->encode($cmd);
  };
  if ($@) {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error encoding HSV color request $@");
  } else {
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: encoded json data: $data ");
    
    my $param = {
      url        => "http://$ip/color?mode=HSV",
      data       => $data,
      timeout    => 30,
      hash       => $ledDevice,
      method     => "POST",
      header     => "User-Agent: fhem\r\nAccept: application/json",
      parser     =>  \&LedController_ParseSetHSVColor,
      callback   =>  \&LedController_callback,
      loglevel   => 5
    };
    
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: set HSV color request \n$param");
    LedController_addCall($ledDevice, $param);  
  
    # TODO consolidate into an "_setReadings" 
    # TODO move the call to the api result section and add error handling
    
    my ($r, $g, $b)=LedController_HSV2RGB($h, $s, $v);
    my $xrgb=sprintf("%02x%02x%02x",$r,$g,$b);
    Log3 ($ledDevice, 5, "$ledDevice->{NAME}: calculated RGB as $xrgb");
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: begin Readings Update\n   hue: $h\n   sat: $s\n   val:$v\n   ct : $ct\n   HSV: $h,$s,$v\n   RGB: $xrgb");

    readingsBeginUpdate($ledDevice);
    readingsBulkUpdate($ledDevice, 'hue', $h);
    readingsBulkUpdate($ledDevice, 'sat', $s);
    readingsBulkUpdate($ledDevice, 'val', $v);
    readingsBulkUpdate($ledDevice, 'ct' , $ct);
    readingsBulkUpdate($ledDevice, 'hsv', "$h,$s,$v");
    readingsBulkUpdate($ledDevice, 'rgb', $xrgb);
    readingsBulkUpdate($ledDevice, 'state', ($v == 0)?'off':'on');
    readingsEndUpdate($ledDevice, 1);
  }
  return undef;
}

sub
LedController_SetRAWColor(@) {

  my ($ledDevice, $r, $g, $b, $ww, $cw, $ct, $t, $c, $q, $d) = @_;
  Log3 ($ledDevice, 5, "$ledDevice->{NAME}: called SetRAWColor $r, $g, $b, $ww, $cw, $ct, $t, $c, $q, $d");
  
  my $ip = $ledDevice->{IP};
  my $data; 
  my $cmd;
  
  $cmd->{raw}->{r}  = $r;
  $cmd->{raw}->{g}  = $g;
  $cmd->{raw}->{b}  = $b;
  $cmd->{raw}->{ww} = $ww;
  $cmd->{raw}->{cw} = $cw;
  $cmd->{raw}->{ct} = $ct;
  $cmd->{cmd}       = $c;
  $cmd->{t}         = $t;
  $cmd->{q}         = $q;
  $cmd->{d}         = $d;
  
  eval { 
    $data = JSON->new->utf8(1)->encode($cmd);
  };
  if ($@) {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error encoding RAW color request $@");
  } else {
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: encoded json data: $data ");
    
    my $param = {
      url        => "http://$ip/color?mode=RAW",
      data       => $data,
      timeout    => 30,
      hash       => $ledDevice,
      method     => "POST",
      header     => "User-Agent: fhem\r\nAccept: application/json",
      parser     =>  \&LedController_ParseSetRAWColor,
      callback   =>  \&LedController_callback,
      loglevel   => 5
    };
    
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: set RAW color request \n$param");
    LedController_addCall($ledDevice, $param);  
  
    # TODO consolidate into an "_setReadings" 
    # TODO move the call to the api result section and add error handling
    
    # my ($r, $g, $b)=LedController_HSV2RGB($h, $s, $v);
    # my $xrgb=sprintf("%02x%02x%02x",$r,$g,$b);
    # Log3 ($ledDevice, 5, "$ledDevice->{NAME}: calculated RGB as $xrgb");
    # Log3 ($ledDevice, 4, "$ledDevice->{NAME}: begin Readings Update\n   hue: $h\n   sat: $s\n   val:$v\n   ct : $ct\n   HSV: $h,$s,$v\n   RGB: $xrgb");

    # readingsBeginUpdate($ledDevice);
    # readingsBulkUpdate($ledDevice, 'hue', $h);
    # readingsBulkUpdate($ledDevice, 'sat', $s);
    # readingsBulkUpdate($ledDevice, 'val', $v);
    # readingsBulkUpdate($ledDevice, 'ct' , $ct);
    # readingsBulkUpdate($ledDevice, 'hsv', "$h,$s,$v");
    # readingsBulkUpdate($ledDevice, 'rgb', $xrgb);
    # readingsBulkUpdate($ledDevice, 'state', ($v == 0)?'off':'on');
    # readingsEndUpdate($ledDevice, 1);
    
  }
  return undef;
}
sub
LedController_ParseSetHSVColor(@) {

	#my ($param, $err, $data) = @_;
	#my ($ledDevice) = $param->{hash};
	my ($ledDevice, $err, $data) = @_;
	my $res;
	
	Log3 ($ledDevice, 4, "$ledDevice->{NAME}: got HSV color response");
	$ledDevice->{helper}->{isBusy}=0;
	if ($err) {
		Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error $err setting HSV color");
	} elsif ($data) {
		Log3 ($ledDevice, 5, "$ledDevice->{NAME}: HSV color response data $data");
		eval { 
			$res = JSON->new->utf8(1)->decode($data);
		};
		if ($@) {
			Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error decoding HSV color response $@");
		} else {
			#if $res->{success} eq 'true';
		} 
	} else {
		Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error <empty data received> setting HSV color"); 
	}
	return undef;
}

sub
LedController_ParseSetRAWColor(@) {

	#my ($param, $err, $data) = @_;
	#my ($ledDevice) = $param->{hash};
	my ($ledDevice, $err, $data) = @_;
	my $res;
	
	Log3 ($ledDevice, 4, "$ledDevice->{NAME}: got HSV color response");
	$ledDevice->{helper}->{isBusy}=0;
	if ($err) {
		Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error $err setting RAW color");
	} elsif ($data) {
		Log3 ($ledDevice, 5, "$ledDevice->{NAME}: RAW color response data $data");
		eval { 
			$res = JSON->new->utf8(1)->decode($data);
		};
		if ($@) {
			Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error decoding RAW color response $@");
		} else {
			#if $res->{success} eq 'true';
		} 
	} else {
		Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error <empty data received> setting RAW color"); 
	}
	return undef;
}

###############################################################################
#
# queue and send a api call
#
###############################################################################

sub
LedController_addCall(@) {
  my ($ledDevice, $param) = @_;
  
  #Log3 ($ledDevice, 5, "$ledDevice->{NAME}: add to queue: \n\n". Dumper $param);
  
  # add to queue
  push @{$ledDevice->{helper}->{cmdQueue}}, $param;
  
  # return if busy
  return if $ledDevice->{helper}->{isBusy};
  
  # do the call
  LedController_doCall($ledDevice);
  
  return undef;
}

sub
LedController_doCall(@) {
  my ($ledDevice) = @_;
  
  return unless scalar @{$ledDevice->{helper}->{cmdQueue}};
  
  # set busy and do it
  $ledDevice->{helper}->{isBusy} = 1;
  my $param = shift @{$ledDevice->{helper}->{cmdQueue}};
  Log3 ($ledDevice, 5, "$ledDevice->{NAME} send API Call ".Dumper($param));
  usleep(2000);
  HttpUtils_NonblockingGet($param);
  
  return undef;
}

sub
LedController_callback(@) {
  my ($param, $err, $data) = @_;
	my ($ledDevice) = $param->{hash};
	
	# TODO generic error handling
  
  $ledDevice->{helper}->{isBusy} = 0;
  
  # do the result-parser callback
  my $parser = $param->{parser};
  &$parser($ledDevice, $err, $data);
  
  # more calls ?
  LedController_doCall($ledDevice) if scalar @{$ledDevice->{helper}->{cmdQueue}};
  
  return undef;
}

###############################################################################
#
# helper functions
#
###############################################################################

sub
LedController_RGB2HSV(@) {
    my ($ledDevice, $r, $g, $b) = @_;
    $r=$r*1023/255;
    $g=$g*1023/255;
    $b=$b*1023/255;

    my ($max, $min, $delta);
    my ($h, $s, $v);

    $max = $r if (($r >= $g) && ($r >= $b));
    $max = $g if (($g >= $r) && ($g >= $b));
    $max = $b if (($b >= $r) && ($b >= $g));
    $min = $r if (($r <= $g) && ($r <= $b));
    $min = $g if (($g <= $r) && ($g <= $b));
    $min = $b if (($b <= $r) && ($b <= $g));

    $v = int(($max / 10.23) + 0.5);
    $delta = $max - $min;

    my $currentHue = ReadingsVal($ledDevice->{NAME}, "hue", 0);
    return ($currentHue, 0, $v) if (($max == 0) || ($delta == 0));

    $s = int((($delta / $max) *100) + 0.5);
    $h = ($g - $b) / $delta if ($r == $max);
    $h = 2 + ($b - $r) / $delta if ($g == $max);
    $h = 4 + ($r - $g) / $delta if ($b == $max);
    $h = int(($h * 60) + 0.5);
    $h += 360 if ($h < 0);
    return $h, $s, $v;
}

sub
LedController_HSV2RGB(@)
{
    my ($hue, $sat, $val) = @_;

    if ($sat == 0) {
        return int(($val * 2.55) +0.5), int(($val * 2.55) +0.5), int(($val * 2.55) +0.5);
    }
    $hue %= 360;
    $hue /= 60;
    $sat /= 100;
    $val /= 100;

    my $i = int($hue);

    my $f = $hue - $i;
    my $p = $val * (1 - $sat);
    my $q = $val * (1 - $sat * $f);
    my $t = $val * (1 - $sat * (1 - $f));

    my ($r, $g, $b);

    if ( $i == 0 ) {
        ($r, $g, $b) = ($val, $t, $p);
    } elsif ( $i == 1 ) {
        ($r, $g, $b) = ($q, $val, $p);
    } elsif ( $i == 2 ) {
        ($r, $g, $b) = ($p, $val, $t);
    } elsif ( $i == 3 ) {
        ($r, $g, $b) = ($p, $q, $val);
    } elsif ( $i == 4 ) {
        ($r, $g, $b) = ($t, $p, $val);
    } else {
        ($r, $g, $b) = ($val, $p, $q);
    }
    return (int(($r * 255) +0.5), int(($g * 255) +0.5), int(($b * 255) + 0.5));
}

sub
LedController_ArgsHelper(@) {
	my ($ledDevice, $a, $b) = @_;	
	Log3 ($ledDevice, 5, "$ledDevice->{NAME} extended args raw: a=$a, b=$b");
	my $t = AttrVal($ledDevice->{NAME}, 'defaultRamp',0);
	Log3 ($ledDevice, 5, "$ledDevice->{NAME} t= $t");
	my $q = 'false';
	my $d = '1';
	if(LedController_isNumeric($a)){
		$t=$a*1000;
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} a is numeric ($a), t= $t");
			if ($b ne ''){
				$q = ($b =~m/.*[qQ].*/)?'true':'false';
				$d = ($b =~m/.*[lL].*/)?0:1;
			}		
		}else{
			$q = ($a =~m/.*[qQ].*/)?'true':'false';
			$d = ($a =~m/.*[lL].*/)?0:1;
		}
	Log3 ($ledDevice, 5, "$ledDevice->{NAME} extended args: t = $t, q = $q, d = $d");
	return ($t, $q, $d);
}

sub LedController_isNumeric{
 defined $_[0] && $_[0] =~ /^[+-]?\d+.?\d*$/;
}

1;

=begin html

<a name="LedController"></a>
<h3>LedController</h3>
<ul>
<b>Define</b>
<code>define <name> LedController [<type>] <ip-or-hostname></code>
<b>Set</b>
TBD
<b>Get</b>
TBD
</ul>

=end html

=begin html_DE

<a name="LedController"></a>
<h3>LedController</h3>
<ul>
<b>Define</b>
<code>define <name> LedController [<type>] <ip-or-hostname></code>
<b>Set</b>
TBD
<b>Get</b>
TBD
</ul>

=end html_DE

