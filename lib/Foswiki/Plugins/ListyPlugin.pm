# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# ListyPlugin is Copyright (C) 2015-2025 Michael Daum http://michaeldaumconsulting.com
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
use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Contrib::JsonRpcContrib ();
use Foswiki::Plugins::RenderPlugin ();

our $VERSION = '6.00';
our $RELEASE = '%$RELEASE%';
our $SHORTDESCRIPTION = 'Fancy list manager';
our $LICENSECODE = '%$LICENSECODE%';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean

=cut

sub initPlugin {

  Foswiki::Plugins::JQueryPlugin::registerPlugin("Listy", 'Foswiki::Plugins::ListyPlugin::JQuery');
  
  Foswiki::Func::registerTagHandler('LISTY', sub {
    return getCore(shift)->LISTY(@_);
  });

  Foswiki::Func::registerTagHandler('FAVBUTTON', sub {
    return getCore(shift)->FAVBUTTON(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod(
    "ListyPlugin",
    "saveListyItem",
    sub {
      my $session = shift;
      return getCore($session)->jsonRpcSaveListyItem(@_);
    }
  );

  Foswiki::Contrib::JsonRpcContrib::registerMethod(
    "ListyPlugin",
    "deleteListyItem",
    sub {
      my $session = shift;
      return getCore($session)->jsonRpcDeleteListyItem(@_);
    }
  );

  Foswiki::Contrib::JsonRpcContrib::registerMethod(
    "ListyPlugin",
    "saveListy",
    sub {
      my $session = shift;
      return getCore($session)->jsonRpcSaveListy(@_);
    }
  );

  Foswiki::Func::registerRESTHandler(
    'importSideBar',
    sub {
      my $session = shift;
      return getCore($session)->restImportSideBar(@_);
    },
    authenticate => 1,
    validate => 0,
    http_allow => 'GET,POST',
  );

  if ($Foswiki::Plugins::VERSION > 2.0) {
    my $metaDataName = $Foswiki::cfg{ListyPlugin}{MetaData} || 'LISTY';
    Foswiki::Func::registerMETA($metaDataName, 
      alias => lc($metaDataName), 
      many => 1,
      ignoreSolrIndex => 1, # prevent MetaDataPlugin from indexing LISTY metadata as we index it by ourselves
      form => $Foswiki::cfg{SystemWebName}.".ListyForm"
    );
  }

  if (exists $Foswiki::cfg{Plugins}{SolrPlugin} && $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
    Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(sub {
      return getCore()->solrIndexTopicHandler(@_);
    });
  }

  # rest handler required for javascript metadata view interface
  Foswiki::Plugins::RenderPlugin::registerAllowedTag("LISTY");

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
  my $session = shift || $Foswiki::Plugins::SESSION;

  unless (defined $core) {
    require Foswiki::Plugins::ListyPlugin::Core;
    $core = new Foswiki::Plugins::ListyPlugin::Core($session);
  } else {
    $core->init($session);
  }

  return $core;
}

1;
