##############################################
# $Id: 32_LedController.pm 0 2016-05-01 12:00:00Z herrmannj $

# TODO

# versions
# 00 POC

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
  $hash->{AttrList}     = "defaultRamp"
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
  return "wrong syntax: define <name> LedController <type> <connection>" if(@a != 4);  
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
  
  return "Unknown argument $cmd, choose one of HSB RGB state update on off" if ($cmd eq '?');

  Log3 ($ledDevice, 5, "$ledDevice->{NAME} called with $cmd ");
  
  if ($cmd eq 'HSB') {

    my ($h, $s, $v) = split ',', $args[0];
    if (defined $args[1]) {
      my $t = $args[1];
      my $q = 'false';
      my $d = 1;
      if (defined $args[2]) {
        $q = ($args[2] =~ m/.*[qQ].*/)?'true':'false';
        $d = ($args[2] =~ m/.*[lL].*/)?0:1;  
      }
      LedController_SetHSBColor($ledDevice, $h, $s, $v, 2700, $t, 'fade', $q, $d);
    } else {
      LedController_SetHSBColor($ledDevice, $h, $s, $v, 2700, 0, 'solid', 'false', 0);
    }
    my ($r, $g, $b)=LedController_HSV2RGB($h, $s, $v);
    my $xrgb=sprintf("%02x%02x%02x",$r,$g,$b);
    print "*** $xrgb";
    readingsBeginUpdate($ledDevice);
    readingsBulkUpdate($ledDevice, 'hue', $h);
    readingsBulkUpdate($ledDevice, 'sat', $s);
    readingsBulkUpdate($ledDevice, 'bri', $v);
    readingsBulkUpdate($ledDevice, 'ct', 2700);
    readingsBulkUpdate($ledDevice, 'HSB', "$h,$s,$v");
    readingsBulkUpdate($ledDevice, 'RGB', $xrgb);
    if($v=0) {
        readingsBulkUpdate($ledDevice, 'state', 'off');
    }else{
        readingsBulkUpdate($ledDevice, 'state', 'on');
    }
    readingsEndUpdate($ledDevice, 1);

  } elsif ($cmd eq 'RGB') {
      # todo:
      # the native mode of operation for those controllers is HSV
      # I am considering to convert RGB into HSV and then set that
      # this would automatically use the color matching that are
      # built in to the firmware.
      #

        print "*** $args[0]\n";
        # my ($r, $g, $b) = split ",", $args[0];
        my $r = hex(substr($args[0],0,2));
        my $g = hex(substr($args[0],2,2));
        my $b = hex(substr($args[0],4,2));

        if (defined $args[1]) {
            my $t = $args[1];
            my $q = 'false';
            my $d = 1;
            if (defined $args[2]) {
                $q = ($args[2] =~ m/.*[qQ].*/)?'true':'false';
                $d = ($args[2] =~ m/.*[lL].*/)?0:1;  
            }
            LedController_SetRGBasHSVColor($ledDevice, $r, $g, $b, 2700, $t, 'fade', $q, $d);
        } else {
            LedController_SetRGBasHSVColor($ledDevice, $r, $g, $b, 2700, 0, 'solid', 'false', 0);
        }

        readingsBeginUpdate($ledDevice);
        if ($r + $g + $g eq 0) {
        readingsBulkUpdate($ledDevice, 'state', 'off');
        }else{
            readingsBulkUpdate($ledDevice, 'state', 'on');
        }
        readingsEndUpdate($ledDevice,1);


  } elsif ($cmd eq 'on') {

      Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting HSV to 60,0,100 ");
      LedController_SetHSBColor($ledDevice, 60,0,100,2700,0,'solid','false',0);

      readingsBeginUpdate($ledDevice);
      readingsBulkUpdate($ledDevice, 'hue', 60);
      readingsBulkUpdate($ledDevice, 'sat', 0);
      readingsBulkUpdate($ledDevice, 'bri', 100);
      readingsBulkUpdate($ledDevice, 'ct', 2700);
      readingsBulkUpdate($ledDevice, 'HSB', "60,0,100");
      readingsBulkUpdate($ledDevice, 'state', 'on');
      readingsEndUpdate($ledDevice, 1);

  } elsif ($cmd eq 'off') {

      Log3 ($ledDevice, 5, "$ledDevice->{NAME} setting HSV to 60,0,0 ");
      LedController_SetHSBColor($ledDevice, 60,0,0,2700,0,'solid','false',0);

      readingsBeginUpdate($ledDevice);
      readingsBulkUpdate($ledDevice, 'hue', 60);
      readingsBulkUpdate($ledDevice, 'sat', 0);
      readingsBulkUpdate($ledDevice, 'bri', 0);
      readingsBulkUpdate($ledDevice, 'ct', 2700);
      readingsBulkUpdate($ledDevice, 'HSB', "60,0,100");
      readingsBulkUpdate($ledDevice, 'state', 'off');
      readingsEndUpdate($ledDevice, 1);

  } elsif ($cmd eq 'update') {
    LedController_GetHSBColor($ledDevice);
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
      LedController_GetHSBColor($ledDevice);
    } 
  } else {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error <empty data received> retriving config"); 
  }
  return undef;
}

