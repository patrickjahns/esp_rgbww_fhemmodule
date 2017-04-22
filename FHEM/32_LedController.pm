##############################################
# $Id: 32_LedController.pm 0 2016-05-01 12:00:00Z herrmannj $

# TODO
# I'm fully aware of this http://xkcd.com/1695/
#  
# * timer driven updates - InternalTimer(gettimeofday()+0.2, LedController_...
#   -> start as soon as an animation is started
#   -> stop when h,s,v have not changed for one timer cycle (we don't want to waste cycles when the lights are static)
#   -> use the blocking update method in the feature_stop branch, check for issues with using blocking and non blocking http calls
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
use Time::HiRes qw(time);
use JSON;
use JSON::XS;
use Data::Dumper;
use Color;

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

sub
LedController_Initialize(@) {

  my ($hash) = @_;

  $hash->{DefFn}                = 'LedController_Define';
  $hash->{UndefFn}              = 'LedController_Undef';
  $hash->{ShutdownFn}           = 'LedController_Undef';
  $hash->{SetFn}                = 'LedController_Set';
  $hash->{GetFn}                = 'LedController_Get';
  $hash->{AttrFn}               = 'LedController_Attr';
  $hash->{NotifyFn}             = 'LedController_Notify';
  $hash->{ReadFn}               = 'LedController_Read';
  $hash->{AttrList}     = "defaultRamp defaultColor defaultHue defaultSat defaultVal colorTemp "
  								 ."outputMode hsvModel biasRed biasYellow biasGreen biasCyan biasBlue biasMagenta "
  								 ."brightnessRed brightnessGreen brightnessBlue brightnessWW brightnessCW "
  								 ."colorTempWW colorTempCW"
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

  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def); 
  my $name = $a[0];
  
  $hash->{IP} = $a[2];
  
  @{$hash->{helper}->{cmdQueue}} = ();
  $hash->{helper}->{isBusy} = 0;
  $hash->{helper}->{shouldStop} = 0;
  LedController_UpdateLogLevel($hash);
  # TODO remove, fixeg loglevel 5 only for debugging
  #$attr{$hash->{NAME}}{verbose} = 5;
  LedController_GetInfo($hash);
  
  #Log3($hash, 5,"$name: ".Dumper($hash));
  LedController_PushConfig($hash);
  
  $hash->{helper}->{oldVal}	  = 100;
  return undef;
  return "wrong syntax: define <name> LedController <type> <ip-or-hostname>" if(@a != 4);  
  return "$hash->{LEDTYPE} is not supported at $hash->{CONNECTION} ($hash->{IP})";
}

sub
LedController_Undef(@) {
  return undef;
}

sub
LedController_UpdateLogLevel(@) {
  my ($hash) = @_;
  $hash->{helper}->{logLevel} = (AttrVal($hash->{NAME},"verbose",0)>$attr{global}{verbose})?AttrVal($hash->{NAME},"verbose",0):$attr{global}{verbose};
  return undef;
}

