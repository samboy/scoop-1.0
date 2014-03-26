package Scoop;
use strict;

my $DEBUG = 0;

sub get_themed_blocks {
	my $S = shift;
	my %themed_blocks;

	# get themes in order from base (must be a full set of blocks) to specific
	my @themelist = split ( /,\s*/, $S->{THEME} );
	foreach my $theme ( @themelist ) {
		my %theme = $S->get_blocks("$theme");
		%themed_blocks = (%themed_blocks, %theme);
	}

	return %themed_blocks;
}

sub get_blocks {
	my $S = shift;
	my $theme = shift;
	my $time = time();
	my $blocks;
	
	warn "fetching theme $theme" if $DEBUG;
	if ( my $cached = $S->cache->fetch("blocks_$theme") ) {
		return %{$cached};
	}

	warn "Last update was $S->cache->{LAST_UPDATE}->{blocks_$theme}.\nI think it was $S->cache->{DATA}->{'blocks_$theme'}.\nBlocks cache not valid! Doing select\n" if $DEBUG;

	my ($rv, $sth) = $S->db_select({
		WHAT => 'bid, block',
		FROM => 'blocks',
		WHERE => qq|theme="$theme"|,
		DEBUG => $DEBUG});
	while (my $block_record = $sth->fetchrow_hashref()) {
		$blocks->{"$block_record->{bid}"} = $block_record->{block};
#		if ( $S->{UI}->{VARS}->{block_delimiter_comments} ) {
#			# this really messes up the colours and any block that is 
#			# inside an HTML tag, but works everywhere else.
#			# how to make it work with attributes??? 
#			my $comment_start = qq|<!-- begin block $block_record->{bid} -->|;
#			my $comment_end = qq|<!-- end block $block_record->{bid} -->|;
#			$blocks->{$block_record->{bid}} =~ s/^(.)/$comment_start$1/;
#			$blocks->{$block_record->{bid}} =~ s/(.)$/$1$comment_end/;
#		}
	}
	$sth->finish();
	if ( $blocks ) {
		# Set the global cache
		$S->cache->store("blocks_$theme", $blocks);

		# Return value, not reference so that our changes won't infect the global cache
		return %{$blocks};
	} else {
		return;
	}
}

sub get_vars {
	my $S = shift;
	my $time = time();
	
	if (my $cached = $S->cache->fetch_data({resource => 'vars', 
	                                        element => 'VARS'})) {
		return %{$cached};
	}

	my ($rv, $sth) = $S->db_select({
		WHAT => '*',
		FROM => 'vars'});
	
	my $vars;
	if ($rv) {
		while (my $var_record = $sth->fetchrow_hashref) {
			$vars->{$var_record->{name}} = $var_record->{value};
		}
	}
	$sth->finish();

	$S->cache->cache_data({resource => 'vars', 
	                       element => 'VARS', 
	                       data => $vars});
	
	# Return value, not reference so that our changes won't infect the global cache
	return %{$vars};
}

sub get_macros {
# cloned from get_vars above.

	my $S = shift;
	my $time = time();
	
	if (my $cached = $S->cache->fetch_data({resource => 'macros', 
	                                        element => 'MACROS'})) {
		return %{$cached};
	}

	my ($rv, $sth) = $S->db_select({
		WHAT => '*',
		FROM => 'macros'});
	
	my $macros;
	if ($rv) {
		while (my $macro_record = $sth->fetchrow_hashref) {
			$macros->{$macro_record->{name}} = $macro_record->{value};
		}
	}
	$sth->finish();

	$S->cache->cache_data({resource => 'macros', 
	                       element => 'MACROS', 
	                       data => $macros});
	
	# Return value, not reference so that our changes won't infect the global cache
	return %{$macros};
}

sub refresh_ui {
	my $S = shift;
	my $UI = {};
	delete $S->{UI};
	#warn '-> Refreshing UI cache...';
	
	my %blocks = $S->get_blocks();
	my %vars = $S->get_vars();
	
	$UI->{BLOCKS} = \%blocks;
	$UI->{VARS} = \%vars;
	
	$S->{UI} = $UI;
	return $UI;
}

