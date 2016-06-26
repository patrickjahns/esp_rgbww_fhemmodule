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
use JSON;
use Data::Dumper;

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

  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def); 
  my $name = $a[0];
  
  $hash->{IP} = $a[2];
  
  LedController_GetConfig($hash);
  
  $attr{$hash->{NAME}}{verbose} = 5;
  
  return undef;
  return "wrong syntax: define <name> LedController <type> <ip-or-hostname>" if(@a != 4);  
  return "$hash->{LEDTYPE} is not supported at $hash->{CONNECTION} ($hash->{IP})";
}

sub
LedController_Undef(@) {
  return undef;
}

sub
LedController_Set(@) {

  my ($ledDevice, $name, $cmd, @args) = @_;
  my $descriptor = '';
  my $colorTemp = AttrVal($ledDevice->{NAME},'colorTemp',0);
  $colorTemp = ($colorTemp)?$colorTemp:2700;
  return "Unknown argument $cmd, choose one of hsv rgb state update hue sat val dim on off rotate" if ($cmd eq '?');

  Log3 ($ledDevice, 5, "$ledDevice->{NAME} called with $cmd ");  
  
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
  } elsif ($cmd eq 'update') {
    LedController_GetHSVColor($ledDevice);
  }
  return undef;
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

sub
LedController_Get(@) {

  my ($ledDevice, $name, $cmd, @args) = @_;
  my $cnt = @args;
  
  return undef;
}

sub LedController_isNumeric{
 defined $_[0] && $_[0] =~ /^[+-]?\d+.?\d*$/;
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
    callback   =>  \&LedController_ParseConfig
  };
  Log3 ($ledDevice, 4, "$ledDevice->{NAME}: get config request");
  HttpUtils_NonblockingGet($param);
  return undef;
}

sub
LedController_ParseConfig(@) {

  my ($param, $err, $data) = @_;
  my ($ledDevice) = $param->{hash};
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
    callback   =>  \&LedController_ParseHSVColor
  };
  Log3 ($ledDevice, 4, "$ledDevice->{NAME}: get HSV color request");
  HttpUtils_NonblockingGet($param);
  return undef;
}

sub
LedController_ParseHSVColor(@) {

  my ($param, $err, $data) = @_;
  my ($ledDevice) = $param->{hash};
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
      callback   =>  \&LedController_ParseSetHSVColor
    };
    
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: set HSV color request \n$param");

    HttpUtils_NonblockingGet($param);
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
	      if($v==0){
	      	readingsBulkUpdate($ledDevice, 'state', 'off');
	      }else{
	      	readingsBulkUpdate($ledDevice, 'state', 'on');
	      }
	   readingsEndUpdate($ledDevice, 1);
  }
  return undef;
}

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
LedController_ParseSetHSVColor(@) {

my ($param, $err, $data) = @_;
my ($ledDevice) = $param->{hash};
my $res;

Log3 ($ledDevice, 4, "$ledDevice->{NAME}: got HSV color response");

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

1;

=pod
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