sub
LedController_Set(@) {

	my ($hash, $name, $cmd, @args) = @_;
  
	return "Unknown argument $cmd, choose one of hsv rgb state update hue sat stop val dim dimup dimdown on off rotate raw ct" if ($cmd eq '?');

    LedController_UpdateLogLevel($hash);
    Log3($hash,4, "\nglobal LogLevel: $attr{global}{verbose}\nmodule LogLevel: ".AttrVal($hash->{NAME},'verbose',0)."\ncompound LogLevel: $hash->{helper}->{logLevel}");	
	# $colorTemp :  ColorTemp in Kelvin, can be set through an ATTR or by the set ct command. Values are between 2000 and 10000k
	# Note: rangeCheck is performed in attr method, so a simple AttrVal with 2700 as default value is enough here.
    # fetch it from Readings, if Readings are not provided, fetch it from Attr, otherwise default to 2700.
    # I'm not 100% sure if this is the right way round, since when it's in the Readings, the Attribute won't overwrite...
    # Alas, when we read the Attribute first, the module will default back to them whenever. 
	my $colorTemp = ReadingsVal($hash->{NAME},'ct',AttrVal($hash->{NAME},'colorTemp',2700));
	
	
	Log3 ($hash, 5, "$hash->{NAME} (Set) called with $cmd, busy flag is $hash->{helper}->{isBusy}\n name is $name, args ".Dumper(@args)) if ($hash->{helper}->{logLevel}>=5);
	Log3 ($hash, 3, "$hash->{NAME} (Set) called with $cmd, busy flag is $hash->{helper}->{isBusy}");  

	# $fadeTime: Duration of the color change in ms
	# $doQueue (true|false): Should this operation be queued or executed directly on the controller?
	# $direction: Take the short route on HSV for the transition (0) or the long one (1)
	# SHUZZ: These arguments may be added to any set command here, therefore we can decode them now.
    my $fadeTime;
    my $doQueue;
    my $direction;
	if ($cmd eq 'on' || $cmd eq 'off' || $cmd eq "pause"){
        ($fadeTime, $doQueue, $direction) = LedController_ArgsHelper($hash, $args[0], $args[1]);
    } else {
        ($fadeTime, $doQueue, $direction) = LedController_ArgsHelper($hash, $args[1], $args[2]);
    }

	if ($cmd eq 'ct'){
        my $colorTemp=$args[0];#
        if(!LedController_rangeCheck($colorTemp,2000,10000)){
            Log3 ($hash, 3, "$hash->{NAME} colorTemp must be a number from 2000-10000");
            return "$hash->{NAME} colorTemp must be a number from 2000-10000";
        }
		# get current hsv from Readings
	  	my $hue = InternalVal($hash->{NAME}, "hueValue", 0);
		my $val = InternalVal($hash->{NAME}, "valValue", 0);
		my $sat = InternalVal($hash->{NAME}, "satValue", 0);

		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

    }

	if ($cmd eq 'hsv') {
		# expected args: <hue:0-360>,<sat:0-100>,<val:0-100>
		# HSV color values --> $hue, $sat and $val are split from arg1
		my ($hue, $sat, $val) = split ',', $args[0];
		
		if (! LedController_rangeCheck($hue, 0, 360)){
			Log3 ($hash, 3, "$hash->{NAME} HUE must be a number from 0-359");
			return "$hash->{NAME} HUE must be a number from 0-359";
		}
		if (! LedController_rangeCheck($sat, 0, 100)){
			Log3 ($hash, 3, "$hash->{NAME} SAT must be a number from 0-100");
			return "$hash->{NAME} SAT must be a number from 0-100";
		}
		if (! LedController_rangeCheck($val, 0, 100)){
			Log3 ($hash, 3, "$hash->{NAME} VAL must be a number from 0-100");
			return "$hash->{NAME} VAL must be a number from 0-100";
		}
		
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);
   
	} elsif ($cmd eq 'rgb') {
		# the native mode of operation for those controllers is HSV
		# I am converting RGB into HSV and then set that
		# This is to make use of the internal color compensation of the controller
		
		# sanity check, is string in required format?
		if ( ! defined($args[0]) ||  $args[0] !~ /^[0-9A-Fa-f]{6}$/ ){
			Log3 ($hash, 3, "$hash->{NAME} RGB requires parameter: Hex RRGGBB (e.g. 3478DE)");
			return "$hash->{NAME} RGB requires parameter: Hex RRGGBB (e.g. 3478DE)";
		}

		# break down param string into discreet RGB values, also Hex to Int
		my $red = hex(substr($args[0],0,2));
		my $green = hex(substr($args[0],2,2));
		my $blue = hex(substr($args[0],4,2));
		Log3 ($hash, 5, "$hash->{NAME} raw: $args[0], r: $red, g: $green, b: $blue") if ($hash->{helper}->{logLevel} >= 5);
		my ($hue, $sat, $val) = LedController_RGB2HSV($hash, $red, $green, $blue);
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);
		
	} elsif ($cmd eq 'rotate'){
		
		# get rotation value
		my $rotation = $args[0];

		if (! LedController_isNumeric($rotation)){
			Log3 ($hash, 3, "$hash->{NAME} rotation requires a numeric argument.");
			return "$hash->{NAME} rotation requires a numeric argument.";
		}
		
		# get current hsv from Readings
	  	my $hue = InternalVal($hash->{NAME}, "hueValue", 0);
		my $val = InternalVal($hash->{NAME}, "valValue", 0);
		my $sat = InternalVal($hash->{NAME}, "satValue", 0);

		# add rotation to hue and normalize to 0-359
		$hue = ($hue + $rotation)%360;

		Log3 ($hash, 5, "$hash->{NAME} setting HUE to $hue, keeping VAL $val and SAT $sat") if ($hash->{helper}->{logLevel} >= 5);
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);
	  		
	} elsif ($cmd eq 'on') {
		# Add check to only do something if the controller is REALLY turned off, i.e. val eq 0
		my $state = InternalVal($hash->{NAME}, "stateValue", "off");
		return undef if ($state eq "on"); 
		
		# OK, state was off 
		# val initialized from internal value.
		# if internal was 0, default to 100;
		my $val = $hash->{helper}->{oldVal};
		if ($val eq 0){
			$val = 100;
		}
	  	my $hue = InternalVal($hash->{NAME}, "hueValue", 0);
		my $sat = InternalVal($hash->{NAME}, "satValue", 0);
		
		# Load default color from attributes (DEPRECATED)
		my $defaultColor = AttrVal($hash->{NAME},'defaultColor',undef);
		if (defined $defaultColor){
			Log3 ($hash, 2, "$hash->{NAME} attr \"defaultColor\" is deprecated. Please use the new Attrs defaultHue, defaultSat and defaultVal individually."); 

			# Split defaultColor and if all three components pass rangeCheck set them.
			my($dcHue, $dcSat, $dcVal) = split(',',$defaultColor );
			if( LedController_rangeCheck($dcHue, 0, 359) && LedController_rangeCheck($dcSat, 0, 100) && LedController_rangeCheck($dcVal, 0, 100)) {
			# defaultColor values are valid. Overwrite current hue/sat/val.
				$hue = $dcHue;
				$sat = $dcSat;
				$val = $dcVal;
			}
		}

		# defaultHue/Sat/Val will overwrite old values if present because this is "on" cmd.
		my $dHue = AttrVal($hash->{NAME}, "defaultHue", $hue);
		my $dSat = AttrVal($hash->{NAME}, "defaultSat", $sat);
		my $dVal = AttrVal($hash->{NAME}, "defaultVal", $val);
		
		# range/sanity check
		$hue = LedController_rangeCheck($dHue, 0, 359)?$dHue:$hue; 
		$sat = LedController_rangeCheck($dSat, 0, 100)?$dSat:$sat; 
		$val = LedController_rangeCheck($dVal, 0, 100)?$dVal:$val; 
		

		Log3 ($hash, 5, "$hash->{NAME} setting VAL to $val, SAT to $sat and HUE $hue") if ($hash->{helper}->{logLevel} >= 5);
		Log3 ($hash, 5, "$hash->{NAME} args[0] = $args[0], args[1] = $args[1]") if ($hash->{helper}->{logLevel} >= 5);

		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);


	} elsif ($cmd eq 'off') {
		# Store old val in internal for use by on command.
		$hash->{helper}->{oldVal} = ReadingsVal($hash->{NAME}, "val", 0);

		# Now set val to zero, read other values and "turn out the light"...
		my $val = 0;
		my $hue = InternalVal($hash->{NAME}, "hueValue", 0);
		my $sat = InternalVal($hash->{NAME}, "satValue", 0);
		Log3 ($hash, 5, "$hash->{NAME} setting VAL to $val, keeping HUE $hue and SAT $sat") if ($hash->{helper}->{logLevel} >= 5);
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq 'val' || $cmd eq 'dim') {
		
		# Set val from arguments, keep hue and sat the way they were
		my $val = $args[0];
		# input validation
		if( ! LedController_rangeCheck($val, 0, 100)){
			Log3 ($hash, 3, "$hash->{NAME} value must be a number from 0-100");
			return "$hash->{NAME} value must be a number from 0-100";
		}
		
		my $hue = InternalVal($hash->{NAME}, "hueValue", 0);
		my $sat = InternalVal($hash->{NAME}, "satValue", 0);
		Log3 ($hash, 5, "$hash->{NAME} setting VAL to $val, keeping HUE $hue and SAT $sat") if ($hash->{helper}->{logLevel} >= 5);
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);
	        
	} elsif ($cmd eq "dimup") {

		# dimming value is first parameter, add to $val and keep hue and sat the way they were.
		my $dim = $args[0];
		my $val = InternalVal($hash->{NAME}, "valValue", 0);
		$val = $val + $dim;
		
		#sanity check needs to run both ways, dim could be set to -200 and we'd end up with a negative reading.
		$val = ($val<0)?0:($val>100)?100:$val;
		my $hue = InternalVal($hash->{NAME}, "hueValue", 0);
		my $sat = InternalVal($hash->{NAME}, "satValue", 0);
		Log3 ($hash, 5, "$hash->{NAME} dimming VAL by $dim to $val, keeping HUE $hue and SAT $sat") if ($hash->{helper}->{logLevel} >= 5);
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq "dimdown") {

		# dimming value is first parameter, subtract from $val and keep hue and sat the way they were.
		my $dim = $args[0];
		my $val = InternalVal($hash->{NAME}, "valValue", 0);
		$val = $val - $dim;

		#sanity check needs to run both ways, dim could be set to -200 and we'd end up with a negative reading.
		$val = ($val<0)?0:($val>100)?100:$val;
		my $hue = InternalVal($hash->{NAME}, "hueValue", 0);
		my $sat = InternalVal($hash->{NAME}, "satValue", 0);
		Log3 ($hash, 5, "$hash->{NAME} dimming VAL by $dim to $val, keeping HUE $hue and SAT $sat") if ($hash->{helper}->{logLevel} >= 5);
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq 'sat') {
      
		# get new saturation value $sat from args, keep hue and val the way they were.
		my $sat = $args[0];
		# input validation
		if( ! LedController_rangeCheck($sat, 0, 100)){
			Log3 ($hash, 3, "$hash->{NAME} sat value must be a number from 0-100");
			return "$hash->{NAME} sat value must be a number from 0-100";
		}
		
		my $hue = InternalVal($hash->{NAME}, "hueValue", 0);
		my $val = InternalVal($hash->{NAME}, "valValue", 0);
		Log3 ($hash, 5, "$hash->{NAME} setting SAT to $sat, keeping HUE $hue and VAL $val") if ($hash->{helper}->{logLevel} >= 5);
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq 'hue') {
      
		# get new hue value $sat from args, keep sat and val the way they were.
		my $hue = $args[0];
		# input validation
		if( ! LedController_rangeCheck($hue, 0, 359)){
			Log3 ($hash, 3, "$hash->{NAME} hue value must be a number from 0-359");
			return "$hash->{NAME} hue value must be a number from 0-359";
		}
		
		my $val = InternalVal($hash->{NAME}, "valValue", 0);
		my $sat = InternalVal($hash->{NAME}, "satValue", 0);
		Log3 ($hash, 5, "$hash->{NAME} setting HUE to $hue, keeping VAL $val and SAT $sat") if ($hash->{helper}->{logLevel} >= 5);
		Log3 ($hash, 5, "$hash->{NAME} got extended args: t = $fadeTime, q = $doQueue, d=$direction") if ($hash->{helper}->{logLevel} >= 5);
      
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq 'pause'){
	
		# For use in queued fades.
		# Will stay at the current color for $fadetime seconds.
		# NOTE: Does not make sense without $doQueue == "true".
		# TODO: Add a check for queueing = true? Or just execute anyway?
		my $val = InternalVal($hash->{NAME}, "valValue", 0);
		my $hue = InternalVal($hash->{NAME}, "hueValue", 0);
		my $sat = InternalVal($hash->{NAME}, "satValue", 0);
		if ($fadeTime eq 0 || $doQueue eq 'false'){
			Log3 ($hash, 3, "$hash->{NAME} Note: pause only makes sense if fadeTime is > 0 AND if queueing is activated for command!");
		}
		LedController_SetHSVColor($hash, $hue, $sat, $val, $colorTemp, $fadeTime, 'solid', $doQueue, $direction);
		
	} elsif ( $cmd eq 'raw' ) {

		my ($red, $green, $blue, $ww, $cw) = split ',',$args[0];
		LedController_SetRAWColor($hash, $red, $green, $blue, $ww, $cw, $colorTemp, $fadeTime, (($fadeTime==0)?'solid':'fade'), $doQueue, $direction);

	} elsif ($cmd eq 'stop') {
		Log3 ($hash, 4, "$hash->{NAME}: Setting should stop");
		$hash->{helper}->{shouldStop} = 1;
		LedController_GetHSVColor($hash);

	} elsif ($cmd eq 'update') {
		LedController_GetHSVColor($hash);
	}
	return undef;
}