sub interface_prefs {
	my $S = shift;
	my $tool = $S->cgi->param('tool');
	
	unless ($S->{UID} >= 1) {
		$S->{UI}->{BLOCKS}->{CONTENT} = $S->{UI}->{BLOCKS}->{user_prefs_message};
		$S->{UI}->{BLOCKS}->{subtitle} = 'Error!';
		return;
	}
	
	if ($tool eq 'comments') {
		$S->comment_prefs();
	} else {
		$S->display_prefs();
	}
	return;
}

sub display_prefs {
	my $S = shift;
	my $err = '';
			
	$S->{UI}->{BLOCKS}->{subtitle} = 'Display Preferences';
	if ($S->cgi->param('saveprefs')) {
		$err = $S->_save_user_prefs();
	} elsif ($S->cgi->param('resetprefs')) {
		$err = $S->_reset_user_prefs();
	}
	
	my $form = $S->_interface_prefs_form();
	my $page = $S->{UI}->{BLOCKS}->{interface_prefs_main_form};
	$page =~ s/%%nickname%%/$S->{NICK}/g;
	$page =~ s/%%interface_form%%/$form/;
	$page =~ s/%%title_msg%%/$err/g;
	
	$S->{UI}->{BLOCKS}->{CONTENT} = $page;
	
	return;	
}

sub _reset_user_prefs {
	my $S = shift;
	my $err = "Preferences Reset.";
	
	# reset the prefs, so get rid of the following (don't touch subscription stuff)
	my @del_prefs = qw( maxstories maxtitles norm_font_face norm_font_size show_topic time_zone
						imagedir online_cloak start_page spellcheck_default speling
						ad_open_new_win rdf_max_headlines online_cloak displayed_boxes
						rdf_feeds rdf_max_headlines digest comment_commentorder
						comment_commentrating comment_commenttype comment_flat_to
						comment_minimal_to comment_nested_to comment_posttype
						comment_ratingchoice comment_threaded_to dynamic_interface );

	$err .= $S->clear_prefs( \@del_prefs );
	# clear the cached user prefs	
	$S->_set_prefs(1);
	# clear and reset ui prefs
	$S->_set_vars();
	$S->_set_blocks();
	# clear and reset general prefs
	$S->_update_pref_config();
	
	return $err;
}

