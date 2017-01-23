# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# ListyPlugin is Copyright (C) 2015-2017 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::ListyPlugin;

use strict;
use warnings;

=begin TML

---+ package ListyPlugin

=cut

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Contrib::JsonRpcContrib ();

our $VERSION = '2.00';
our $RELEASE = '23 Jan 2017';
our $SHORTDESCRIPTION = 'Fancy list manager';
our $NO_PREFS_IN_TOPIC = 1;
our $core;


=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean

=cut

sub initPlugin {

  Foswiki::Func::registerTagHandler('LISTY', \&LISTY);

  Foswiki::Contrib::JsonRpcContrib::registerMethod("ListyPlugin", "saveListyItem", sub {
    my $session = shift;
    return getCore($session)->jsonRpcSaveListyItem(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("ListyPlugin", "deleteListyItem", sub {
    my $session = shift;
    return getCore($session)->jsonRpcDeleteListyItem(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("ListyPlugin", "saveListy", sub {
    my $session = shift;
    return getCore($session)->jsonRpcSaveListy(@_);
  });

  if ($Foswiki::Plugins::VERSION > 2.0) {
    my $metaDataName = $Foswiki::cfg{ListyPlugin}{MetaData} || 'LISTY';
    Foswiki::Meta::registerMETA($metaDataName, alias => lc($metaDataName), many => 1);
  }


  return 1;
}

=begin TML

---++ finishPlugin()

=cut

sub finishPlugin {
  undef $core;
}

=begin TML

---++ getCore()

=cut

sub getCore {
  my $session = shift;

  unless (defined $core) {
    require Foswiki::Plugins::ListyPlugin::Core;
    $core = new Foswiki::Plugins::ListyPlugin::Core($session);
  } else {
    $core->init($session);
  }

  return $core;
}

=begin TML

---++ LISTY($session, $params, $theTopic, $theWeb) -> $string

stub for LISTY to initiate the core before handling the macro

=cut

sub LISTY {
  my $session = shift;
  return getCore($session)->LISTY(@_);
}


1;
