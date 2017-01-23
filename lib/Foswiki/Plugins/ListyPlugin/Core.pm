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

package Foswiki::Plugins::ListyPlugin::Core;

use strict;
use warnings;

=begin TML

---+ package ListyPlugin::Core

=cut

use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Contrib::JsonRpcContrib::Error ();
use Foswiki::Func ();
use Error qw(:try);
use JSON ();
use Digest::MD5 qw(md5_hex);
#use Data::Dump qw(dump);

use constant TRACE => 0; # toggle me

=begin TML

---++ writeDebug($message)

prints a debug message to STDERR when this module is in TRACE mode

=cut

sub writeDebug {
  return unless TRACE;
  #Foswiki::Func::writeDebug("ListyPlugin::Core - $_[0]");
  print STDERR "ListyPlugin::Core - $_[0]\n";
}

=begin TML

---++ inlineError($text) -> $html

formats an inline error message

=cut

sub inlineError {
  return "<span class='foswikiAlert'>".$_[0]."</span>";
}

=begin TML

---++ new($class)

constructor for the core

=cut

sub new {
  my $class = shift;
  my $session = shift;

  my $this = bless({
    metaDataName => $Foswiki::cfg{ListyPlugin}{MetaData} || 'LISTY',
    @_
  }, $class);

  $this->readTemplate();

  $this->{format} = Foswiki::Func::expandTemplate("listy::format");
  $this->{header} = Foswiki::Func::expandTemplate("listy::header");
  $this->{footer} = Foswiki::Func::expandTemplate("listy::footer");
  $this->{itemTools} = Foswiki::Func::expandTemplate("listy::item::tools") || '';
  $this->{itemFormat}{topic} = Foswiki::Func::expandTemplate("listy::item::topic") || '';
  $this->{itemFormat}{external} = Foswiki::Func::expandTemplate("listy::item::external") || '';
  $this->{itemFormat}{text} = Foswiki::Func::expandTemplate("listy::item::text") || '';
  $this->{itemFormat}{query} = Foswiki::Func::expandTemplate("listy::item::query") || '';

  return $this->init($session);
}

=begin TML

---++ init($this, $session)

initializes this instance with values of this session

=cut

sub init {
  my ($this, $session) = @_;

  $this->{session} = $session;
  $this->{baseWeb} = $session->{webName};
  $this->{baseTopic} = $session->{topicName};

  return $this;
}

=begin TML

---++ LISTY($this, $params, $theTopic, $theWeb) -> $result

implementation of this macro

=cut