sub
LedController_Get(@) {

  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;
  
  return "Unknown argument $cmd, choose one of config" if ($cmd eq '?');

  Log3($hash, 4, "$hash->{NAME}: get called with cmd: $cmd");
  if ($cmd eq 'config'){
      Log3($hash, 4, "$hash->{NAME}: callign GetInfo");
      LedController_GetConfig($hash);
      }
  return undef;
}

sub
LedController_Attr(@) {

  my ($cmd, $device, $attribName, $attribVal) = @_;
  my $hash = $defs{$device};

  if ($cmd eq 'set' && $attribName eq 'colorTemp'){
  	return "colorTemp must be between 2700 and 6000" if ! LedController_rangeCheck($attribVal, 2000, 10000);
  }
  
  # TODO: Add checks for defaultColor, defaultHue/Sat/Val here!
  Log3 ($hash, 4, "$hash->{NAME} attrib $attribName $cmd $attribVal") if $attribVal && ($hash->{helper}->{logLevel} >= 4); 
  
  LedController_PushConfig($hash);
  return undef;
}

# restore previous settings (as set statefile)
sub
LedController_Notify(@) {

  my ($hash, $eventSrc) = @_;
  my $events = deviceEvents($eventSrc, 1);
  my ($hue, $sat, $val);
}