sub
LedController_GetHSBColor(@) {

  my ($ledDevice) = @_;
  my $ip = $ledDevice->{IP};
  
  my $param = {
    url        => "http://$ip/color?mode=HSV",
    timeout    => 30,
    hash       => $ledDevice,
    method     => "GET",
    header     => "User-Agent: fhem\r\nAccept: application/json",
    callback   =>  \&LedController_ParseHSBColor
  };
  Log3 ($ledDevice, 4, "$ledDevice->{NAME}: get HSB color request");
  HttpUtils_NonblockingGet($param);
  return undef;
}

sub
LedController_ParseHSBColor(@) {

  my ($param, $err, $data) = @_;
  my ($ledDevice) = $param->{hash};
  my $res;
  
  Log3 ($ledDevice, 4, "$ledDevice->{NAME}: got HSB color response");
  
  if ($err) {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error $err retriving HSB color");
  } elsif ($data) {
    Log3 ($ledDevice, 5, "$ledDevice->{NAME}: HSB color response data $data");
    eval { 
      $res = JSON->new->utf8(1)->decode($data);
    };
    if ($@) {
     Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error decoding HSB color response $@");
    } else {
      my ($r, $g, $b)=LedController_HSV2RGB($res->{hsv}->{h}, $res->{hsv}->{s},$res->{hsv}->{v});
      my $xrgb=sprintf("%02x%02x%02x",$r,$g,$b);
      Log3 ($ledDevice, 5, "$ledDevice->{NAME}: calculated RGB as $xrgb");

      readingsBeginUpdate($ledDevice);
      readingsBulkUpdate($ledDevice, 'hue', $res->{hsv}->{h});
      readingsBulkUpdate($ledDevice, 'sat', $res->{hsv}->{s});
      readingsBulkUpdate($ledDevice, 'bri', $res->{hsv}->{v});
      readingsBulkUpdate($ledDevice, 'ct', $res->{hsv}->{ct});
      readingsBulkUpdate($ledDevice, 'HSB', "$res->{hsv}->{h},$res->{hsv}->{s},$res->{hsv}->{v}");
      readingsBulkUpdate($ledDevice, 'RGB', $xrgb);
      readingsEndUpdate($ledDevice, 1);
    } 
  } else {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error <empty data received> retriving HSB color"); 
  }
  return undef;
}

sub
LedController_SetHSBColor(@) {

  my ($ledDevice, $h, $s, $b, $ct, $t, $c, $q, $d) = @_;
  my $ip = $ledDevice->{IP};
  my $data; 
  my $cmd;
  
  $cmd->{hsv}->{h}  = $h;
  $cmd->{hsv}->{s}  = $s;
  $cmd->{hsv}->{v}  = $b;
  $cmd->{hsv}->{ct} = $ct;
  $cmd->{cmd}       = $c;
  $cmd->{t}         = $t;
  $cmd->{q}         = $q;
  $cmd->{d}         = $d;
  
  eval { 
    $data = JSON->new->utf8(1)->encode($cmd);
  };
  if ($@) {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error encoding HSB color request $@");
  } else {
    print "*** $data \n";
    
    my $param = {
      url        => "http://$ip/color?mode=HSV",
      data       => $data,
      timeout    => 30,
      hash       => $ledDevice,
      method     => "POST",
      header     => "User-Agent: fhem\r\nAccept: application/json",
      callback   =>  \&LedController_ParseSetHSBColor
    };
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: set HSB color request ");
    HttpUtils_NonblockingGet($param);
  }
  return undef;
}