sub LISTY {
  my ($this, $params, $topic, $web) = @_;

  my $wikiName = Foswiki::Func::getWikiName();

  my $theCollection = $params->{_DEFAULT} || $params->{collection} || '';
  my $theHidenull = Foswiki::Func::isTrue($params->{hidenull}, 0);
  my $theTopic = $params->{topic} || $this->{baseTopic};
  my $theCollections = $params->{collections};
  my $theShowCollections = Foswiki::Func::isTrue($params->{showcollections}, defined($theCollections));
  my $theCollectionFormfield = $params->{collection_formfield} || '';
  my $theCollectionValue = $params->{collection_value} || $theCollection;
  my $theReverse = Foswiki::Func::isTrue($params->{reverse}, 0);
  my $theSort = $params->{sort};
  $theSort = "index" if !defined($theSort) || $theSort !~ /^(index|title|summary|date)$/;

  my $theTypes = $params->{type} || $params->{types} ||'text, topic, external';

  my %types = map {$_ => 1} split(/\s*,\s*/, $theTypes);
  my $theAutoSave = Foswiki::Func::isTrue($params->{autosave}, 1) ? 'true':'false';

  my $theWeb;
  ($theWeb, $theTopic) = Foswiki::Func::normalizeWebTopicName($this->{baseWeb}, $theTopic);
  #writeDebug("called LISTY ... web=$theWeb, topic=$theTopic");

  unless (Foswiki::Func::checkAccessPermission('VIEW', $wikiName, undef, $theTopic, $theWeb)) {
    #return inlineError("Access denied to $theWeb.$theTopic");
    return ''; # better be silent instead of clutterish
  }

  my @listyItems = ();

  my $theQuery = $params->{query};
  if ($theQuery) {

    $types{query} = 1; # add query type

    # get listies by converting a topic search result to appropriate structures
    if (Foswiki::Func::getContext()->{DBCachePluginEnabled}) {
      @listyItems = $this->getListyItemsByDBQuery($theWeb, $theTopic, $theQuery);
    } else {
      @listyItems = $this->getListyItemsByQuery($theWeb, $theTopic, $theQuery);
    }

    # set collection explicitly
    foreach my $item (@listyItems) {
      $item->{collection} = $theCollection;
    }

    @listyItems = $this->syncQueryListy($theWeb, $theTopic, $theCollection, \@listyItems);

    #print STDERR "listyItems=".dump(\@listyItems)."\n";
  } else {
    @listyItems = $this->getListyItems($theWeb, $theTopic);
  }

  my %allCollections = ();
  $allCollections{$_->{collection}||''} = 1 foreach @listyItems;

  @listyItems = grep {$_->{collection} eq $theCollection} grep {$types{$_->{type}}} @listyItems;

  if ($theSort eq 'index') {
    @listyItems = sort {$a->{index} <=> $b->{index}} @listyItems;
  } elsif ($theSort eq 'date') {
    @listyItems = sort {$a->{date} <=> $b->{date}} @listyItems;
  } elsif ($theSort eq 'title') {
    @listyItems = sort {$a->{title} cmp $b->{title}} @listyItems;
  } else {
    @listyItems = sort {lc($a->{$theSort}||$a->{topic}||$a->{url}||$a->{title}) cmp lc($b->{$theSort}||$b->{topic})||$b->{url}||$b->{title}} @listyItems;
  }
  @listyItems = reverse @listyItems if $theReverse;

  #print STDERR "listy ($theSort, $theCollection): ".join(',', map {"title=$_->{title}, index=$_->{index}"} @listyItems)."\n";

  my $allowChange = (Foswiki::Func::checkAccessPermission('CHANGE', $wikiName, undef, $theTopic, $theWeb));
  my $itemTools = $allowChange?$this->{itemTools}:'';
  
  my @results = ();
  foreach my $item (@listyItems) {
    my $collection = $item->{collection} || '';
    next if $collection ne $theCollection;

    unless ($item->{name}) {
      print STDERR "WARNING: mal-formed listy: unnamed found at $theWeb.$theTopic, collection=$collection\n";
      next;
    }

    unless (defined($item->{type})) {
      print STDERR "WARNING: mal-formed listy: undefined type in item $item->{name} $theWeb.$theTopic, collection=$collection\n";
      next;
    }

    unless ($item->{type} =~ /^(text|topic|external|query)$/) {
      print STDERR "WARNING: mal-formed listy: unknown type '$item->{type}' in item $item->{name} $theWeb.$theTopic, collection=$collection\n";
      next;
    }

    my $title = '';
    my $class = 'jqListyItem';
    my $summary = $item->{summary} || '';
    my $url = '';

    my $web = $item->{web} || $this->{baseWeb};
    my $topic = $item->{topic} || $this->{baseTopic};
    ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

    if ($item->{type} eq 'topic') {
      $title = $item->{title} || getTopicTitle($item->{web}, $item->{topic});
      $class .= ' jqListyItemTopic';
      $class .= ' foswikiCurrentTopicLink' if $item->{web} && $item->{topic} && $this->{baseWeb} eq $item->{web} && $this->{baseTopic} eq $item->{topic};
      $url = Foswiki::Func::getScriptUrlPath($web, $topic, "view");
    } elsif ($item->{type} eq 'external') {
      $title = $item->{title}||$item->{url};
      $class .= ' jqListyItemExternal';
      $url = $item->{url} || '';
    } elsif ($item->{type} eq 'query') {
      $title = $item->{title} || getTopicTitle($item->{web}, $item->{topic});
      $class .= ' jqListyItemQuery';
      $url = Foswiki::Func::getScriptUrlPath($web, $topic, "view");
    }  else {
      $title = $item->{title};
      $class .= ' jqListyItemText';
    }

    my $itemFormat = $this->_getFormatOfType($params, $item->{type});
    $itemFormat = Foswiki::Func::decodeFormatTokens($itemFormat);
    $itemFormat = Foswiki::Func::expandCommonVariables($itemFormat, $topic, $web);

    my $line = $this->{format};
    
    $line =~ s/\$item\b/$itemFormat/g;
    $line =~ s/\$class\b/$class/g;
    $line =~ s/\$date\b/Foswiki::Func::formatTime($item->{date}/g;
    $line =~ s/\$index\b/$item->{index}+1/ge;
    $line =~ s/\$url\b/$url/g;
    $line =~ s/\$type\b/$item->{type}/g;
    $line =~ s/\$title\b/$title/g;
    $line =~ s/\$topic\b/$topic/g;
    $line =~ s/\$web\b/$web/g;
    $line =~ s/\$name\b/$item->{name}/g;
    $line =~ s/\$summary\b/$summary/g;
    $line =~ s/\$json\b/$this->_formatAsJson($item)/ge;
    push @results, $line;
  }

  my $count = scalar(@results);

  if (!$count) {
    return '' if $theHidenull;
    push @results, "<!-- -->";
  }


  my $topButtons = '';
  my $bottomButtons = '';
  my $buttons = '';
  if (!Foswiki::Func::getContext()->{static} && $allowChange && !defined($theQuery)) {
    $buttons = Foswiki::Func::expandTemplate("listy::buttons");
  }

  if ($params->{buttons}) {
    if ($params->{buttons} eq 'top') {
      $topButtons = $buttons;
      $bottomButtons = '';
    } elsif ($params->{buttons} eq 'both') {
      $topButtons = $buttons;
      $bottomButtons = $buttons;
    } elsif ($params->{buttons} eq 'bottom') {
      $topButtons = '';
      $bottomButtons = $buttons;
    } 
  } else {
    $bottomButtons = $buttons;
  }

  my $style = '';
  my $width = $params->{width};
  if (defined $width) {
    $style = "style='width:$width'";
  }

  my $class = $params->{class} || '';

  my $result = $this->{header}.join("\n", @results).$this->{footer};
  $result =~ s/\$tools\b/$itemTools/g;
  $result =~ s/\$buttons\b/$buttons/g;
  $result =~ s/\$topbuttons\b/$topButtons/g;
  $result =~ s/\$bottombuttons\b/$bottomButtons/g;
  $result =~ s/\$sourceweb\b/$theWeb/g;
  $result =~ s/\$sourcetopic\b/$theTopic/g;
  $result =~ s/\$collection\b/$theCollection/g;
  $result =~ s/\$showcollections\b/$theShowCollections?'true':'false'/ge;
  $result =~ s/\$collectionformfield\b/$theCollectionFormfield/g;
  $result =~ s/\$collectionvalue\b/$theCollectionValue/g;
  $result =~ s/\$types\b/$theTypes/g;
  $result =~ s/\$autosave\b/$theAutoSave/g;
  $result =~ s/\$count\b/$count/g;
  $result =~ s/\$style\b/$style/g;
  $result =~ s/\$class\b/$class/g;

  my @md5 = ();
  foreach my $type (keys %types) {
    my $format = $this->_getFormatOfType($params, $type);
    push @md5, '"'.$type.'":"'.md5_hex($format).'"';
  }
  my $html5Data = "data-formatter-md5='{".join(", ", @md5)."}'" ;
  $result =~ s/\$html5data/$html5Data/g;

  my $allCollections = defined($theCollections)?$theCollections:join(",", sort keys %allCollections);
  $result =~ s/\$allcollections/$allCollections/g;


  #writeDebug("all collections in $theWeb.$theTopic: $allCollections");

  my $listyId = "jqListyId".int(rand(1000));
  $result =~ s/\$listyId/$listyId/g;

  # only add the gui if we are allowed to make changes
  my $origTml = '';
  if ($allowChange) {
    Foswiki::Plugins::JQueryPlugin::createPlugin("i18n");
    Foswiki::Plugins::JQueryPlugin::createPlugin("ui");
    Foswiki::Plugins::JQueryPlugin::createPlugin("hoverIntent");
    Foswiki::Plugins::JQueryPlugin::createPlugin("jsonrpc");
    Foswiki::Plugins::JQueryPlugin::createPlugin("form");
    Foswiki::Plugins::JQueryPlugin::createPlugin("pnotify");
    Foswiki::Plugins::JQueryPlugin::createPlugin("blockui");
    Foswiki::Plugins::JQueryPlugin::createPlugin("tabpane");
    Foswiki::Plugins::JQueryPlugin::createPlugin("render");
    Foswiki::Func::addToZone("script", "LISTY::PLUGIN", <<'HERE', "JQUERYPLUGIN::PNOTIFY, JQUERYPLUGIN::UI, JQUERYPLUGIN::HOVERINTENT, JQUERYPLUGIN::JSONRPC, JQUERYPLUGIN::FORM, JQUERYPLUGIN::BLOCKUI, JQUERYPLUGIN::RENDER, JQUERYPLUGIN::I18N");
<script type="text/javascript" src="%PUBURLPATH%/%SYSTEMWEB%/ListyPlugin/jquery.listy.js"></script> 
HERE

    $origTml = _entityEncode('%LISTY{'.$params->stringify.'}%');
    $origTml = '<div class="jqListyTml" style="display:none">'.$origTml.'</div>';
  }

  Foswiki::Func::addToZone("head", "LISTY::PLUGIN", <<'HERE', "JQUERYPLUGIN::UI");
<link rel="stylesheet" href="%PUBURLPATH%/%SYSTEMWEB%/ListyPlugin/jquery.listy.css" media="all" />
HERE

  # open matching localization file if it exists
  my $langTag = $this->{session}->i18n->language();

  my $messagePath = $Foswiki::cfg{SystemWebName} .'/ListyPlugin/i18n/' . $langTag . '.js';
  my $messageFile = $Foswiki::cfg{PubDir} . '/' . $messagePath;
  if (-f $messageFile) {
      Foswiki::Func::addToZone('script', "LISTYPLUGIN::I8N", <<"HERE", 'JQUERYPLUGIN::I18N');
<script type='application/l10n' data-i18n-language='$langTag' data-i18n-namespace='LISTY' src='$Foswiki::cfg{PubUrlPath}/$messagePath'></script>
HERE
  }

  $result =~ s/\$tml\b/$origTml/g;

  return $result;
}

sub _getFormatOfType {
  my ($this, $params, $type) = @_;

  my $format = $this->{itemFormat}{$type} || '<span class=\'$class\'>$title</span>';
  $format = $params->{format} if defined $params->{format};
  $format = $params->{$type."_format"} if defined $params->{$type."_format"};

  return $format;
}

sub json {
  my $this = shift;

  unless (defined $this->{json}) {
    $this->{json} = JSON->new->pretty(TRACE)->convert_blessed(1);
  }

  return $this->{json};
}

sub _formatAsJson {
  my ($this, $item) = @_;

  return "{}" unless $item;

  my %copy = map {$_ => _entityEncode($item->{$_})} keys %$item;
  return $this->json->encode(\%copy);
}

sub _entityEncode {
  my $text = shift;

  if (defined $text) {
    $text =~ s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&\$'*<=>@\]_\|])/'&#'.ord($1).';'/ge;
  }

  return $text;
}

sub _entityDecode {
  my $text = shift;

  if (defined $text) {
    $text =~ s/&#(\d+);/chr($1)/ge;
  }

  return $text;
}

=begin TML

---++ getListyItems($web, $topic) -> @listyItems

returns all listy items stored in the given topic

=cut

sub getListyItems {
  my ($this, $web, $topic, $meta) = @_;

  #writeDebug("getListyItems($web, $topic)");

  ($meta) = Foswiki::Func::readTopic($web, $topic) unless $meta;
  
  my @listyItems = $meta->find($this->{metaDataName});

  #writeDebug("found ".scalar(@listyItems));

  return @listyItems;
}

=begin TML

---++ getListyItemsByQuery($web, $topic, $query) -> @listyItems

returns a list of items by query

=cut

sub getListyItemsByQuery {
  my ($this, $web, $topic, $query) = @_;

  #writeDebug("getListyItemsByQuery($web, $topic, $query)");
  my @listyItems = ();

  my $matches = Foswiki::Func::query($query, undef, { 
    web => $web, 
    files_without_match => 1 
  });

  my $i = 0;
  while ($matches->hasNext) {
    my $webtopic = $matches->next;
    my ($w, $t) = Foswiki::Func::normalizeWebTopicName('', $webtopic);
    my $item = _getListyFromTopic($w, $t);
    if (defined $item) {
      $item->{index} = $i;
      $item->{type} = 'query';
      push @listyItems, $item;
      $i++;
    }
  }

  #writeDebug("found $i");

  return @listyItems;
}

=begin TML

---++ getListyItemsByDBQuery($web, $topic, $query) -> @listyItems

returns a list of items by query

=cut

sub getListyItemsByDBQuery {
  my ($this, $web, $topic, $query) = @_;

  writeDebug("getListyItemsDBByQuery($web, $topic, $query)");
  my @listyItems = ();

  require Foswiki::Plugins::DBCachePlugin;
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($web);

  my $hits = $db->dbQuery($query, undef, "topictitle");

  my $i = 0;
  while (my $obj = $hits->next) {
    my $t = $obj->fastget("topic");
    my $item = _getListyFromTopic($web, $t);
    if (defined $item) {
      $item->{index} = $i;
      $item->{type} = 'query';
      push @listyItems, $item;
      $i++;
    }
  }

  writeDebug("found $i");

  return @listyItems;
}

=begin TML

---++ syncQueryListy($web, $topic, $collection, $queryItems) -> @items

=cut

sub syncQueryListy {
  my ($this, $web, $topic, $collection, $queryItems) = @_;

  my @listyItems = $this->getListyItems($web, $topic);
  @listyItems = grep {$_->{collection} eq $collection} @listyItems;

  return @$queryItems unless @listyItems;

  my %indexes = ();
  foreach my $item (@listyItems) {
    $indexes{$item->{web}.'.'.$item->{topic}} = {
      index => $item->{index},
      name => $item->{name}
    };
  }

  my %seen = ();
  foreach my $item (@$queryItems) {
    # propagate index and id to query listy
    my $i = $indexes{$item->{web}.'.'.$item->{topic}};
    next unless $i;
    $item->{index} = $i->{index};
    $item->{name} = $i->{name};

    # remember seen query items
    $seen{$item->{name}} = 1;
  }

if (0) {
  # remove unseen query items from listy items 
  my $needsSave = 0;
  my $meta;
  foreach my $item (@listyItems) {
    unless ($seen{$item->{name}}) {
      #writeDebug("item $item->{name} not seen anymore ... removing");
      ($meta) = Foswiki::Func::readTopic($this->{baseWeb}, $this->{baseTopic}) unless $meta;
      $meta->remove($this->{metaDataName}, $item->{name});
      $needsSave = 1;
    }
  }

  Foswiki::Func::saveTopic($this->{baseWeb}, $this->{baseTopic}, $meta, undef, {ignorepermissions=>1});
}

  return @$queryItems;
}

=begin TML

---++ jsonRpcSaveListyItem($this, $request) 

=cut

sub jsonRpcSaveListyItem {
  my ($this, $request) = @_;

  my $wikiName = Foswiki::Func::getWikiName();

  writeDebug("called jsonRpcSaveListyItem(), topic=$this->{baseWeb}.$this->{baseTopic}, wikiName=$wikiName");

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $this->{baseWeb}.$this->{baseTopic} does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("CHANGE", $wikiName, undef, $this->{baseTopic}, $this->{baseWeb});

  my $collection = $request->param("collection");
  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Unknown listy collection")
    unless defined $collection;

  writeDebug("collection=$collection");

  my ($meta) = Foswiki::Func::readTopic($this->{baseWeb}, $this->{baseTopic});

  my $newListy = _getListyFromRequest($request);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1003, "Can't get listy from request")
    unless defined $newListy;

  if ($newListy->{name}) {
    # merge
    my $currentListy = $meta->get($this->{metaDataName}, $newListy->{name});
    $newListy = _mergeListies($newListy, $currentListy);
  } else {
    # new
    $newListy->{name} = "id".int(rand(1000)).time();
    $newListy->{index} = $this->getMaxIndex($meta, $collection) unless defined $newListy->{index} && $newListy->{index} ne '';
  }

  $meta->putKeyed($this->{metaDataName}, $newListy);

  Foswiki::Func::saveTopic($this->{baseWeb}, $this->{baseTopic}, $meta, undef, {ignorepermissions=>1});

  return $newListy;
}