sub
LedController_GetInfo(@) {

  my ($hash) = @_;
  my $ip = $hash->{IP};
  
  my $param = {
    url        => "http://$ip/info",
    timeout    => 30,
    hash       => $hash,
    method     => "GET",
    header     => "User-Agent: fhem\r\nAccept: application/json",
    parser     =>  \&LedController_ParseInfo,
    callback   =>  \&LedController_callback
  };
  Log3 ($hash, 4, "$hash->{NAME}: get info request") if ($hash->{helper}->{logLevel} >= 4);
  LedController_addCall($hash, $param);
  return undef;
}

sub
LedController_ParseInfo(@) {

  #my ($param, $err, $data) = @_;
  #my ($hash) = $param->{hash};
  my ($hash, $err, $data) = @_;
  my $res;
  
  Log3 ($hash, 4, "$hash->{NAME}: got info response") if ($hash->{helper}->{logLevel} >= 4);
  
  if ($err) {
    Log3 ($hash, 2, "$hash->{NAME}: error $err retriving config");
  } elsif ($data) {
    Log3 ($hash, 5, "$hash->{NAME}: info response data $data") if ($hash->{helper}->{logLevel} >= 5);
    eval { 
    	# TODO: Can't we just store the instance of the JSON parser somewhere?
    	# Would that improve performance???
      $res = JSON->new->utf8(1)->decode($data);
    };
    if ($@) {
     Log3 ($hash, 2, "$hash->{NAME}: error decoding config response $@");
    } else {
      $hash->{DEVICEID} = $res->{deviceid};
      $hash->{FIRMWARE} = $res->{firmware};
      $hash->{MAC} = $res->{connection}->{mac};
      LedController_GetHSVColor($hash);
    } 
  } else {
    Log3 ($hash, 2, "$hash->{NAME}: error <empty data received> retriving config"); 
  }
  return undef;
}

sub
LedController_PushConfig(@){
  my ($hash)=@_;
  
  my $mode=AttrVal($hash->{NAME},"outputMode","");
  if($mode eq "RGB"){
	  $hash->{config}->{outputMode}=0;
  }elsif($mode eq "RGBWW"){
	  $hash->{config}->{outputMode}=1;
  }elsif($mode eq "RGBCW"){
	  $hash->{config}->{outputMode}=2;
  }elsif($mode eq "RGBWWCW"){
	  $hash->{config}->{outputMode}=3;
  }else{
	  return "$mode is not supported by LedController";
  }
  
  my $model=AttrVal($hash->{NAME},'hsvModel',"");
  if($model eq "Normal"){
		$hash->{config}->{hsvModel}=0;  
  }elsif($model eq "Spectrum"){
		$hash->{config}->{hsvModel}=1;  
  }elsif($model eq "Rainbow"){
		$hash->{config}->{hsvModel}=2;  
  }else{
	  return "$model is not supported by LedController";
  }
  
  $hash->{config}->{Bias}->{red}    = AttrVal($hash->{NAME},'biasRed'    ,0);
  $hash->{config}->{Bias}->{yellow} = AttrVal($hash->{NAME},'biasYellow' ,0);
  $hash->{config}->{Bias}->{green}  = AttrVal($hash->{NAME},'biasGreen'  ,0);
  $hash->{config}->{Bias}->{cyan}   = AttrVal($hash->{NAME},'biasCyan'   ,0);
  $hash->{config}->{Bias}->{blue}   = AttrVal($hash->{NAME},'biasBlue'   ,0);
  $hash->{config}->{Bias}->{magenta}= AttrVal($hash->{NAME},'biasMagenta',0);

  $hash->{config}->{Brightness}->{red}   = AttrVal($hash->{NAME},'brightnessRed'   ,100);
  $hash->{config}->{Brightness}->{green} = AttrVal($hash->{NAME},'brightnessGreen' ,100);
  $hash->{config}->{Brightness}->{blue}  = AttrVal($hash->{NAME},'brightnessBlue'  ,100);
  $hash->{config}->{Brightness}->{ww}    = AttrVal($hash->{NAME},'brightnessWW'    ,100);
  $hash->{config}->{Brightness}->{cw}    = AttrVal($hash->{NAME},'brightnessCW'    ,100);

  $hash->{config}->{colorTemp}->{ww}     = AttrVal($hash->{NAME},'colorTempWW',2700);
  $hash->{config}->{colorTemp}->{cw}     = AttrVal($hash->{NAME},'colorTempCW',6000);

  Log3($hash,5,"$hash->{NAME}: pushing config ".Dumper($hash->{config}));
  LedController_SetConfig($hash, $hash->{config});    
}
sub
LedController_GetConfig(@) {

  my ($hash) = @_;
  my $ip = $hash->{IP};
  
  my $param = {
    url        => "http://$ip/config",
    timeout    => 30,
    hash       => $hash,
    method     => "GET",
    header     => "User-Agent: fhem\r\nAccept: application/json",
    parser     =>  \&LedController_ParseConfig,
    callback   =>  \&LedController_callback
  };
  Log3 ($hash, 4, "$hash->{NAME}: get config request") if ($hash->{helper}->{logLevel} >= 4);
  Log3 ($hash, 5, "$hash->{NAME}: config dump:".Dumper($param)) if ($hash->{helper}->{logLevel} >= 5);
  LedController_addCall($hash, $param);
  return undef;
}