sub _save_user_prefs {
	my $S = shift;
	my $err;

	my @preflist = (
		"maxstories",
		"maxtitles",
		"textarea_cols",
		"textarea_rows",
		"norm_font_face",
		"norm_font_size",
		"show_topic",
		"time_zone",
		"imagedir",
		"online_cloak",
		"start_page",
		"theme"
		# note that we'll add two below if spellchecking is on
		# and 1 more if use_ads is on
	);

	# Prefs which are handled by checkboxes and thus need to be cleared
	# before being set (since an unchecked box doesn't get entered into the
	# query data)
	my @clear_preflist = (
		"online_cloak",
		"dynamic_interface"
	);

	# return with an error unless maxstories, maxtitles, and norm_font_size
	# are numbers
	my $maxstories 		= $S->cgi->param('maxstories');
	my $maxtitles 		= $S->cgi->param('maxtitles');
	my $norm_font_size 	= $S->cgi->param('norm_font_size');
	my $textarea_cols	= $S->cgi->param('textarea_cols');
	my $textarea_rows	= $S->cgi->param('textarea_rows');
	if (
	  $maxstories     =~ /\D/ ||
	  $maxtitles      =~ /\D/ ||
	  $norm_font_size =~ /\D/ || 
	  $textarea_cols  =~ /\D/ ||
	  $textarea_rows  =~ /\D/
	) {
		$err = "Please use only numbers for Num Stories, Num titles, or Font Size.";
			return $err;
	}

	if (($maxstories >50) || ($maxtitles >50)) {
		$err = "You cannot set your Num Stories or Num titles to more than 50";
		return $err;
	} 

	if (($textarea_cols < 1) || ($textarea_rows < 1)) {
		$err = "Text area height and width must be greater than 0";
		return $err;
	}

	if ($S->spellcheck_enabled()) {
		push(@preflist, "spellcheck_default", "speling");
		my $speling = $S->cgi->param('speling');
		if (
		  $speling ne "american" &&
		  $speling ne "british"  &&
		  $speling ne "canadian"
		) {
			$err = "Please select a correct spelling variant.";
			return $err;
		}

		$S->param->{spellcheck_default} = 0 unless
		$S->cgi->param('spellcheck_default');
	}

	if ($S->{UI}->{VARS}->{use_ads}) {
		push(@preflist, "ad_open_new_win");
		push(@preflist, "story_ad_position");
		if ($S->have_perm('ad_opt_out')) {
			push(@preflist, "showad");
		}
	}

	if ($S->{UI}->{VARS}->{allow_dynamic_comment_mode}) {
		push(@preflist, "dynamic_interface");
	}

	# build the hash of prefs to update
	my $newprefs = {};
	foreach my $pref (@clear_preflist) {
		$newprefs->{$pref} = '';
	}
	foreach my $pref (@preflist) {
		#my $val = $S->{DBH}->quote(scalar $S->cgi->param($pref));
		my $val = scalar $S->cgi->param($pref);
		next unless (defined($val) && ($val ne 'NULL'));
		$newprefs->{$pref} = $val;
	}

	# update all the new prefs
	$err .= $S->pref( $newprefs );

	# update boxes
	my $box_value;
	while (my($k, $v) = each %{ $S->{BOX_DATA} }) {
		next unless $v->{user_choose};
		next if $S->{CGI}->param("box_$k");
		$box_value .= ',' if $box_value;
		$box_value .= $k;
	}
	# if they don't want any boxes, put something in so that we don't use
	# the default of showing all boxes.
	# rusty: The default *should* be showing all boxes!
	#$box_value = ',' unless $box_value;

	$S->clear_prefs( 'displayed_boxes' );
	if( $box_value ) {
		$err .= $S->pref( 'displayed_boxes', $box_value );
	}

	if ($err) {
		$err = "DB error : $err";
	} else {
		$err = "Preferences Updated.";
	}

	# now update the RDF feeds
	if ($S->{UI}->{VARS}->{use_rdf_feeds}) {
		my @rids;
		my $channels = $S->rdf_channels();
		foreach my $c (@{$channels}) {
			push(@rids, $c->{rid}) if $S->{CGI}->param("rdf_$c->{rid}");
		}
		$S->rdf_set_prefs(\@rids);

		my $max_titles = $S->{CGI}->param('max_rdf_titles');
		return "Please use only a number for the maximum headlines" if $max_titles =~ /\D/;

		$S->clear_prefs('rdf_max_headlines');
		my $tmp_err = $S->pref('rdf_max_headlines', $max_titles);
		if (defined $tmp_err) {
			$err .= "<br />DB error: $tmp_err";
		}
	}

	$S->_set_prefs(1);
	$S->_set_vars();
	$S->_set_blocks();
	$S->_update_pref_config();

	return $err;
}