sub _getListyFromRequest {
  my ($request, $name) = @_;

  #print STDERR "request: ".dump($request)."\n";

  $name = $request->param("name") unless defined $name;
  return unless defined ($name);

  my $item = {
    date => time(),
    name => $name,
    collection => _entityDecode($request->param("collection")),
    summary => _entityDecode($request->param("summary")),
    title => _entityDecode($request->param("title")),
    web => _entityDecode($request->param("listyWeb")),
    topic => _entityDecode($request->param("listyTopic")),
    type => _entityDecode($request->param("type")),
    url => _entityDecode($request->param("url")),
    index => _entityDecode($request->param("index")),
  };

  #print STDERR "item from request:".dump($item)."\n";

  return $item;
}

sub _getListyFromTopic {
  my ($web, $topic, $meta) = @_;

  ($meta) = Foswiki::Func::readTopic($web, $topic) unless $meta;

  my $info = $meta->getRevisionInfo();

  my $summary = $meta->get("FIELD", "Summary");
  $summary = $summary->{value} if defined $summary;
  my $title = $meta->get("FIELD", "TopicTitle") || $meta->getPreference("TOPICTITLE");
  $title = $title->{value} if defined $title;

  my $item = {
    date => $info->{date},
    name => "id".int(rand(1000)).time(),
    collection => undef,
    summary => $summary,
    title => $title,
    web => $web,
    topic => $topic,
    type => "topic",
    index => 0,
  };

  return $item;
}