sub
LedController_ParseConfig(@) {

  #my ($param, $err, $data) = @_;
  #my ($hash) = $param->{hash};
  my ($hash, $err, $data) = @_;
  my $res;
  
  Log3 ($hash, 4, "$hash->{NAME}: got config response") if ($hash->{helper}->{logLevel} >= 4);
  
  if ($err) {
    Log3 ($hash, 2, "$hash->{NAME}: error $err retriving config");
  } elsif ($data) {
    Log3 ($hash, 5, "$hash->{NAME}: config response data $data") if ($hash->{helper}->{logLevel} >= 5);
    eval { 
    	# TODO: Can't we just store the instance of the JSON parser somewhere?
    	# Would that improve performance???
      $res = JSON->new->utf8(1)->decode($data);
    };
    if ($@) {
     Log3 ($hash, 2, "$hash->{NAME}: error decoding config response $@");
    } else {
      $hash->{config}->{outputMode}     = $res->{color}->{outputmode};
      $hash->{config}->{hsvModel}       = $res->{color}->{hsv}->{model};
      $hash->{config}->{Bias}->{red}    = $res->{color}->{hsv}->{red};
      $hash->{config}->{Bias}->{yellow} = $res->{color}->{hsv}->{yellow};
      $hash->{config}->{Bias}->{green}  = $res->{color}->{hsv}->{green};
      $hash->{config}->{Bias}->{cyan}   = $res->{color}->{hsv}->{cyan};
      $hash->{config}->{Bias}->{blue}   = $res->{color}->{hsv}->{blue};
      $hash->{config}->{Bias}->{magenta}= $res->{color}->{hsv}->{magenta};

      $hash->{config}->{Brightness}->{red}   = $res->{color}->{brightness}->{red};
      $hash->{config}->{Brightness}->{green} = $res->{color}->{brightness}->{green};
      $hash->{config}->{Brightness}->{blue}  = $res->{color}->{brightness}->{blue};
      $hash->{config}->{Brightness}->{ww}    = $res->{color}->{brightness}->{ww};
      $hash->{config}->{Brightness}->{cw}    = $res->{color}->{brightness}->{cw};

      $hash->{config}->{colorTemp}->{ww}     = $res->{color}->{colortemp}->{ww};
      $hash->{config}->{colorTemp}->{cw}     = $res->{color}->{colortemp}->{cw};
      Log3($hash,5,"$hash->{NAME} read ".Dumper($hash->{config}));

      #LedController_GetHSVColor($hash);
      return Dumper($hash->{config});
    } 
  } else {
    Log3 ($hash, 2, "$hash->{NAME}: error <empty data received> retriving config"); 
  }
  return undef;
}

sub
LedController_SetConfig(@) {

  my($hash, $config) = @_;
  Log3 ($hash, 5, "$hash->{NAME}: called SetConfig with".Dumper($config)) if ($hash->{helper}->{logLevel} >= 5);
  my $ip = $hash->{IP};
  my $data; 
  my $cmd;
  
  $cmd->{color}->{outputmode}     = $config->{outputMode}      if defined($config->{outputMode});
  $cmd->{color}->{hsv}->{model}   = $config->{hsvModel}        if defined($config->{hsvModel});
  $cmd->{color}->{hsv}->{red}     = $config->{Bias}->{red}     if defined($config->{Bias}->{red});
  $cmd->{color}->{hsv}->{yellow}  = $config->{Bias}->{yellow}  if defined($config->{Bias}->{yellow});
  $cmd->{color}->{hsv}->{green}   = $config->{Bias}->{green}   if defined($config->{Bias}->{green});
  $cmd->{color}->{hsv}->{cyan}    = $config->{Bias}->{cyan}    if defined($config->{Bias}->{cyan});
  $cmd->{color}->{hsv}->{blue}    = $config->{Bias}->{blue}    if defined($config->{Bias}->{blue});
  $cmd->{color}->{hsv}->{magenta} = $config->{Bias}->{magenta} if defined($config->{Bias}->{magenta});
  
  $cmd->{color}->{brightness}->{red}   = $config->{Brightnes}->{red}   if defined($config->{Brightnes}->{red});
  $cmd->{color}->{brightness}->{green} = $config->{Brightnes}->{green} if defined($config->{Brightnes}->{green});
  $cmd->{color}->{brightness}->{blue}  = $config->{Brightnes}->{blue}  if defined($config->{Brightnes}->{blue});
  $cmd->{color}->{brightness}->{ww}    = $config->{Brightnes}->{ww}    if defined($config->{Brightnes}->{ww});
  $cmd->{color}->{brightness}->{cw}    = $config->{Brightnes}->{cw}    if defined($config->{Brightnes}->{cw});
  
  $cmd->{color}->{colortemp}->{ww} = $config->{colorTemp}->{ww} if defined($config->{colorTemp}->{ww});
  $cmd->{color}->{colortemp}->{cw} = $config->{colorTemp}->{cw} if defined($config->{colorTemp}->{ww});
  
  eval { 
    $data = JSON->new->utf8(1)->encode($cmd);
  };
  if ($@) {
    Log3 ($hash, 2, "$hash->{NAME}: error encoding HSV color request $@");
  } else {
      #Log3 ($hash, 4, "$hash->{NAME}: encoded json data: $data ");
    
    my $param = {
      url        => "http://$ip/config",
      data       => $data,
	  cmd		 => $cmd,
      timeout    => 30,
      hash       => $hash,
      method     => "POST",
      header     => "User-Agent: fhem\r\nAccept: application/json",
      parser     =>  \&LedController_ParseSetHSVColor,
      callback   =>  \&LedController_callback,
      loglevel   => 5
    };
    
    Log3 ($hash, 5, "$hash->{NAME}: set HSV color request \n$param") if ($hash->{helper}->{logLevel}>=5);
    LedController_addCall($hash, $param);  
  }
  return undef;
}

sub
LedController_ParseSetConfig(@) {

	#my ($param, $err, $data) = @_;
	#my ($hash) = $param->{hash};
	my ($hash, $err, $data) = @_;
	my $res;
	
	Log3 ($hash, 4, "$hash->{NAME}: got HSV color response");
	$hash->{helper}->{isBusy}=0;
	if ($err) {
		Log3 ($hash, 2, "$hash->{NAME}: error $err setting HSV color");
	} elsif ($data) {
      eval { 
			$res = JSON->new->utf8(1)->decode($data);
		};
		if ($@) {
			Log3 ($hash, 2, "$hash->{NAME}: error decoding config response $@");
		} 
	} else {
		Log3 ($hash, 2, "$hash->{NAME}: error <empty data received> setting config"); 
	}
	return undef;
}