sub _interface_prefs_form {
	my $S = shift;
	
	my $zone_select = $S->_timezone_list();
	my $topic_img_select = $S->_topic_img_select();
	my $image_server_select = $S->_image_server_select();
	my $rdf_feed_checks = $S->_rdf_feed_checks();
	my $box_toggles = $S->_user_box_toggles();
	my $spellcheck_toggle = $S->_spellcheck_toggles();
	my $start_page_select = $S->_start_page_select();
	my $ad_open_select = $S->_ad_open_select();
	my $ad_setting = $S->ad_select(); 
	my $story_ad_pos_select = $S->_story_ad_pos_select();
	my $textarea_cols = $S->{prefs}->{textarea_cols} || $S->{UI}->{VARS}->{default_textarea_cols};
	my $textarea_rows = $S->{prefs}->{textarea_rows} || $S->{UI}->{VARS}->{default_textarea_rows}; 
	my $theme_select = $S->_theme_list();

	$ad_open_select = '' unless( $S->{UI}->{VARS}->{use_ads} == 1);
	$story_ad_pos_select = '' unless( $S->{UI}->{VARS}->{use_ads} == 1);
	
	my $cloaked = $S->{prefs}->{online_cloak} ? ' checked="checked"' : '';
	my $dyn = $S->{prefs}->{dynamic_interface} ? ' checked="checked"' : '';

	my $form = qq|
		<form name="intpref" method="post" action="%%rootdir%%/">
		<input type="hidden" name="op" value="interface" />
		<input type="hidden" name="tool" value="prefs" />
		<table width="100%" border="0" cellpadding="3" cellspacing="0">
		<tr valign="top">
			<td>%%norm_font%%<b>Your time zone:</B>%%norm_font_end%%</td>
			<td>%%norm_font%% $zone_select %%norm_font_end%%</td>
		</tr>
		<tr valign="top">
			<td>%%norm_font%%<b>Number of story summaries to show:<br />(on main page)</b>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="text" size="5" name="maxstories" value="$S->{UI}->{VARS}->{maxstories}" />%%norm_font_end%%</td>
		</tr>
		<tr valign="top">
			<td>%%norm_font%%<b>Number of story titles to show:<br />(in "older stories" box)</b>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="text" size="5" name="maxtitles" value="$S->{UI}->{VARS}->{maxtitles}" />%%norm_font_end%%</td>
		</tr>
		<tr valign="top">
			<td>%%norm_font%%<b>Text box width:</B>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="text" size="5" name="textarea_cols" value="$textarea_cols" />%%norm_font_end%%</td>
		</tr>
		<tr valign="top">
			<td>%%norm_font%%<b>Text box height:</b>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="text" size="5" name="textarea_rows" value="$textarea_rows" />%%norm_font_end%%</td>
		</tr>
		<tr valign="top">
			<td>%%norm_font%%<b>Font Face:</b>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="text" size="30" name="norm_font_face" value="$S->{UI}->{BLOCKS}->{norm_font_face}" />%%norm_font_end%%</td>
		</tr>
		<tr valign="top">
			<td>%%norm_font%%<b>Font Size:</b>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="text" size="5" name="norm_font_size" value="$S->{UI}->{BLOCKS}->{norm_font_size}" />%%norm_font_end%%</td>
		</tr>
		$ad_open_select
		$story_ad_pos_select
		$ad_setting		
		<tr valign="top">
			<td>%%norm_font%%<b>Show topic images with stories?</b>%%norm_font_end%%</td>
			<td>%%norm_font%% $topic_img_select %%norm_font_end%%</td>
		</tr>
		$start_page_select
		<tr valign="top">
			<td>%%norm_font%%<b>Hide yourself in the Who's Online box?</b>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="checkbox" name="online_cloak"$cloaked />%%norm_font_end%%</td>
		</tr>|;
	if($S->{UI}->{VARS}->{allow_dynamic_comment_mode}) {
		$form .= qq|
		<tr valign="top">
			<td>%%norm_font%%<b>Use dynamic interface elements?</b>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="checkbox" name="dynamic_interface"$dyn />%%norm_font_end%%</td>
		</tr>|;
	}
	if ($S->{UI}->{VARS}->{allow_user_themes} ) {
		$form .= qq|
		<tr valign="top">
			<td>%%norm_font%%<b>Use which theme?</b>%%norm_font_end%%</td>
			<td>%%norm_font%% $theme_select %%norm_font_end%%</td>
		</tr>|;
	}
	$form .= qq|
		$spellcheck_toggle
		$image_server_select
		$box_toggles
		$rdf_feed_checks
		<tr valign="top">
			<td>%%norm_font%%<input type="submit" name="saveprefs" value="Save Preferences" />%%norm_font_end%%</td>
			<td align="right">%%norm_font%%<input type="submit" name="resetprefs" value="Reset to Defaults" />%%norm_font_end%%</td>
		</tr>
		</table>
		</form>|;

	return $form;
}

sub _topic_img_select {
	my $S = shift;
	my @choices = ("Yes", "No");
	my $curr = $S->{prefs}->{show_topic} || "Yes";
	
	my $select = qq|
		<select name="show_topic" size="1">|;
	my $selected = '';
	foreach my $choice (@choices) {
		if ($choice eq $curr) {
			$selected = ' selected="selected"';
		} else {
			$selected = '';
		}
		$select .= qq|
			<option value="$choice"$selected>$choice</option>|;
	}
	$select .= qq|
		</select>|;
	
	return $select;
}

sub _timezone_list {
	my $S = shift;
	my %zones = $S->_timezone_hash();
	
	my $S_zone = $S->{prefs}->{time_zone} || $S->{UI}->{VARS}->{time_zone};
	my $select = qq|
		<select name="time_zone" size="1">|;
	
	my ($selected, $z);
	foreach my $zone (sort keys %zones) {
		$z = uc($zone);
		if ($z eq $S_zone) {
			$selected = ' selected="selected"';
		} else {
			$selected= '';
		}
		$select .= qq|
			<option value="$z"$selected>[$z] $zones{$zone}</option>|;
	}
	
	$select .= qq|
		</select>|;
	
	return $select;
}