sub _getListyFromJson {
  my ($request, $name) = @_;

  $name = $request->param("name") unless defined $name;
  return unless defined ($name);

  my $item = $request->param($name);

  #print STDERR "before json:".dump($item)."\n";

  foreach my $key (keys %$item) {
    my $val = _entityDecode($item->{$key}, 1);
    $item->{$key} = $val;
  }

  $item->{date} = time();
  $item->{name} = $name;

  #print STDERR "after json:".dump($item)."\n";

  return $item;
}

sub _mergeListies {
  my ($targetListy, $sourceListy) = @_;

  return $targetListy unless defined $sourceListy;

  $targetListy->{title} = $sourceListy->{title} unless defined $targetListy->{title};
  $targetListy->{summary} = $sourceListy->{summary} unless defined $targetListy->{summary};
  $targetListy->{index} = $sourceListy->{index};

  if ($targetListy->{type} eq 'topic') {
    $targetListy->{web} = $sourceListy->{web} unless defined $targetListy->{web};
    $targetListy->{topic} = $sourceListy->{topic} unless defined $targetListy->{topic};
  } elsif ($targetListy->{type} eq 'external') {
    $targetListy->{url} = $sourceListy->{url} unless defined $targetListy->{url};
  }

  return $targetListy;
}

=begin TML