sub
LedController_GetHSVColor_blocking(@) {

    my ($hash) = @_;
    my $ip = $hash->{IP};
    my $res;
    my $param = {
        url        => "http://$ip/color?mode=HSV",
        timeout    => 2,
        method     => "GET",
        header     => "User-Agent: fhem\r\nAccept: application/json",
    };

    Log3($hash, 4, "$hash->{NAME}: get HSV color request (blocking)");

    my ($err, $data) = HttpUtils_BlockingGet($param);

    Log3($hash, 4, "$hash->{NAME}: got HSV color response (blocking)");

    if ($err) {
        Log3($hash, 2, "$hash->{NAME}: error $err retrieving HSV color");
    } elsif ($data) {
        Log3 ($hash, 5, "$hash->{NAME}: HSV color response data $data") if ($hash->{helper}->{logLevel} >= 5);
        eval { 
            $res = JSON->new->utf8(1)->decode($data);
        };
        if ($@) {
            Log3($hash, 4, "$hash->{NAME}: error decoding HSV color response $@");
        } else {
            LedController_UpdateReadings($hash, $res->{hsv}->{h}, $res->{hsv}->{s}, $res->{hsv}->{v}, $res->{hsv}->{ct});
        } 
    } else {
        Log3($hash, 2, "$hash->{NAME}: error <empty data received> retriving HSV color"); 
    }
    return undef;
}

sub
LedController_GetHSVColor(@) {

my ($hash) = @_;
my $ip = $hash->{IP};

my $param = {
url        => "http://$ip/color?mode=HSV",
timeout    => 30,
hash       => $hash,
method     => "GET",
header     => "User-Agent: fhem\r\nAccept: application/json",
parser     =>  \&LedController_ParseHSVColor,
callback   =>  \&LedController_callback
};
Log3 ($hash, 4, "$hash->{NAME}: get HSV color request");
LedController_addCall($hash, $param);
return undef;
}

sub
LedController_ParseHSVColor(@) {

#my ($param, $err, $data) = @_;
#my ($hash) = $param->{hash};
my ($hash, $err, $data) = @_;
my $res;

Log3 ($hash, 4, "$hash->{NAME}: got HSV color response");

if ($err) {
    Log3 ($hash, 2, "$hash->{NAME}: error $err retriving HSV color");
  } elsif ($data) {
      # Log3 ($hash, 5, "$hash->{NAME}: HSV color response data $data") if ($hash->{helper}->{logLevel} >= 5);
    eval { 
      $res = JSON->new->utf8(1)->decode($data);
    };
    if ($@) {
      Log3 ($hash, 4, "$hash->{NAME}: error decoding HSV color response $@");
    } else {
      LedController_UpdateReadings($hash, $res->{hsv}->{h}, $res->{hsv}->{s}, $res->{hsv}->{v}, $res->{hsv}->{ct});
      if ($hash->{helper}->{shouldStop}) {
        Log3 ($hash, 4, "$hash->{NAME}: Stopping");
        $hash->{helper}->{shouldStop} = 0;
        LedController_SetHSVColor($hash, $res->{hsv}->{h}, $res->{hsv}->{s}, $res->{hsv}->{v}, $res->{hsv}->{ct}, 0, 'solid', 'false', 0);
      }
    } 
  } else {
    Log3 ($hash, 2, "$hash->{NAME}: error <empty data received> retriving HSV color"); 
  }
  return undef;
}

sub
LedController_SetHSVColor(@) {


  my ($hash, $hue, $sat, $val, $colorTemp, $fadeTime, $transitionType, $doQueue, $direction) = @_;
  Log3 ($hash, 5, "$hash->{NAME}: called SetHSVColor $hue, $sat, $val, $colorTemp, $fadeTime, $transitionType, $doQueue, $direction)") if ($hash->{helper}->{logLevel} >= 5);
  my $ip = $hash->{IP};
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
    Log3 ($hash, 2, "$hash->{NAME}: error encoding HSV color request $@");
  } else {
      #Log3 ($hash, 4, "$hash->{NAME}: encoded json data: $data ");
    
    my $param = {
      url        => "http://$ip/color?mode=HSV",
      data       => $data,
	  cmd		 => $cmd,
      timeout    => 30,
      hash       => $hash,
      method     => "POST",
      header     => "User-Agent: fhem\r\nAccept: application/json",
      parser     =>  \&LedController_ParseSetHSVColor,
      callback   =>  \&LedController_callback,
      loglevel   => 5
    };
    
    Log3 ($hash, 5, "$hash->{NAME}: set HSV color request \n$param") if ($hash->{helper}->{logLevel}>=5);
    LedController_addCall($hash, $param);  

    LedController_UpdateReadings($hash, $hue, $sat, $val, $colorTemp);
  }
  return undef;
}

sub
LedController_UpdateReadings(@) {
  my ($hash, $hue, $sat, $val, $colorTemp) = @_;
  my ($red, $green, $blue)=LedController_HSV2RGB($hue, $sat, $val);
  my $xrgb=sprintf("%02x%02x%02x",$red,$green,$blue);
  Log3 ($hash, 5, "$hash->{NAME}: calculated RGB as $xrgb");
  Log3 ($hash, 4, "$hash->{NAME}: begin Readings Update\n   hue: $hue\n   sat: $sat\n   val:$val\n   ct : $colorTemp\n   HSV: $hue,$sat,$val\n   RGB: $xrgb");
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'hue', $hue);
  readingsBulkUpdate($hash, 'sat', $sat);
  readingsBulkUpdate($hash, 'val', $val);
  readingsBulkUpdate($hash, 'ct' , $colorTemp);
  readingsBulkUpdate($hash, 'hsv', "$hue,$sat,$val");
  readingsBulkUpdate($hash, 'rgb', $xrgb);
  readingsBulkUpdate($hash, 'state', ($val== 0)?'off':'on');
  readingsEndUpdate($hash, 1);
  return undef;
}