# select box of themes available to the user to choose
sub _theme_list {
	my $S = shift;

	my $themes = $S->{UI}->{VARS}->{user_themes};
	warn "user_themes are $themes" if $DEBUG;
	my @themes = split ( /,\s*/, $themes );
	my $S_theme = $S->{prefs}->{theme} || $S->{UI}->{VARS}->{user_theme_default};
	warn "selected theme is $S_theme" if $DEBUG;

	my $select = qq| <select name="theme">\n|;
	unless ( $S->{UI}->{VARS}->{user_theme_default} ) {
		my $selected = ' selected="selected"' unless $S_theme;
		$select .= qq|<option value=""$selected>none</option>\n|;
	}
	foreach my $th ( @themes ) {
		my $selected = "";
		if ( $th eq $S_theme ) {
			$selected = ' selected="selected"';
		}
		$select .= qq|<option value="$th"$selected>$th</option>\n|;
		warn "theme $th is $selected" if $DEBUG;
	}
	$select .= qq| </select>\n|;

	return $select;
}

sub _image_server_select {
	my $S = shift;
	my $form = '';
	return $form unless $S->CONFIG->{image_mirrors};
	
	my $S_image_serv = $S->{prefs}->{imagedir};
	
	# Ok, we can't trust that UI->VARS will have he real default imagedir,
	# Since we might have reset it already. So get the real default
	# out of the DB.
	my ($rv, $sth) = $S->db_select({
		WHAT => 'value',
		FROM => 'vars',
		WHERE=> 'name = "imagedir"'
	});
	
	my $default_imagedir = $sth->fetchrow();
	$sth->finish;
	
	$form = qq|
	<tr valign="top">
		<td>%%norm_font%%<b>Preferred image server:</b>%%norm_font_end%%</td>
		<td>%%norm_font%%<select name="imagedir" size="1"><option value="$default_imagedir">Default</option>|;
	
	my $server_str = $S->{CONFIG}->{image_mirrors};
	my %servers = split /\s*(?:=>|,)\s*/, $server_str;

	foreach my $server (sort keys %servers) {
		my $selected = '';
		if ($S_image_serv eq $servers{$server}) {
			$selected = ' selected="selected"';
		}
		$form .= qq|
			<option value="$servers{$server}"$selected>$server</option>|;
	}
	
	$form .= qq|
		</select>%%norm_font_end%%
		</td>
	</tr>|;
	
	return $form;
}
		
# Zones copied out of Time::Timezone
sub _timezone_hash {
	my $S = shift;
	my %zones = (
		"adt" 	=>	"Atlantic Daylight",
		"edt" 	=>	"Eastern Daylight",
		"cdt" 	=>	"Central Daylight",
		"mdt" 	=>	"Mountain Daylight",
		"pdt" 	=>	"Pacific Daylight",
		"ydt" 	=>	"Yukon Daylight",
		"hdt" 	=>	"Hawaii Daylight",
		"bst" 	=>	"British Summer",
		"mest"	=>	"Middle European Summer",
		"sst" 	=>	"Swedish Summer",
		"fst" 	=>	"French Summer",
		"wadt"	=>	"West Australian Daylight",
		"eadt"	=>	"Eastern Australian Daylight",
		"nzdt"	=>	"New Zealand Daylight",
		"gmt"	=>	"Greenwich Mean",
		"utc"	=>	"Universal (Coordinated)",
		"wet"	=>	"Western European",
		"wat"	=>	"West Africa",
		"at" 	=>	"Azores",
		"ast" 	=>	"Atlantic Standard",
		"est" 	=>	"Eastern Standard",
		"cst" 	=>	"Central Standard",
		"mst" 	=>	"Mountain Standard",
		"pst" 	=>	"Pacific Standard",
		"yst"	=>	"Yukon Standard",
		"hst"	=>	"Hawaii Standard",
		"cat"	=>	"Central Alaska",
		"ahst"	=>	"Alaska-Hawaii Standard",
		"nt"	=>	"Nome",
		"idlw"	=>	"International Date Line West",
		"cet"	=>	"Central European",
		"met"	=>	"Middle European",
		"mewt"	=>	"Middle European Winter",
		"swt"	=>	"Swedish Winter",
		"fwt"	=>	"French Winter",
		"eet"	=>	"Eastern Europe, USSR Zone 1",
		"bt"	=>	"Baghdad, USSR Zone 2",
		"zp4"	=>	"USSR Zone 3",
		"zp5"	=>	"USSR Zone 4",
		"zp6"	=>	"USSR Zone 5",
		"wast"	=>	"West Australian Standard",
		"cct"	=>	"China Coast, USSR Zone 7",
		"jst"	=>	"Japan Standard, USSR Zone 8",
		"east"	=>	"Eastern Australian Standard",
		"gst"	=>	"Guam Standard, USSR Zone 9",
		"nzt"	=>	"New Zealand",
		"nzst"	=>	"New Zealand Standard",
		"idle"	=>	"International Date Line East");
	return %zones;
}