---++ jsonRpcDeleteListyItem($this, $request) 

=cut

sub jsonRpcDeleteListyItem {
  my ($this, $request) = @_;

  my $wikiName = Foswiki::Func::getWikiName();

  writeDebug("called jsonRpcDeleteListyItem(), topic=$this->{baseWeb}.$this->{baseTopic}, wikiName=$wikiName");

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $this->{baseWeb}.$this->{baseTopic} does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("CHANGE", $wikiName, undef, $this->{baseTopic}, $this->{baseWeb});

  my $name = $request->param("name");
  throw Foswiki::Contrib::JsonRpcContrib::Error(1001, "Unknown listy") 
    unless defined $name;

  my ($meta) = Foswiki::Func::readTopic($this->{baseWeb}, $this->{baseTopic});
  my $item = $meta->get($this->{metaDataName}, $name);
  
  throw Foswiki::Contrib::JsonRpcContrib::Error(1001, "Unknown listy $name") 
    unless defined $item;

  $meta->remove($this->{metaDataName}, $name);

  Foswiki::Func::saveTopic($this->{baseWeb}, $this->{baseTopic}, $meta, undef, {ignorepermissions=>1});

  return;
}

=begin TML

---++ jsonRpcSaveListy($this, $request) 

=cut

sub jsonRpcSaveListy {
  my ($this, $request) = @_;

  my $wikiName = Foswiki::Func::getWikiName();

  writeDebug("called jsonRpcSaveListy(), topic=$this->{baseWeb}.$this->{baseTopic}, wikiName=$wikiName");

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $this->{baseWeb}.$this->{baseTopic} does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("CHANGE", $wikiName, undef, $this->{baseTopic}, $this->{baseWeb});

  my ($meta) = Foswiki::Func::readTopic($this->{baseWeb}, $this->{baseTopic});
  my $sorting = $request->param("sorting");

  throw Foswiki::Contrib::JsonRpcContrib::Error(1002, "Unknown sorting") 
    unless defined $sorting;

  writeDebug("sorting=$sorting");

  my $collection = $request->param("collection");
  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Unknown listy collection")
    unless defined $collection;
  writeDebug("collection=$collection");

  my $collectionFormfield = $request->param("collectionFormfield") || '';
  writeDebug("collectionFormfield=$collectionFormfield") if $collectionFormfield;

  my $collectionValue = $request->param("collectionValue") || $collection;
  writeDebug("collectionValue=$collectionValue");

  if (Foswiki::Func::getContext->{DBCachePluginEnabled}) {
    #require Foswiki::Plugins::DBCachePlugin;
    Foswiki::Plugins::DBCachePlugin::disableSaveHandler();
  }

  my @sorting = split(/\s*,\s*/, $sorting);
  my %seen = ();
  my $index = 0;
  foreach my $name (@sorting) {
    next unless $name;
    my $newListy = _mergeListies(
      _getListyFromJson($request, $name), 
      $meta->get($this->{metaDataName}, $name)
    );

    #print STDERR "newListy:".dump($newListy)."\n";
    
    $newListy->{index} = $index++;
    $newListy->{collection} = $collection;
    $newListy->{type} = 'topic' if $newListy->{type} eq 'query'; # SMELL: convert moved query items to topic items

    if ( $collectionFormfield
      && $collection
      && $newListy->{type} eq 'topic'
      && defined $newListy->{web}
      && defined $newListy->{topic})
    {
      writeDebug("found a collectionField=$collectionFormfield, reading in $newListy->{web}.$newListy->{topic}");
      my ($listyMeta) = Foswiki::Func::readTopic($newListy->{web}, $newListy->{topic});
      my $formfield = $listyMeta->get("FIELD", $collectionFormfield);
      my $needsSave = 0;
      if (defined $formfield) {
        writeDebug("... topic=$newListy->{topic} old formfield value=$formfield->{value}");
        if ($formfield->{value} ne $collectionValue) {
          $needsSave = 1;
          $formfield->{value} = $collectionValue;
        }
      } else {
        writeDebug("... new formfield in $newListy->{topic}");
        $listyMeta->put('FIELD', {name => $collectionFormfield, title => $collectionFormfield, value => $collectionValue});
        $needsSave = 1;
      }
      writeDebug("changing formfield $collectionFormfield of " . $newListy->{web} . "." . $newListy->{topic} . " to $collectionValue") if $needsSave;
      Foswiki::Func::saveTopic($newListy->{web}, $newListy->{topic}, $listyMeta) if $needsSave;
    }

    $seen{$newListy->{name}} = 1;

    $meta->putKeyed($this->{metaDataName}, $newListy);
  }

  # remove unseen listy of this collection 
  foreach my $item ($meta->find($this->{metaDataName})) {
    next if $seen{$item->{name}} || $item->{collection} ne $collection;

    writeDebug("removing listy name=$item->{name}, ".
               "url=".($item->{url}||'').", ".
               "web=".($item->{web}||'').", ".
               "topic=".($item->{topic}||'').", ".
               "title=$item->{title} from collection=$item->{collection}");

    $meta->remove($this->{metaDataName}, $item->{name});
  }

  writeDebug("saving $this->{baseWeb}.$this->{baseTopic}");

  Foswiki::Func::saveTopic($this->{baseWeb}, $this->{baseTopic}, $meta, undef, {ignorepermissions=>1});

  if (Foswiki::Func::getContext->{DBCachePluginEnabled}) {
    Foswiki::Plugins::DBCachePlugin::enableSaveHandler();

    writeDebug("reloading db cache for $this->{baseWeb}");
    my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{baseWeb}); 
    $db->load(2) if $db;
  }

  return;
}