sub
LedController_SetRAWColor(@) {

    # very crude inital implementation
    # testing only
    #


  my ($hash, $red, $green, $blue, $warmWhite, $coldWhite, $colorTemp, $fadeTime, $transitionType, $doQueue, $direction) = @_;
  Log3 ($hash, 5, "$hash->{NAME}: called SetRAWColor $red, $green, $blue, $warmWhite, $coldWhite, $colorTemp, $fadeTime, $transitionType, $doQueue, $direction");
  
  my $ip = $hash->{IP};
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
    Log3 ($hash, 2, "$hash->{NAME}: error encoding RAW color request $@");
  } else {
      #Log3 ($hash, 4, "$hash->{NAME}: encoded json data: $data ");
    
    my $param = {
      url        => "http://$ip/color?mode=RAW",
      data       => $data,
      timeout    => 30,
      hash       => $hash,
      method     => "POST",
      header     => "User-Agent: fhem\r\nAccept: application/json",
      parser     =>  \&LedController_ParseSetRAWColor,
      callback   =>  \&LedController_callback,
      loglevel   => 5
    };
    
    Log3 ($hash, 4, "$hash->{NAME}: set RAW color request r:$red g:$green b:$blue ww:$warmWhite cw:$coldWhite") if ($hash->{helper}->{logLevel} >= 4);
    Log3 ($hash, 5, "$hash->{NAME}: set RAW color request \n$param") if ($hash->{helper}->{logLevel}>=5);
    LedController_addCall($hash, $param);  
  }
  return undef;
}
sub
LedController_ParseSetHSVColor(@) {

	#my ($param, $err, $data) = @_;
	#my ($hash) = $param->{hash};
	my ($hash, $err, $data) = @_;
	my $res;
	
	Log3 ($hash, 4, "$hash->{NAME}: got HSV color response");
	$hash->{helper}->{isBusy}=0;
	if ($err) {
		Log3 ($hash, 2, "$hash->{NAME}: error $err setting HSV color");
	} elsif ($data) {
        #Log3 ($hash, 5, "$hash->{NAME}: HSV color response data $data") if ($hash->{helper}->{logLevel} >= 5);
		eval { 
			$res = JSON->new->utf8(1)->decode($data);
		};
		if ($@) {
			Log3 ($hash, 2, "$hash->{NAME}: error decoding HSV color response $@");
		} else {
			#if $res->{success} eq 'true';
		} 
	} else {
		Log3 ($hash, 2, "$hash->{NAME}: error <empty data received> setting HSV color"); 
	}
	return undef;
}