sub _start_page_select {
	my $S = shift;

	my $current = $S->{prefs}->{start_page} || '__main__';
	my @choices = sort keys %{ $S->{SECTION_DATA} };
	unshift(@choices, '__main__', '__all__');

	my $form = qq|<tr valign="top">
		<td>%%norm_font%%<b>Start page:</b>%%norm_font_end%%</td>
		<td>
			<select name="start_page" size="1">|;
	foreach my $c (@choices) {
		my $name;
		if ($c eq '__main__') {
			$name = 'Front Page';
		} elsif ($c eq '__all__') {
			$name = 'Everything';
		} else {
			$name = $S->{SECTION_DATA}->{$c}->{title};
		}
		my $checked = ($c eq $current) ? ' selected="selected"' : '';

		$form .= qq|
				<option value="$c"$checked>$name</option>|;
	}

	$form .= "
			</select>
		</td>
	</tr>\n";

	return $form;
}

sub _user_box_toggles {
	my $S = shift;

	my $prefs = {};
	#my $check_all = $S->{prefs}->{displayed_boxes} ? 0 : 1;
	foreach my $p (split(/,/, $S->{prefs}->{displayed_boxes})) {
		$prefs->{$p} = 1;
	}

	my $counter = 0;
	my $form = qq|
		<tr valign="top">
			<td>%%norm_font%%<b>Boxes:</b>%%norm_font_end%%</td>
			<td>
				<table width="100%" border="0" cellspacing="0" cellpadding="0">
				<tr>|;
	while (my($k, $v) = each %{ $S->{BOX_DATA} }) {
		next unless $v->{user_choose};
		$counter++;
		my $checked = ($prefs->{$k}) ? '' : ' checked="checked"';
		$form .= qq|
			<td><input type="checkbox" value="1" name="box_$k"$checked />%%norm_font%%$v->{title}%%norm_font_end%%</td>|;
		if ($counter == 2) {
			$form .= qq|
				</tr>
				<tr>|;
			$counter = 0;
		}
	}

	$form .= qq|
				</table>
				</td>
				</tr>\n|;

	return $form;
}

sub _spellcheck_toggles {
	my $S = shift;

	return unless $S->spellcheck_enabled();
	my $checked = $S->spellcheck_default() ? ' checked="checked"' : '';

	my $form = qq|
		<tr valign="top">
			<td>%%norm_font%%<b>Spellcheck posts by default?</b>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="checkbox" name="spellcheck_default"$checked />%%norm_font_end%%</td>
		</tr>
		<tr valign="top">
			<td>%%norm_font%%<b>Spelling variant:</b>%%norm_font_end%%</td>
			<td>%%norm_font%%
				<select name="speling" size="1">\n|;

	my $cur_speling = $S->{prefs}->{speling}
		|| lc($S->{UI}->{VARS}->{spellcheck_spelling})
		|| 'american';
	foreach my $s (qw(American British Canadian)) {
		my $sl = lc($s);
		my $checked = ($cur_speling eq $sl) ? ' selected="selected"' : '';
		$form .= qq|
				<option value="$sl"$checked>$s</option>|;
	}

	$form .= qq|
			</select>
			%%norm_font_end%%
			</td>
		</tr>|;

	return $form;
}