=begin TML

---++ getMaxIndex($meta, $collection) -> $index

create the index of the last entry

=cut

sub getMaxIndex {
  my ($this, $meta, $theCollection) = @_;

  $theCollection ||= '';

  my @listyItems = $meta->find($this->{metaDataName});
  my $maxIndex = 0;
  foreach my $item (@listyItems) {
    my $collection = $item->{collection} || '';
    next if $collection ne $theCollection;
    my $index = int($item->{index});
    $maxIndex = $index if $index > $maxIndex;
  }

  $maxIndex++;

  return $maxIndex;
}

=begin TML

get topic title either by using DBCachePlugin if installed or by reading the PREFs hardcore

=cut

sub getTopicTitle {
  my ($web, $topic) = @_;

  if (Foswiki::Func::getContext()->{DBCachePluginEnabled}) {
    require Foswiki::Plugins::DBCachePlugin;
    return Foswiki::Plugins::DBCachePlugin::getTopicTitle($web, $topic);
  } 

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  if ($Foswiki::cfg{SecureTopicTitles}) {
    my $wikiName = Foswiki::Func::getWikiName();
    return $topic
      unless Foswiki::Func::checkAccessPermission('VIEW', $wikiName, $text, $topic, $web, $meta);
  }

  # read the formfield value
  my $title = $meta->get('FIELD', 'TopicTitle');
  if ($title) {
    $title = $title->{value};
  }

  # read the topic preference
  unless ($title) {
    $title = $meta->get('PREFERENCE', 'TOPICTITLE');
    if ($title) {
      $title = $title->{value};
    }
  }

  # read the preference
  unless ($title)  {
    Foswiki::Func::pushTopicContext($web, $topic);
    $title = Foswiki::Func::getPreferencesValue('TOPICTITLE');
    Foswiki::Func::popTopicContext();
  }

  # default to topic name
  $title ||= $topic;

  $title =~ s/\s*$//;
  $title =~ s/^\s*//;

  return $title;
} 

=begin TML

reads the listyplugin templates unless already loaded

=cut

sub readTemplate {
  my $this = shift;

  return if ($this->{doneReadTemplate});
  $this->{doneReadTemplate} = 1;

  my $test = Foswiki::Func::expandTemplate("listy::isloaded") || '';
  return unless $test eq '';

  Foswiki::Func::readTemplate("listyplugin");
}

=begin TML

remove listy items that already exist in other collections

=cut

sub filterExistingListies {
  my ($this, $web, $topic, $listies) = @_;

  my @result = ();

#print STDERR "listies=".dump($listies)."\n";

  if ($listies && @$listies) {
    my %existing = map {$_->{web}.'.'.$_->{topic} => $_} $this->getListyItems($web, $topic);
#print STDERR "existing=".dump(\%existing)."\n";
    foreach my $item (@$listies) {
      push @result, $item unless $existing{$item->{web}.'.'.$item->{topic}};
    }
  }
#print STDERR "result=".dump(\@result)."\n";

  return @result;
}

1;
