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
  #$attr{$ledDevice->{NAME}}{verbose} = 5;
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
  
	return "Unknown argument $cmd, choose one of hsv rgb state update hue sat val dim dimup dimdown on off rotate raw" if ($cmd eq '?');

	my $descriptor = '';	# What's this???
	
	# $colorTemp : Color temperature in Kelvin (K). Can be set in attr. Default 2700K. Used for ???
	my $colorTemp = AttrVal($ledDevice->{NAME},'colorTemp',0);
	$colorTemp = ($colorTemp)?$colorTemp:2700;
	
	
	Log3 ($ledDevice, 5, "$ledDevice->{NAME} (Set) called with $cmd, busy flag is $ledDevice->{helper}->{isBusy}\n name is $name, args ".Dumper(@args));
	Log3 ($ledDevice, 3, "$ledDevice->{NAME} (Set) called with $cmd, busy flag is $ledDevice->{helper}->{isBusy}");  

	# $fadeTime: Duration of the color change in ms
	# $doQueue (true|false): Should this operation be queued or executed directly on the controller?
	# $direction: Take the short route on HSV for the transition (0) or the long one (1)
	# SHUZZ: These arguments may be added to any set command here, therefore we can decode them now.
	my ($fadeTime, $doQueue, $direction) = LedController_ArgsHelper($ledDevice, $args[1], $args[2]);

	
	if ($cmd eq 'hsv') {
		# expected args: <hue:0-360>,<sat:0-100>,<val:0-100>
		# HSV color values --> $hue, $sat and $val are split from arg1
		my ($hue, $sat, $val) = split ',', $args[0];

		# sanity check / range correction. Making sure values are in correct range (see above)
		# TODO: Silently correct values or return an error message?
		$hue = $hue%360;
		$sat = ($sat<0)?0:($sat>100)?100:$sat;
		$val = ($val<0)?0:($val>100)?100:$val;
		
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);
   
	} elsif ($cmd eq 'rgb') {
		# the native mode of operation for those controllers is HSV
		# I am converting RGB into HSV and then set that
		# This is to make use of the internal color compensation of the controller
		
		# sanity check, is string in required format?
		return "RGB is required hex RRGGBB" if (defined($args[0]) && $args[0] !~ /^[0-9A-Fa-f]{6}$/);

		# break down param string into discreet RGB values, also Hex to Int
		my $red = hex(substr($args[0],0,2));
		my $green = hex(substr($args[0],2,2));
		my $blue = hex(substr($args[0],4,2));
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} raw: $args[0], r: $red, g: $green, b: $blue");
		my ($hue, $sat, $val) = LedController_RGB2HSV($ledDevice, $red, $green, $blue);
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);
		
	} elsif ($cmd eq 'rotate'){
		
		# get rotation value
		my $rotation = $args[0];
		
		# get current hsv from Readings
	  	my $hue = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $val = ReadingsVal($ledDevice->{NAME}, "val", 0);
		my $sat = ReadingsVal($ledDevice->{NAME}, "sat", 0);

		# add rotation to hue and normalize to 0-359
		$hue = ($hue + $rotation)%360;

		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting HUE to $hue, keeping VAL $val and SAT $sat");
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);
	  		
	} elsif ($cmd eq 'on') {
		# added an attr "defaultColor" as a h,s,v tupel. This will be used as the default "on" color
		# if you want to keep the hue/sat from before, use "dim" or it's equivalent "val"
		
		# Load default color from attributes
		my $defaultColor=AttrVal($ledDevice->{NAME},'defaultColor',0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} defaultColor: $defaultColor");

		# break down to hue, sat and val components.
		# if color is not set (== 0), default to 0,0,100 (i.e. plain white).
		my ($hue, $sat, $val) = (($defaultColor) eq (0))?(0,0,100):split(',',$defaultColor );
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting VAL to $val, SAT to $sat and HUE $hue");
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} args[0] = $args[0], args[1] = $args[1]");

		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);


	} elsif ($cmd eq 'off') {

		# Not much here, just set val to zero and "turn out the light"...
		# This seems equivalent to "dim 0" or "val 0".
		my $val = 0;
		my $hue = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $sat = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting VAL to $val, keeping HUE $hue and SAT $sat");
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq 'val' || $cmd eq 'dim') {
		
		# Set val from arguments, keep hue and sat the way they were
		my $val = $args[0];
		# input validation
		$val = ($val<0)?0:($val>100)?100:$val;
		
		my $hue = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $sat = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting VAL to $val, keeping HUE $hue and SAT $sat");
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);
	        
	} elsif ($cmd eq "dimup") {

		# dimming value is first parameter, add to $val and keep hue and sat the way they were.
		my $dim = $args[0];
		my $val = ReadingsVal($ledDevice->{NAME}, "val", 0);
		$val = $val + $dim;
		
		#sanity check needs to run both ways, dim could be set to -200 and we'd end up with a negative reading.
		$val = ($val<0)?0:($val>100)?100:$val;
		my $hue = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $sat = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} dimming VAL by $dim to $val, keeping HUE $hue and SAT $sat");
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq "dimdown") {

		# dimming value is first parameter, subtract from $val and keep hue and sat the way they were.
		my $dim = $args[0];
		my $val = ReadingsVal($ledDevice->{NAME}, "val", 0);
		$val = $val - $dim;

		#sanity check needs to run both ways, dim could be set to -200 and we'd end up with a negative reading.
		$val = ($val<0)?0:($val>100)?100:$val;
		my $hue = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $sat = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} dimming VAL by $dim to $val, keeping HUE $hue and SAT $sat");
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq 'sat') {
      
		# get new saturation value $sat from args, keep hue and val the way they were.
		my $sat = $args[0];
		
		# sanity check
		$sat = ($sat<0)?0:($sat>100)?100:$sat;
		
		my $hue = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $val = ReadingsVal($ledDevice->{NAME}, "val", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting SAT to $sat, keeping HUE $hue and VAL $val");
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq 'hue') {
      
		# get new hue value $sat from args, keep sat and val the way they were.
		my $hue = $args[0];
		
		# sanity check
		$hue = $hue%360;
		
		my $val = ReadingsVal($ledDevice->{NAME}, "val", 0);
		my $sat = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting HUE to $hue, keeping VAL $val and SAT $sat");
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} got extended args: t = $fadeTime, q = $doQueue, d=$direction");
      
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq 'pause'){
		my $val = ReadingsVal($ledDevice->{NAME}, "val", 0);
		my $hue = ReadingsVal($ledDevice->{NAME}, "hue", 0);
		my $sat = ReadingsVal($ledDevice->{NAME}, "sat", 0);
		my ($fadeTime, $doQueue, $direction) = LedController_ArgsHelper($ledDevice, $args[0], $args[1]);
		LedController_SetHSVColor($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, 'solid', $doQueue, $direction);
		
	} elsif ( $cmd eq 'raw' ) {

		my ($red, $green, $blue, $ww, $cw) = split ',',$args[0];
		LedController_SetRAWColor($ledDevice, $red, $green, $blue, $ww, $cw, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

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
      # Log3 ($ledDevice, 5, "$ledDevice->{NAME}: HSV color response data $data");
    eval { 
      $res = JSON->new->utf8(1)->decode($data);
    };
    if ($@) {
     Log3 ($ledDevice, 4, "$ledDevice->{NAME}: error decoding HSV color response $@");
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

  my ($ledDevice, $hue, $sat, $val, $colorTemp, $fadeTime, $transitionType, $doQueue, $direction) = @_;
  Log3 ($ledDevice, 5, "$ledDevice->{NAME}: called SetHSVColor $hue, $sat, $val, $colorTemp, $fadeTime, $transitionType, $doQueue, $direction)");
  my $ip = $ledDevice->{IP};
  my $data; 
  my $cmd;
  
  $cmd->{hsv}->{h}  = $hue;
  $cmd->{hsv}->{s}  = $sat;
  $cmd->{hsv}->{v}  = $val;
  $cmd->{hsv}->{ct} = $colorTemp;
  $cmd->{cmd}       = $transitionType;
  $cmd->{t}         = $fadeTime;
  $cmd->{q}         = $doQueue;
  $cmd->{d}         = $direction;
  
  eval { 
    $data = JSON->new->utf8(1)->encode($cmd);
  };
  if ($@) {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error encoding HSV color request $@");
  } else {
      #Log3 ($ledDevice, 4, "$ledDevice->{NAME}: encoded json data: $data ");
    
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
    
    my ($red, $green, $blue)=LedController_HSV2RGB($hue, $sat, $val);
    my $xrgb=sprintf("%02x%02x%02x",$red,$green,$blue);
    Log3 ($ledDevice, 5, "$ledDevice->{NAME}: calculated RGB as $xrgb");
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: begin Readings Update\n   hue: $hue\n   sat: $sat\n   val:$val\n   ct : $colorTemp\n   HSV: $hue,$sat,$val\n   RGB: $xrgb");

    readingsBeginUpdate($ledDevice);
    readingsBulkUpdate($ledDevice, 'hue', $hue);
    readingsBulkUpdate($ledDevice, 'sat', $sat);
    readingsBulkUpdate($ledDevice, 'val', $val);
    readingsBulkUpdate($ledDevice, 'ct' , $colorTemp);
    readingsBulkUpdate($ledDevice, 'hsv', "$hue,$sat,$val");
    readingsBulkUpdate($ledDevice, 'rgb', $xrgb);
    readingsBulkUpdate($ledDevice, 'state', ($val== 0)?'off':'on');
    readingsEndUpdate($ledDevice, 1);
  }
  return undef;
}

sub
LedController_SetRAWColor(@) {

    # very crude inital implementation
    # testing only
    #


  my ($ledDevice, $red, $green, $blue, $warmWhite, $coldWhite, $colorTemp, $fadeTime, $transitionType, $doQueue, $direction) = @_;
  Log3 ($ledDevice, 5, "$ledDevice->{NAME}: called SetRAWColor $red, $green, $blue, $warmWhite, $coldWhite, $colorTemp, $fadeTime, $transitionType, $doQueue, $direction");
  
  my $ip = $ledDevice->{IP};
  my $data; 
  my $cmd;
  
  $cmd->{raw}->{r}  = $red;
  $cmd->{raw}->{g}  = $green;
  $cmd->{raw}->{b}  = $blue;
  $cmd->{raw}->{ww} = $warmWhite;
  $cmd->{raw}->{cw} = $coldWhite;
  $cmd->{raw}->{ct} = $colorTemp;
  $cmd->{cmd}       = $transitionType;
  $cmd->{t}         = $fadeTime;
  $cmd->{q}         = $doQueue;
  $cmd->{d}         = $direction;
  
  eval { 
    $data = JSON->new->utf8(1)->encode($cmd);
  };
  if ($@) {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error encoding RAW color request $@");
  } else {
      #Log3 ($ledDevice, 4, "$ledDevice->{NAME}: encoded json data: $data ");
    
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
    
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: set RAW color request r:$red g:$green b:$blue ww:$warmWhite cw:$coldWhite");
    #Log3 ($ledDevice, 4, "$ledDevice->{NAME}: set RAW color request \n$param");
    LedController_addCall($ledDevice, $param);  
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
        #Log3 ($ledDevice, 5, "$ledDevice->{NAME}: HSV color response data $data");
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

# TODO Refactor into RGB2HSV and RAW2HSV
# 

sub
LedController_RGB2HSV(@) {
    my ($ledDevice, $red, $green, $blue) = @_;
    $red=($red*1023)/255;
    $green=($green*1023)/255;
    $blue=($blue*1023)/255;

    my ($max, $min, $delta);
    my ($hue, $sat, $val);

    $max = $red if (($red >= $green) && ($red >= $blue));
    $max = $green if (($green >= $red) && ($green >= $blue));
    $max = $blue if (($blue >= $red) && ($blue >= $green));
    $min = $red if (($red <= $green) && ($red <= $blue));
    $min = $green if (($green <= $red) && ($green <= $blue));
    $min = $blue if (($blue <= $red) && ($blue <= $green));

    $val = int(($max / 10.23) + 0.5);
    $delta = $max - $min;
	
    my $currentHue = ReadingsVal($ledDevice->{NAME}, "hue", 0) + 0;
    return ($currentHue, 0, $val) if (($max == 0) || ($delta == 0));

    $sat= int((($delta / $max) *100) + 0.5);
    $hue = ($green - $blue) / $delta if ($red == $max);
    $hue = 2 + ($blue - $red) / $delta if ($green == $max);
    $hue = 4 + ($red - $green) / $delta if ($blue == $max);
    $hue = int(($hue * 60) + 0.5);
    $hue += 360 if ($hue < 0);
    return $hue, $sat, $val;
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

    my ($red, $green, $blue);

    if ( $i == 0 ) {
        ($red, $green, $blue) = ($val, $t, $p);
    } elsif ( $i == 1 ) {
        ($red, $green, $blue) = ($q, $val, $p);
    } elsif ( $i == 2 ) {
        ($red, $green, $blue) = ($p, $val, $t);
    } elsif ( $i == 3 ) {
        ($red, $green, $blue) = ($p, $q, $val);
    } elsif ( $i == 4 ) {
        ($red, $green, $blue) = ($t, $p, $val);
    } else {
        ($red, $green, $blue) = ($val, $p, $q);
    }
    return (int(($red * 255) +0.5), int(($green * 255) +0.5), int(($blue * 255) + 0.5));
}

sub
LedController_ArgsHelper(@) {
	my ($ledDevice, $a, $b) = @_;	
	Log3 ($ledDevice, 5, "$ledDevice->{NAME} extended args raw: a=$a, b=$b");
	my $fadeTime = AttrVal($ledDevice->{NAME}, 'defaultRamp',0);
	Log3 ($ledDevice, 5, "$ledDevice->{NAME} t= $fadeTime");
	my $doQueue = 'false';
	my $d = '1';
	if(LedController_isNumeric($a)){
		$fadeTime=$a*1000;
		Log3 ($ledDevice, 5, "$ledDevice->{NAME} a is numeric ($a), t= $fadeTime");
			if ($b ne ''){
				$doQueue = ($b =~m/.*[qQ].*/)?'true':'false';
				$d = ($b =~m/.*[lL].*/)?0:1;
			}		
		}else{
			$doQueue = ($a =~m/.*[qQ].*/)?'true':'false';
			$d = ($a =~m/.*[lL].*/)?0:1;
		}
	Log3 ($ledDevice, 5, "$ledDevice->{NAME} extended args: t = $fadeTime, q = $doQueue, d = $d");
	return ($fadeTime, $doQueue, $d);
}

sub LedController_isNumeric{
 defined $_[0] && $_[0] =~ /^[+-]?\d+.?\d*$/;
}

1;

=begin html

<a name="LedController"></a>
<h3>LedController</h3>
 <ul>
  <p>The module controls the led controller made by patrick jahns.</p> 
    <p>Additional information you will find in the <a href="https://forum.fhem.de/index.php/topic,48918.0.html">forum</a>.</p> 
  <br><br> 
 
  <a name="LedControllerdefine"></a> 
  <b>Define</b> 
  <ul> 
    <code>define &lt;name&gt; LedController [&lt;type&gt;] &lt;ip-or-hostname&gt;</code> 
    <br><br> 
 
      Example: 
      <ul> 
      <code>define LED_Stripe LedController 192.168.1.11</code><br> 
    </ul> 
  </ul> 
  <br> 
   
  <a name="LedControllerset"></a> 
  <b>Set</b> 
  <ul> 
    <li> 
      <p><code>set &lt;name&gt; <b>on</b> [ramp] [q]</code></p> 
      <p>Turns on the device. It is either chosen 100% White or the color defined by the attribute "defaultColor".</p> 
      <p>Advanced options: 
      <ul> 
        <li>ramp</li> 
      </ul> 
      </p> 
      <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
    </li> 
    <li> 
      <p><code>set &lt;name&gt; <b>off</b> [ramp] [q]</code></p> 
      <p>Turns off the device.</p> 
      <p>Advanced options: 
      <ul> 
        <li>ramp</li> 
      </ul> 
      </p> 
      <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
    </li> 
    <li> 
      <p><code>set &lt;name&gt; <b>dim</b> &lt;level&gt; [ramp] [q]</code></p> 
      <p>Sets the brightness to the specified level (0..100).<br /> 
      This command also maintains the preset color even with "dim 0" (off) and then "dim xx" (turned on) at.  
      Therefore, it represents an alternative form to "off" / "on". The latter would always choose the "default color".</p> 
      <p>Advanced options: 
      <ul> 
        <li>ramp</li> 
      </ul> 
        </p> 
        <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
      </li> 
  <li> 
      <p><code>set &lt;name&gt; <b>dimup / dimdown</b> &lt;level&gt; [ramp] [q]</code></p> 
      <p>Increases / decreases the brightness by the given value.<br /> 
      This command also maintains the preset color even with turning it all the way to 0 (off) and back up.  
      <p>Advanced options: 
      <ul> 
        <li>ramp</li> 
      </ul> 
        </p> 
        <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
      </li> 
    <li> 
    <li> 
      <p><code>set &lt;name&gt; <b>hsv</b> &lt;H,S,V&gt; [ramp] [l|q]</code></p> 
          <p>Sets color, saturation and brightness in the HSV color space. If the ramp is specified (as a time in seconds), the module calculates a soft color transition from the current color to the newly set. 
          <ul><i>For example, sets a saturated blue with half brightness:</i><br /><code>set LED_Stripe hsv 240,100,50</code></ul></p> 
          <p>Advanced options: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>l q</li> 
          </ul> 
          </p> 
      </li> 
       
      <li> 
      <p><code>set &lt;name&gt; <b>hue</b> &lt;value&gt; [ramp] [l|q]</code></p> 
          <p>Sets the color angle (0..360) in the HSV color space. If the ramp is specified (as a time in seconds), the module calculates a soft color transition from the current color to the newly set. 
          <ul><i>For example, changing only the hue with a transition of 5 seconds:</i><br /><code>set LED_Stripe hue 180 5</code></ul></p> 
          <p>Advanced options: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>l q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
      <p><code>set &lt;name&gt; <b>sat</b> &lt;value&gt; [ramp] [q]</code></p> 
          <p>Sets the saturation in the HSV color space to the specified value (0..100). If the ramp is specified (as a time in seconds), the module calculates a soft color transition from the current saturation to the newly set. 
          <ul><i>For example, changing only the saturation with a transition of 5 seconds:</i><br /><code>set LED_Stripe sat 60 5</code></ul></p> 
          <p>Advanced options: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
      <p><code>set &lt;name&gt; <b>val</b> &lt;value&gt; [ramp] [q]</code></p> 
          <p>Sets the brightness to the specified value (0..100). It's the same as cmd <b>dim</b>.</p> 
          <p>Advanced options: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
      <p><code>set &lt;name&gt; <b>rotate</b> &lt;angle&gt; [ramp] [l|q]</code></p> 
          <p>Sets the color in the HSV color space by addition of the specified angle to the current color. 
          <ul><i>For example, changing color from current green to blue:</i><br /><code>set LED_Stripe rotate 120</code></ul></p> 
          <p>Advanced options: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>l q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
          <p><code>set &lt;name&gt; <b>rgb</b> &lt;RRGGBB&gt; [ramp] [l|q]</code></p> 
          <p>Sets the color in the RGB color space.<br> 
          Currently RGB values will be converted into HSV to make use of the internal color compensation of the LedController.</p> 
          <p>Advanced options: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>l q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
          <p><code>set &lt;name&gt; <b>update</b></code></p> 
          <p>Gets the current HSV color from the LedController.</p> 
      </li> 
       
      <p><b>Meaning of Flags</b></p> 
      Certain commands (set) can be marked with special flags. 
      <p> 
      <ul> 
        <li>ramp:  
            <ul> 
              Time in seconds for a soft color or brightness transition. The soft transition starts at the currently visible color and is calculated for the specified. 
            </ul> 
        </li> 
        <li>l:  
            <ul> 
              (long). A smooth transition to another color is carried out in the HSV color space on the "long" way. 
              A transition from red to green then leads across magenta, blue, and cyan. 
            </ul> 
        </li> 
        <li>q:  
            <ul> 
              (queue). Commands with this flag are cached in an internal queue of the LedController and will not run before the currently running soft transitions have been processed.  
              Commands without the flag will be processed immediately. In this case all running transitions are stopped immediately and the queue will be cleared. 
            </ul> 
        </li> 
       
  </ul> 
  <br> 
 
  <a name="LedControllerattr"></a> 
  <b>Attributes</b> 
  <ul> 
    <li><a name="defaultColor">defaultColor</a><br> 
    <code>attr &ltname&gt <b>defaultColor</b> &ltH,S,V&gt</code><br> 
    Specify the light color in HSV which is selected at "on". Default is white.</li> 
 
    <li><a name="defaultRamp">defaultRamp</a><br> 
    Time in milliseconds. If this attribute is set, a smooth transition is always implicitly generated if no ramp in the set is indicated.</li> 
 
    <li><a name="colorTemp">colorTemp</a><br> 
    </li> 
  </ul> 
  <p><b>Colorpicker for FhemWeb</b> 
    <ul> 
      <p> 
      In order for the Color Picker can be used in <a href="#FHEMWEB">FhemWeb</a> following attributes need to be set: 
      <p> 
      <li> 
         <code>attr &ltname&gt <b>webCmd</b> rgb</code> 
      </li> 
      <li> 
         <code>attr &ltname&gt <b>widgetOverride</b> rgb:colorpicker,rgb</code> 
      </li> 
    </ul> 
  <br> 
 
</ul> 
 
=end html 

=begin html_DE

<a name="LedController"></a> 
<h3>LedController</h3> 
<ul> 
<p>Dieses Modul steuert den selbst einwickelten LedController von Patrick Jahns.</p> 
    <p>Weitere Informationen hierzu sind im <a href="https://forum.fhem.de/index.php/topic,48918.0.html">Forum</a> zu finden.</p> 
  <br><br> 
 
  <a name="LedControllerdefine"></a> 
  <b>Define</b> 
  <ul> 
    <code>define &lt;name&gt; LedController [&lt;type&gt;] &lt;ip-or-hostname&gt;</code> 
    <br><br> 
 
      Beispiel: 
      <ul> 
      <code>define LED_Stripe LedController 192.168.1.11</code><br> 
    </ul> 
  </ul> 
  <br> 
   
  <a name="LedControllerset"></a> 
  <b>Set</b> 
  <ul> 
    <li> 
      <p><code>set &lt;name&gt; <b>on</b> [ramp] [q]</code></p> 
      <p>Schaltet das device ein. Dabei wird entweder 100% Weiß oder die im Attribut "defaultColor" definierte Farbe gewählt.</p> 
      <p>Erweiterte Parameter: 
      <ul> 
        <li>ramp</li> 
      </ul> 
      </p> 
      <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
    </li> 
    <li> 
      <p><code>set &lt;name&gt; <b>off</b> [ramp] [q]</code></p> 
      <p>Schaltet das device aus.</p> 
      <p>Erweiterte Parameter: 
      <ul> 
        <li>ramp</li> 
      </ul> 
      </p> 
      <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
    </li> 
    <li> 
      <p><code>set &lt;name&gt; <b>dim</b> &lt;level&gt; [ramp] [q]</code></p> 
      <p>Setzt die Helligkeit auf den angegebenen Wert (0..100).<br /> 
      Dieser Befehl behält außerdem die eingestellte Farbe auch bei "dim 0" (ausgeschaltet) und nachfolgendem "dim xx" (eingeschaltet) bei. 
      Daher stellt er eine alternative Form zu "off" / "on" dar. Letzteres würde immer die "defaultColor" wählen.</p> 
      <p>Erweiterte Parameter: 
      <ul> 
        <li>ramp</li> 
      </ul> 
        </p> 
        <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
      <p><code>set &lt;name&gt; <b>dimup / dimdown</b> &lt;value&gt; [ramp] [q]</code></p> 
      <p>Erhöht oder vermindert die Helligkeit um den angegebenen Wert (0..100).<br /> 
      Dieser Befehl behält außerdem die eingestellte Farbe bei.
      <p>Erweiterte Parameter: 
      <ul> 
        <li>ramp</li> 
      </ul> 
        </p> 
        <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
      </li>     <li> 
      <p><code>set &lt;name&gt; <b>hsv</b> &lt;H,S,V&gt; [ramp] [l|q]</code></p> 
          <p>Setzt die Farbe, Sättigung und Helligkeit im HSV Farbraum. Wenn die ramp (als Zeit in Sekunden) angegeben ist, berechnet das Modul einen weichen Farbübergang von der aktuellen Farbe zur neu gesetzten. 
          <ul><i>Beispiel, setzt ein gesättigtes Blau mit halber Helligkeit:</i><br /><code>set LED_Stripe hsv 240,100,50</code></ul></p> 
          <p>Erweiterte Parameter: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>l q</li> 
          </ul> 
          </p> 
      </li> 
       
      <li> 
      <p><code>set &lt;name&gt; <b>hue</b> &lt;value&gt; [ramp] [l|q]</code></p> 
          <p>Setzt den Farbwinkel (0..360) im HSV Farbraum. Wenn die ramp (als Zeit in Sekunden) angegeben ist, berechnet das Modul einen weichen Farbübergang von der aktuellen Farbe zur neu gesetzten. 
          <ul><i>Beispiel, nur Änderung des Farbwertes mit einer Animationsdauer von 5 Sekunden:</i><br /><code>set LED_Stripe hue 180 5</code></ul></p> 
          <p>Erweiterte Parameter: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>l q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
      <p><code>set &lt;name&gt; <b>sat</b> &lt;value&gt; [ramp] [q]</code></p> 
          <p>Setzt die Sättigung im HSV Farbraum auf den übergebenen Wert (0..100). Wenn die ramp (als Zeit in Sekunden) angegeben ist, berechnet das Modul einen weichen Farbübergang von der aktuellen Sättigung zur neu gesetzten. 
          <ul><i>Beispiel, nur Änderung der Sättigung mit einer Animationsdauer von 5 Sekunden:</i><br /><code>set LED_Stripe sat 60 5</code></ul></p> 
          <p>Erweiterte Parameter: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
      <p><code>set &lt;name&gt; <b>val</b> &lt;value&gt; [ramp] [q]</code></p> 
          <p>Setzt die Helligkeit auf den übergebenen Wert (0..100). Dieser Befehl ist identisch zum <b>"dim"</b> Kommando.</p> 
          <p>Erweiterte Parameter: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
      <p><code>set &lt;name&gt; <b>rotate</b> &lt;angle&gt; [ramp] [l|q]</code></p> 
          <p>Setzt den Farbwinkel im HSV Farbraum durch Addition des Übergebenen Wertes auf die aktuelle Farbe. 
          <ul><i>Beispiel, Änderung der Farbe von aktuell Grün auf Blau:</i><br /><code>set LED_Stripe rotate 120</code></ul></p> 
          <p>Erweiterte Parameter: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>l q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
          <p><code>set &lt;name&gt; <b>rgb</b> &lt;RRGGBB&gt; [ramp] [l|q]</code></p> 
          <p>Setzt die Farbe im RGB Farbraum.<br> 
          Aktuell wandelt das Modul den Wert vor dem Senden in einen HSV-Wert um, um die interne Farbkompensation des Led Controllers nutzen zu können.</p> 
          <p>Erweiterte Parameter: 
          <ul> 
              <li>ramp</li> 
          </ul> 
          </p> 
          <p>Flags: 
          <ul> 
              <li>l q</li> 
          </ul> 
          </p> 
      </li> 
      <li> 
          <p><code>set &lt;name&gt; <b>update</b></code></p> 
          <p>Fragt die aktuellen HSV Farbwerte vom Led Controller ab.</p> 
      </li> 
       
      <p><b>Bedeutung der Flags</b></p> 
      Bestimmte Befehle (set) können mit speziellen Flags versehen werden. 
      <p> 
      <ul> 
        <li>ramp:  
            <ul> 
              Zeit in Sekunden für einen weichen Farb- oder Helligkeitsübergang. Der weiche Übergang startet bei der aktuell sichtbaren Farbe und wird zur angegeben berechnet. 
            </ul> 
        </li> 
        <li>l:  
            <ul> 
              (long). Ein weicher Übergang zu einer anderen Farbe wird im Farbkreis auf dem "langen" Weg durchgeführt.</br> 
              Ein Übergang von ROT nach GRÜN führt dann über MAGENTA, BLAU, und CYAN. 
            </ul> 
        </li> 
        <li>q:  
            <ul> 
              (queue). Kommandos mit diesem Flag werden in der (Controller)internen Warteschlange zwischengespeichert und erst ausgeführt nachdem die aktuell laufenden weichen Übergänge 
              abgearbeitet wurden. Kommandos ohne das Flag werden sofort abgearbeitet. Dabei werden alle laufenden Übergänge sofort abgebrochen und die Warteschlange wird gelöscht. 
            </ul> 
        </li> 
       
  </ul> 
  <br> 
 
  <a name="LedControllerattr"></a> 
  <b>Attribute</b> 
  <ul> 
    <li><a name="defaultColor">defaultColor</a><br> 
    <code>attr &ltname&gt <b>defaultColor</b> &ltH,S,V&gt</code><br> 
    HSV Angabe der Lichtfarbe die bei "on" gewählt wird. Standard ist Weiß.</li> 
 
    <li><a name="defaultRamp">defaultRamp</a><br> 
    Zeit in Millisekunden. Wenn dieses Attribut gesetzt ist wird implizit immer ein weicher Übergang erzeugt wenn keine ramp im set angegeben ist.</li> 
 
    <li><a name="colorTemp">colorTemp</a><br> 
    </li> 
  </ul> 
  <p><b>Colorpicker für FhemWeb</b> 
    <ul> 
      <p> 
      Um den Color-Picker für <a href="#FHEMWEB">FhemWeb</a> zu aktivieren müssen folgende Attribute gesetzt werden: 
      <p> 
      <li> 
         <code>attr &ltname&gt <b>webCmd</b> rgb</code> 
      </li> 
      <li> 
         <code>attr &ltname&gt <b>widgetOverride</b> rgb:colorpicker,rgb</code> 
      </li> 
    </ul> 
  <br> 
 
</ul> 
 
=end html_DE 
=cut
