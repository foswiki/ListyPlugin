# Extension for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# JQuery MetaCommentPlugin is Copyright (C) 2021-2024 Michael Daum 
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

package Foswiki::Plugins::ListyPlugin::JQuery;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::ListyPlugin ();
use Foswiki::Plugins::JQueryPlugin::Plugin ();
our @ISA = qw( Foswiki::Plugins::JQueryPlugin::Plugin );

sub new {
  my $class = shift;

  my $this = bless(
    $class->SUPER::new(
      name => 'Listy',
      version => $Foswiki::Plugins::ListyPlugin::VERSION,
      author => 'Michael Daum',
      homepage => 'https://foswiki.org/Extensions/ListyPlugin',
      javascript => ['jquery.listy.js', 'jquery.favbutton.js'],
      css => ['jquery.listy.css'],
      puburl => '%PUBURLPATH%/%SYSTEMWEB%/ListyPlugin',
      i18n => '%PUBURLPATH%/%SYSTEMWEB%/ListyPlugin/i18n',
      dependencies => ['ui', 'hoverIntent', 'jsonRpc', 'form', 'pnotify', 'blockui', 'tabpane', 'render', 'ui::tooltip', 'ui::dialog']
    ),
    $class
  );

  return $this;
}

1;