sub _rdf_feed_checks {
	my $S = shift;

	return "" unless $S->{UI}->{VARS}->{use_rdf_feeds};

	my $current_prefs = $S->rdf_get_prefs();
	my $channels = $S->rdf_channels();

	my $counter = 0;
	my $form = qq|
		<tr valign="top">
			<td>%%norm_font%%<b>External Feeds:</b><br />[<a href="%%rootdir%%/submitrdf">Submit New Feed</A>]%%norm_font_end%%</td>
			<td>
			<table width="100%" border="0" cellspacing="0" cellpadding="0">
			<tr>|;
	foreach my $c (@{$channels}) {
		next unless $c->{enabled} && $c->{title} && !$c->{submitted};
		$counter++;
		my $checked = $current_prefs->{$c->{rid}} ? ' checked="checked"'  : '';
		$form .= qq|
			<td>
			<input type="checkbox" name="rdf_$c->{rid}" value="1"$checked />
			%%norm_font%%<a href="%%rootdir%%/special/rdf_preview/?rdf=$c->{rid}">$c->{title}</a>%%norm_font_end%%
			</td>|;
		if ($counter == 2) {
			$form .= qq|
			</tr>
			<tr>|;
			$counter = 0;
		}
	}
	my $default_max = defined($S->{prefs}->{rdf_max_headlines}) ?
		$S->{prefs}->{rdf_max_headlines} :
		$S->{UI}->{VARS}->{rdf_max_headlines};
	$form .= qq|
			</tr>
			</table>
			</td>
		</tr>
		<tr valign="top">
			<td>%%norm_font%%<b>Maximum headlines per feed:</b>%%norm_font_end%%</td>
			<td>%%norm_font%%<input type="text" name="max_rdf_titles" value="$default_max" size="5">%%norm_font_end%%</td>
		</tr>|;

	return $form;
}

# makes a select box for how to open up ads, when you click on them
sub _ad_open_select {
	my $S = shift;

	my @choices = ("Yes", "No");
	my $curr = $S->{prefs}->{ad_open_new_win} || "Yes";
	
	my $select = qq|
		<select name="ad_open_new_win" size=1>|;
	my $selected = '';
	foreach my $choice (@choices) {
		if ($choice eq $curr) {
			$selected = ' selected="selected"';
		} else {
			$selected = '';
		}
		$select .= qq|
			<option value="$choice"$selected>$choice</option>|;
	}

	$select .= qq|
		</select>|;

	my $content = qq|
		<tr valign="top">
			<td>%%norm_font%%<b>Open advertisement clicks in new window?</b>%%norm_font_end%%</td>
			<td>%%norm_font%% $select %%norm_font_end%%</td>
		</tr>
	|;

	return $content;
}


sub _story_ad_pos_select {
	my $S = shift;
	
	my @choices = ("Embedded left", "Embedded right", "Below story", "Right column");
	my $curr = $S->{prefs}->{story_ad_position} || "Embedded right";
	
	my $select = qq|
		<select name="story_ad_position" size=1>|;
	my $selected = '';
	foreach my $choice (@choices) {
		if ($choice eq $curr) {
			$selected = ' selected="selected"';
		} else {
			$selected = '';
		}
		$select .= qq|
			<option value="$choice"$selected>$choice</option>|;
	}

	$select .= qq|
		</select>|;

	my $content = qq|
		<tr valign="top">
			<td>%%norm_font%%<b>Position of Story Ads?</b>%%norm_font_end%%</td>
			<td>%%norm_font%% $select %%norm_font_end%%</td>
		</tr>
	|;

	return $content;
}
	
sub ad_select {
	my $S = shift;
	
	return '' unless ($S->have_perm('ad_opt_out'));
	
	my $ad_setting = qq|
	<tr valign="top">
		<td>%%norm_font%%<b>Show Ads:</b>%%norm_font_end%%</td>
		<td>%%norm_font%% <SELECT NAME="showad" SIZE=1>|;

	my $cur_value = $S->{prefs}->{showad} || "None";

	foreach my $choice ('All','Index pages only','Story pages only','None') {
		my $SELECTED = ($choice eq $S->{prefs}->{showad}) ? ' SELECTED' : '';
		$ad_setting .= qq|
			<OPTION VALUE="$choice"$SELECTED>$choice|;
	}
	
	$ad_setting .= qq|
		</SELECT> %%norm_font_end%%</td>
		</tr>
	|;
	
	return $ad_setting;
}

	
1;
	