sub
LedController_ParseSetRAWColor(@) {

	#my ($param, $err, $data) = @_;
	#my ($hash) = $param->{hash};
	my ($hash, $err, $data) = @_;
	my $res;
	
	Log3 ($hash, 4, "$hash->{NAME}: got HSV color response") if ($hash->{helper}->{logLevel} >= 4);
	$hash->{helper}->{isBusy}=0;
	if ($err) {
		Log3 ($hash, 2, "$hash->{NAME}: error $err setting RAW color");
	} elsif ($data) {
		Log3 ($hash, 5, "$hash->{NAME}: RAW color response data $data") if ($hash->{helper}->{logLevel} >= 5);
		eval { 
			$res = JSON->new->utf8(1)->decode($data);
		};
		if ($@) {
			Log3 ($hash, 2, "$hash->{NAME}: error decoding RAW color response $@");
		} else {
			#if $res->{success} eq 'true';
		} 
	} else {
		Log3 ($hash, 2, "$hash->{NAME}: error <empty data received> setting RAW color"); 
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
  my ($hash, $param) = @_;
  
  Log3 ($hash, 5, "$hash->{NAME}: add to queue: \n\n". Dumper $param) if ($hash->{helper}->{logLevel} >= 5);
  
  # add to queue
  push @{$hash->{helper}->{cmdQueue}}, $param;
  
  # Update internals so next cmd can get correct starting values.
  LedController_doInternalReadingsUpdate($hash, $param->{cmd});
  
  # return if busy
  return if $hash->{helper}->{isBusy};
  
  # do the call
  LedController_doCall($hash);
  
  return undef;
}

sub
LedController_doCall(@) {
  my ($hash) = @_;
  
  return unless scalar @{$hash->{helper}->{cmdQueue}};
  
  # set busy and do it
  $hash->{helper}->{isBusy} = 1;
  my $param = shift @{$hash->{helper}->{cmdQueue}};
  Log3 ($hash, 5, "$hash->{NAME} send API Call ".Dumper($param)) if ($hash->{helper}->{logLevel} >= 5);
  HttpUtils_NonblockingGet($param);
  
  return undef;
}

sub
LedController_callback(@) {
	my ($param, $err, $data) = @_;
	my ($hash) = $param->{hash};

	# TODO generic error handling

	$hash->{helper}->{isBusy} = 0;

	# do the result-parser callback
	my $parser = $param->{parser};
	&$parser($hash, $err, $data);

	# more calls ?
	LedController_doCall($hash) if scalar @{$hash->{helper}->{cmdQueue}};

	# Do readings update
	
	if( ! defined $err || $err eq ""){
		LedController_doReadingsUpdate($hash, $param->{cmd});
	} else {
		Log3 ($hash, 3, "$hash->{NAME} Readings NOT updated, received Error: ".$err);
	}
  
  
  return undef;
}


###############################################################################
#
# helper functions
#
###############################################################################


sub LedController_doInternalReadingsUpdate(@){

	my ($hash, $cmd) = @_;
	
	if( defined $cmd->{hsv}){
		# Must be a setHSV command, let's update the readings...
	    my ($red, $green, $blue)=LedController_HSV2RGB($cmd->{hsv}->{h}, $cmd->{hsv}->{s}, $cmd->{hsv}->{v});
		my $xrgb=sprintf("%02x%02x%02x",$red,$green,$blue);
		my $hsvString = "$cmd->{hsv}->{h},$cmd->{hsv}->{s},$cmd->{hsv}->{v}";
		$hash->{hueValue} = $cmd->{hsv}->{h};
		$hash->{satValue} = $cmd->{hsv}->{s};
		$hash->{valValue} = $cmd->{hsv}->{v};
		$hash->{ctValue} = $cmd->{hsv}->{ct};
		$hash->{hsvValue} = $hsvString;
		$hash->{rgbValue} = $xrgb;
		$hash->{stateValue} = ($cmd->{hsv}->{v}== 0)?'off':'on';
		Log3 ($hash, 3, "$hash->{NAME} DEBUG: Internal hue - helper: ".InternalVal($hash->{NAME}, "hueValue", 0)." and direct: ".$hash->{valValue});  

	} else {
		Log3 ($hash, 3, "$hash->{NAME} DEBUG: doInternalReadingsUpdate: no hsv in cmd hash.");  
	
	}

}


sub LedController_doReadingsUpdate(@){

	my ($hash, $cmd) = @_;
	
	if( defined $cmd->{hsv}){
		# Must be a setHSV command, let's update the readings...
	    my ($red, $green, $blue)=LedController_HSV2RGB($cmd->{hsv}->{h}, $cmd->{hsv}->{s}, $cmd->{hsv}->{v});
		my $xrgb=sprintf("%02x%02x%02x",$red,$green,$blue);
		Log3 ($hash, 4, "$hash->{NAME}: begin Readings Update\n   hue: $cmd->{hsv}->{h}\n   sat: $cmd->{hsv}->{s}\n   val:$cmd->{hsv}->{v}\n   ct : $cmd->{hsv}->{ct}\n   HSV: $cmd->{hsv}->{h},$cmd->{hsv}->{s},$cmd->{hsv}->{v}\n   RGB: $xrgb") if ($hash->{helper}->{logLevel} >= 4);

		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'hue', $cmd->{hsv}->{h}) if (ReadingsVal($hash->{NAME}, "hue",0) != $cmd->{hsv}->{h});
		readingsBulkUpdate($hash, 'sat', $cmd->{hsv}->{s}) if (ReadingsVal($hash->{NAME}, "sat",0) != $cmd->{hsv}->{s});
		readingsBulkUpdate($hash, 'val', $cmd->{hsv}->{v}) if (ReadingsVal($hash->{NAME}, "val",0) != $cmd->{hsv}->{v});
		readingsBulkUpdate($hash, 'ct' , $cmd->{hsv}->{ct}) if (ReadingsVal($hash->{NAME}, "ct",0) != $cmd->{hsv}->{ct});
		my $hsvString = "$cmd->{hsv}->{h},$cmd->{hsv}->{s},$cmd->{hsv}->{v}";
		readingsBulkUpdate($hash, 'hsv', $hsvString) if (ReadingsVal($hash->{NAME}, "hsv",0) ne $hsvString);;
		readingsBulkUpdate($hash, 'rgb', $xrgb) if (ReadingsVal($hash->{NAME}, "rgb",0) ne $xrgb);
		my $newState = ($cmd->{hsv}->{v}== 0)?'off':'on';
		readingsBulkUpdate($hash, 'state', $newState)if (ReadingsVal($hash->{NAME}, "state",0) ne $newState);
		readingsEndUpdate($hash, 1);

	
	} else {
		Log3 ($hash, 3, "$hash->{NAME} DEBUG: doInternalReadingsUpdate: no hsv in cmd hash.");  

	# RAW mode is not yet done.
	# I'll need to think of a way to at least approximate HSV values for this while taking into account WW/CW and so on.
	# Should be doable, but not necessarily correct since RAW has a larger color space than RGB/HSV does.
		
	# Idea: Add WW and CW together in order to get the amount of white light.
	# The way I understand the colorTemp code in the controller, it will calculate white from RGB and then split up the white to WW/CW according to
	# the colortemp. This should be reversable by simply adding them back together.
	# if( (255 - max(r,g,b)) > WWCW)
	#     r += (255 - max(r,g,b));
	#     g += (255 - max(r,g,b));
	#     b += (255 - max(r,g,b));
	# else
	#     r += WWCW;
	#     g += WWCW;
	#     b += WWCW;
	# fi
	# 
	# Now just RGB2HSV and set readings.
	#
	# This would only be an approximation, but should be pretty close I think.
	#
	# NOTE: It would be pretty cool if we knew which mode the controller is running in.
	# e.g. if we knew controller is running in RGB (i.e. no CW/WW strips attached) we could do an exact conversion / ignore the WW/CW values.
		
		
	}
}





sub
LedController_RGB2HSV(@) {
    my ($hash, $red, $green, $blue) = @_;
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

    my $currentHue = InternalVal($hash->{NAME}, "hueValue", 0) + 0;
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
	my ($hash, $a, $b) = @_;	
	Log3 ($hash, 5, "$hash->{NAME} extended args raw: a=$a, b=$b") if ($hash->{helper}->{logLevel} >= 5);
	my $fadeTime = AttrVal($hash->{NAME}, 'defaultRamp',0);
	Log3 ($hash, 5, "$hash->{NAME} t= $fadeTime") if ($hash->{helper}->{logLevel} >= 5);
	my $doQueue = 'false';
	my $d = '1';
    if(defined $a){
        if(LedController_isNumeric($a)){
            $fadeTime=$a*1000;
            Log3 ($hash, 5, "$hash->{NAME} a is numeric ($a), t= $fadeTime") if ($hash->{helper}->{logLevel} >= 5);
                if (defined $b and $b ne ''){
                    $doQueue = ($b =~m/.*[qQ].*/)?'true':'false';
                    $d = ($b =~m/.*[lL].*/)?0:1;
                }		
            }else{
                $doQueue = ($a =~m/.*[qQ].*/)?'true':'false';
                $d = ($a =~m/.*[lL].*/)?0:1;
            }
        }
	Log3 ($hash, 5, "$hash->{NAME} extended args: t = $fadeTime, q = $doQueue, d = $d") if ($hash->{helper}->{logLevel} >= 5);
	return ($fadeTime, $doQueue, $d);
}

sub LedController_isNumeric{
 defined $_[0] && $_[0] =~ /^[+-]?\d+.?\d*/;
}

sub LedController_rangeCheck(@){
	my ($val, $min, $max) = @_;
	return LedController_isNumeric($val) && $val >= $min && $val <= $max;
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
    <code>attr &ltname&gt <b>defaultColor</b> &ltH,S,V&gt DEPRECATED</code><br> 
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