sub
LedController_SetRGBColor(@) {

    my ($ledDevice, $r, $g, $b) =@_;
    my $ip = $ledDevice->{IP};
    my $data;
    my $cmd;

    $cmd->{raw}->{r} = $r;
    $cmd->{raw}->{g} = $g;
    $cmd->{raw}->{b} = $b;
    $cmd->{raw}->{ww} = 0;
    $cmd->{raw}->{cw} = 0;

    eval {
        $data = JSON->new->utf8(1)->encode($cmd);
    };
    if ($@) {
        Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error encoding RGB color request $@");
    } else {
        print "*** $data \n";

        my $param = {
            url     => "http://$ip/color?mode=RAW",
            data    => $data,
            timeout => 30,
            hash    => $ledDevice,
            method  => "POST",
            header     => "User-Agent: fhem\r\nAccept: application/json",
            callback   =>  \&LedController_ParseSetRGBColor
        };
    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: set RGB color request ");
    HttpUtils_NonblockingGet($param);
    }
}

sub LedController_SetRGBasHSVColor(@) {
    my ($ledDevice, $r, $g, $b, $ct, $t, $c, $q, $d)=@_;
    my $ip = $ledDevice->{IP};
    my $data;
    my $cmd;
    my $xrgb=sprintf("%02x%02x%02x", $r, $g, $b);
    my ($h, $s, $v) = LedController_RGB2HSV($ledDevice, $r, $g, $b);

    $cmd->{hsv}->{h}  = $h;
    $cmd->{hsv}->{s}  = $s;
    $cmd->{hsv}->{v}  = $b;
    $cmd->{hsv}->{ct} = $ct;
    $cmd->{cmd}       = $c;
    $cmd->{t}         = $t;
    $cmd->{q}         = $q;
    $cmd->{d}         = $d;
    eval { 
        $data = JSON->new->utf8(1)->encode($cmd);
    };
    if ($@) {
        Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error encoding HSB color request $@");
    } else {
        print "*** $data \n";

        my $param = {
            url        => "http://$ip/color?mode=HSV",
            data       => $data,
            timeout    => 30,
            hash       => $ledDevice,
            method     => "POST",
            header     => "User-Agent: fhem\r\nAccept: application/json",
            callback   =>  \&LedController_ParseSetHSBColor
        };
        Log3 ($ledDevice, 4, "$ledDevice->{NAME}: set HSB color request ");
        Log3 ($ledDevice, 5 , "$ledDevice->{NAME}: coverted r:$r, g:$g, b:$b to $xrgb ");
        HttpUtils_NonblockingGet($param);
        readingsBeginUpdate($ledDevice);
        readingsBulkUpdate($ledDevice, 'hue', $h);
        readingsBulkUpdate($ledDevice, 'sat', $s);
        readingsBulkUpdate($ledDevice, 'bri', $b);
        readingsBulkUpdate($ledDevice, 'ct', 2700);
        readingsBulkUpdate($ledDevice, 'HSB', "$h,$s,$b");
        readingsBulkUpdate($ledDevice, 'RGB', $xrgb);
        if($b=0) {
            readingsBulkUpdate($ledDevice, 'state', 'off');
        }else{
            readingsBulkUpdate($ledDevice, 'state', 'on');
        }
        readingsEndUpdate($ledDevice, 1);

    }
    return undef;
}

sub
LedController_ParseSetRGBColor(@) {
    my ($param, $err, $data) = @_;
    my ($ledDevice) = $param->{hash};
    my $res;

    Log3 ($ledDevice, 4, "$ledDevice->{NAME}: got RGB color response");
  
    if ($err) {
        Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error $err setting RGB color");
    } elsif ($data) {
        Log3 ($ledDevice, 5, "$ledDevice->{NAME}: RGB color response data $data");
        eval { 
            $res = JSON->new->utf8(1)->decode($data);
        };
        if ($@) {
            Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error decoding RGB color response $@");
        } else {
          #if $res->{success} eq 'true';
        } 
    } else {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error <empty data received> setting RGB color"); 
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
LedController_ParseSetHSBColor(@) {

my ($param, $err, $data) = @_;
my ($ledDevice) = $param->{hash};
my $res;

Log3 ($ledDevice, 4, "$ledDevice->{NAME}: got HSB color response");

if ($err) {
Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error $err setting HSB color");
  } elsif ($data) {
    Log3 ($ledDevice, 5, "$ledDevice->{NAME}: HSB color response data $data");
    eval { 
      $res = JSON->new->utf8(1)->decode($data);
    };
    if ($@) {
     Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error decoding HSB color response $@");
    } else {
      #if $res->{success} eq 'true';
    } 
  } else {
    Log3 ($ledDevice, 2, "$ledDevice->{NAME}: error <empty data received> setting HSB color"); 
  }
  return undef;
}

1;

=begin html

<a name="LedController"></a>
<h3>LedController</h3>
<ul>
</ul>

=end html

=begin html_DE

<a name="LedController"></a>
<h3>LedController</h3>
<ul>
</ul>

=end html_DE
