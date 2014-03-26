package Scoop;
use strict;

sub displaystory {
	my $S = shift;
	my $sid = shift;
	my $story = shift;
	my $mode = $S->{CGI}->param('mode');
	#warn "Sid is $sid";
	my $stories;
	
	$story->{sid} ||= $sid;
	$story->{aid} ||= $S->{UID};
	$story->{nick} ||= $S->get_nick_from_uid($story->{aid});
	
	#Make sure comment controls are set
	#$S->_set_comment_mode();
	#$S->_set_comment_order();
	#$S->_set_comment_rating_thresh();
	#$S->_set_comment_type();

	#my $rating_choice;
	#$S->_set_comment_rating_choice;
	
	my $rating_choice = $S->get_comment_option('ratingchoice');
		
	unless ($sid eq 'preview') {
		$stories = $S->getstories(
			{-type => 'fullstory',
			 -sid => $sid,
			 -perm_override => 1});
		if ($stories) {		 
			$story = $stories->[0];
		} else {
			return 0;
		}

	}
	$S->{CURRENT_TOPIC} = $story->{tid};
	$S->{CURRENT_SECTION} = $story->{section};

	# Set the page title
	#$S->{UI}->{BLOCKS}->{subtitle} = $story->{title};
	
	my $page;
	if ( $S->_does_poll_exist($sid) == 1 ) {
		$page .= $S->display_poll($sid);
		# warn "displaying poll $sid";
	} else {
		# warn "getting story summary for $sid\n";
		$page .= $S->story_summary($story);
	}

	my ($more, $stats, $section) = $S->story_links($story);
	$page =~ s/%%section_link%%/$section/g;

	$page =~ s/%%readmore%%//g;
	
	$page .= qq|%%story_separator%%|;
	
	my $body = $S->{UI}->{BLOCKS}->{story_body};
	$body =~ s/%%bodytext%%/$story->{bodytext}/;
	
	if ((exists $S->{UI}->{VARS}->{use_macros} && $S->{UI}->{VARS}->{use_macros})) {
		$body = $S->process_macros($body);
	}

	$page .= $body;

	if ($S->_does_poll_exist($sid) && !$S->have_perm('view_polls')) {
		$page = qq| <b>%%norm_font%%Sorry, you don't have permission to view polls on this site.%%norm_font_end%%</b> |;
	}

	my $story_section = $story->{section} || $S->_get_story_section($sid);
	# check the section permissions
	if ($S->have_section_perm('deny_read_stories', $story_section)) {
		$page = qq| <b>%%norm_font%%Sorry, you don't have permission to read stories posted to this section.%%norm_font_end%%</b> |;
	} elsif ($S->have_section_perm('hide_read_stories', $section)) {
		$page = qq| <b>%%norm_font%%Sorry, I can't seem to find that story.%%norm_font_end%%</b> |;
	}

	if (($story->{displaystatus} == '-1' && !$S->have_perm('moderate')) || 
		($story->{displaystatus} == '-1' && (($S->{UID} ne $story->{'aid'}) && !$S->have_perm('story_admin')))) {

		$page = '';

	}

	return ($story, $page);
}		


sub story_summary {
	my $S = shift;
	my $story = shift;
	my $add_readmore = shift || 0;
	my $edit;

	$story->{nick} = $S->{UI}->{VARS}->{anon_user_nick} if $story->{aid} == -1;
	my $linknick = $S->urlify($story->{nick});
	
	my $editlink;
	if ($S->have_perm('edit_user')) {
			$editlink .= qq| [<A CLASS="light" HREF="%%rootdir%%/user/$linknick/edit">Edit User</A>]|;
	}
	
	my $info = qq|<A CLASS="light" HREF="%%rootdir%%/user/$linknick">$story->{nick}</A>$editlink|;
	my $time = $story->{ftime};
	
	
	if ($S->{UI}->{VARS}->{show_dept} && $story->{dept}) {
		$info .= qq|
 			<br>%%dept_font%%from the $story->{dept} department%%dept_font_end%%|;
	}
	
	my ($topic, $topic_link, $t_link_end, $topic_img, $topic_text);
	
	# are topics enabled, and does the user want to see topic images?
	if ($S->{UI}->{VARS}->{'use_topics'} && 
	    (($S->{UID} == -1 && $S->{UI}->{VARS}->{topic_images_default}) || 
		($S->{UID} != -1 && $S->{prefs}->{show_topic} ne 'No'))) {
		$topic = $S->get_topic($story->{tid});
	} else {
		$topic = {};
	}

	# check this, because if it's not set, either topics aren't enabled, or the
	# user doesn't want to see them, or there is no topic for this story
	if ($topic->{tid}) {
		if ($story->{section} eq 'Diary') {
			$topic_link = qq|<A HREF="%%rootdir%%/user/$linknick/diary">|;
		} else {
			$topic_link = qq|<A HREF="%%rootdir%%/?op=search&topic=$topic->{tid}">|;
		}
		
		$t_link_end = '</a>';

		$topic_img = qq|$topic_link<IMG SRC="%%imagedir%%%%topics%%/$topic->{image}" WIDTH="$topic->{width}" HEIGHT="$topic->{height}" ALT="$topic->{alttext}" TITLE="$topic->{alttext}" ALIGN="right" BORDER=0>$t_link_end
		|;
		$topic_text = qq| $topic_link$topic->{alttext}$t_link_end |;
	} else {
		$topic_img = "";
		$topic_text = "";
	}
	
	my $text = qq|
		$story->{introtext}|;

	if ((exists $S->{UI}->{VARS}->{use_macros} && $S->{UI}->{VARS}->{use_macros})) {
		$text = $S->process_macros($text);
	}

	my $op = $S->{CGI}->param('op') || 'main';
	# bit of a hack for when user's hotlist something right after posting it,
	# such as a diary. normally, it would take them back to the submitstory
	# page, when in reality they want to be taken to what they just submitted
	$op = 'displaystory' if $op eq 'submitstory';
	my $oplink = "/$op";

	foreach (qw(page section)) {
		my $var = $S->{CGI}->param($_);
		$oplink .= '/';
		$oplink .= $var if $var;
	}

	my $hotlist = '';
	if ($S->{UID} >= 0 && $story->{displaystatus} >= 0) {
		my $flag = $S->check_for_hotlist_story($story->{sid});
		if ($flag) {
			$hotlist = qq|<A HREF="%%rootdir%%/hotlist/remove/$story->{sid}$oplink">%%hotlist_remove_link%%</A>|;
		} else {
			$hotlist = qq|<A HREF="%%rootdir%%/hotlist/add/$story->{sid}$oplink">%%hotlist_link%%</A>|;
		}
	} 
	
	my $friendlist = '';

	# If a story is new, replace |new| in the story with |new_story_marker|
	my $is_new = (defined($S->story_last_seen($story->{sid})) || $op eq 'displaystory') ? '' : $S->{UI}->{BLOCKS}->{new_story_marker};

	my $section;
	if ($story->{sid} eq 'preview') {
		$section = $S->{SECTION_DATA}->{$story->{section}};	
	} else { 
		$section = $S->{SECTION_DATA}->{ $S->_get_story_section( $story->{sid} )} || undef;
	}
	
	my $page = $S->{UI}->{BLOCKS}->{story_summary};
	#warn "Page is:\n--------------------------------\n$page\n\n";
	$page =~ s/%%info%%/$info/g;
	$page =~ s/%%title%%/$story->{title}/g;
	$page =~ s/%%introtext%%/$text/g;
	$page =~ s/%%hotlist%%/$hotlist/g;
	$page =~ s/%%friendlist%%/$friendlist/g;
	$page =~ s/%%topic_img%%/$topic_img/g;
	$page =~ s/%%topic_text%%/$topic_text/g;
	$page =~ s/%%time%%/$time/g;
	$page =~ s/%%sid%%/$story->{sid}/g;
	$page =~ s/%%section_icon%%/$section->{icon}/g if $section->{icon};
	$page =~ s/%%section_title%%/$section->{title}/g;
	$page =~ s/%%aid%%/$story->{nick}/g;
	$page =~ s/%%section%%/$story->{section}/g;
	$page =~ s/%%tid%%/$story->{tid}/g;
	$page =~ s/%%new%%/$is_new/g;

	if( $add_readmore )
	{
	    my ($more, $stats, $section_link) = $S->story_links( $story );
	    $page =~ s/%%readmore%%/$more/g;
	    $page =~ s/%%stats%%/$stats/g;
	    $page =~ s/%%section_link%%/$section_link/g;
	    #$page .= qq|<TR><TD>&nbsp;</TD></TR>|;
	}
	return $page;
			
}

sub getstories {
	my $S = shift;
	my $args = shift;

	my ($rv, $sth);
	my $return_stories = [];
	
	my $type = $args->{'-type'};
	my $topic = $args->{'-topic'};
        my $user = $args->{'-user'};
	my $maxstories = $args->{'-maxstories'} || $S->{UI}->{VARS}->{maxstories};

	my $section = $args->{'-section'};
	$section = $S->{CGI}->param('section') unless ($section);
	
	my $date_format = $S->date_format('time');
	my $wmd_format = $S->date_format('time', 'WMD');

	# get some sql to make sure they can't get stories that are in sections
	# they aren't allowed to view
	my $excl_sect_sql = $S->get_disallowed_sect_sql('norm_read_stories');
	my $excl_sect_sql_wAND = ' AND ' . $excl_sect_sql;
	$excl_sect_sql_wAND = '' if( $excl_sect_sql_wAND eq ' AND ' );

	# Now get SQL to insure we retrieve inherited content
	my $inherited_sect_sql= ($S->{UI}{VARS}->{enable_subsections})?$S->get_inheritable_sect_sql($section):'';

	my $archive = 0;
	$archive = $S->_check_archivestatus($args->{-sid}) if exists($args->{'-sid'});
	# need this for joining stories to users. if we're looking in the archive,
	# the users table is in a different database, so we have to include the db
	# name to access it
	my $db_name = $S->{CONFIG}->{db_name};
	if ($type eq 'summaries') {
		my $ds = exists($args->{-dispstatus}) ? $args->{-dispstatus} : 0;
		my $page = $args->{-page};

		my @where;
		push(@where, "displaystatus = $ds")   if defined($ds);
		push(@where, "sid = '$args->{-sid}'") if exists($args->{'-sid'});
		push(@where, $excl_sect_sql) if ($excl_sect_sql ne '');
		push(@where, $args->{-where}) if ($args->{-where});

		my $offset = (($page * $maxstories) - $maxstories) if $page;
		my $limit  = $offset ? "$offset, $maxstories" : "$maxstories";
		my $from = qq|stories s LEFT JOIN $db_name.users u ON s.aid = u.uid|;
		
		$from .= ", $args->{-from}" if ($args->{-from});
		
		($rv, $sth) = $S->db_select({
			DEBUG => 0,
			ARCHIVE => $archive,
			WHAT  => qq{sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus},
			FROM  => $from,
			WHERE => join(" AND ", @where),
			ORDER_BY => q{time desc},
			LIMIT => $limit
		});
		my $count = $maxstories;
		
		while (my $story = $sth->fetchrow_hashref) {
			#warn "In Elements, getting commentcount for $story->{sid}\n";
			$story->{commentcount} = $S->_commentcount($story->{sid});	
			$story->{archived} = 0;
			push (@{$return_stories}, $story);
			$count --;
		}
		if ($S->{HAVE_ARCHIVE} && ($count > 0) && ( !exists($args->{'-sid'}))) {
			$sth->finish();
			($rv, $sth) = $S->db_select({
				DEBUG => 0,
				ARCHIVE => 0,
				WHAT => qq|count(sid)|,
				FROM  => q{stories},
				WHERE => join(" AND ", @where),
				ORDER_BY => q{time desc}
			});
			
			my $maxoffset = $sth->fetchrow;
			$sth->finish();
			my $newoffset = $offset - $maxoffset + ($maxstories - $count);
			$limit = $newoffset ? "$newoffset, $count" : "$count";
			($rv, $sth) = $S->db_select({
				ARCHIVE => 1,
				DEBUG => 0,
				WHAT => qq|sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus|,
				FROM => $from,
				WHERE => join(" AND ", @where),
				ORDER_BY => 'time desc',
				LIMIT => $limit
			});
			
			while (my $story = $sth->fetchrow_hashref) {
				#warn "In Elements, getting commentcount for $story->{sid}\n";
				$story->{commentcount} = $S->_commentcount($story->{sid});	
				$story->{archived} = 1;
				push (@{$return_stories}, $story);
			}
		}
		$sth->finish;
	
		return $return_stories;

	} elsif ($type eq 'fullstory') {
		my $displaystatus = ' AND displaystatus >= 0';
		if ($S->have_perm('story_list') || $args->{'-perm_override'}) {
			$displaystatus = '';
		} elsif ($S->have_perm('moderate')) {
			$displaystatus = ' AND (displaystatus >= 0 OR displaystatus = -2)';
		}
		($rv, $sth) = $S->db_select({
			ARCHIVE => $archive,
			WHAT => qq|sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus, time|,
			FROM => "stories s LEFT JOIN $db_name.users u ON s.aid = u.uid",
			WHERE => qq|sid = "$args->{-sid}" $displaystatus $excl_sect_sql_wAND|,
			DEBUG => 0
			});
	} elsif ($type eq 'titlesonly') {
		my ($where, $limit);
		
		$limit = qq{$S->{UI}->{VARS}->{maxstories}, $S->{UI}->{VARS}->{maxtitles}};
		if ($args->{'-sid'}) {
			$where = qq|sid = "$args->{'-sid'}" AND |;
			$limit = '';
		}
		if (defined($args->{'-section'})) {
			my $operator = '=';
			if ($args->{'-section'} =~ /^\!(.*)$/) {
				$operator = '!=';
				$args->{'-section'} = $1;
			}
			$where .= qq|section $operator "$args->{'-section'}" AND |;
		}
		if (defined($args->{'-topic'})) {
			my $operator = '=';
			if ($args->{'-topic'} =~ /^\!(.*)$/) {
				$operator = '!=';
				$args->{'-topic'} = $1;
			}
			$where .= qq|tid $operator "$args->{'-topic'}" AND |;
		}
		
		if (defined($args->{'-displaystatus'})) {
			$where .= qq|displaystatus = $args->{'-displaystatus'} |;
		} else {
			$where .= 'displaystatus >= 0 ';
		}

		$where .= $excl_sect_sql_wAND;

		$where .= " AND $args->{-where}" if $args->{-where};
		
		($rv, $sth) = $S->db_select({
			DEBUG => 0,
			ARCHIVE => $archive,
			WHAT  => qq{sid, title, $wmd_format AS ftime},
			FROM  => q{stories},
			WHERE => $where,
			LIMIT => $limit,
			ORDER_BY => q{time desc}
		});
	} elsif ($type eq 'titlesonly-section') {
		($rv, $sth) = $S->db_select({
			ARCHIVE => $archive,
			DEBUG => 0,
			WHAT  => qq{sid, title, $wmd_format AS ftime},
			FROM  => q{stories},
			WHERE => q{displaystatus >= 0 AND section = 'section' $excl_sect_sql_wAND},
			LIMIT => qq{$S->{UI}->{VARS}->{maxstories}, $S->{UI}->{VARS}->{maxtitles}},
			ORDER_BY => q{time desc}
		});
	} elsif ($type eq 'section') {
		my $page = $args->{-page};

		# first build up the WHERE part of the SQL query

		my $sec_where;
		if( $section ne '__all__' ) {
			$sec_where = qq|AND (section = '$section' |;

			if( $inherited_sect_sql ) {
				$sec_where.='OR '.$inherited_sect_sql;
			}

			$sec_where .= ") ";
		}
		else {
			my $ex_sec = $S->excluded_from_all_stories();
			$sec_where = qq|$ex_sec|;
		}

		$sec_where .= ($topic) ? qq|AND tid = '$topic' | : '';
		if ($user) {
			my $tmp_uid = $S->get_uid_from_nick($user);
			$sec_where .= qq|AND aid = '$tmp_uid' |;
		}

		my $maxdays = $args->{'-maxdays'};
		if ($maxdays) {
			$sec_where .= qq|AND TO_DAYS(NOW()) - TO_DAYS(time) <= $maxdays |; 
		}

		$sec_where .= ' ' . $excl_sect_sql_wAND;

		my $offset = (($page * $maxstories) - $maxstories) if $page;
		my $limit = $offset ? "$offset, $maxstories" : "$maxstories";
		if ($S->{UI}->{VARS}->{allow_story_hide}) {
		($rv, $sth) = $S->db_select({
			ARCHIVE => 0,
			DEBUG => 1,
			WHAT => qq|s.sid as sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus|,
			FROM => "(stories s LEFT OUTER JOIN viewed_stories v on s.sid = v.sid and v.uid = $S->{UID}) LEFT JOIN users u ON s.aid = u.uid",
			WHERE => qq|(displaystatus >= 0) and (v.hide < 1 or v.hide is null) $sec_where|,
			ORDER_BY => 'time desc',
			LIMIT => $limit });
		} else {
		($rv, $sth) = $S->db_select({
			ARCHIVE => 0,
			DEBUG => 0,
			WHAT => qq|sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus|,
			FROM => 'stories s LEFT JOIN users u ON s.aid = u.uid',
			WHERE => qq|displaystatus >= 0 $sec_where|,
			ORDER_BY => 'time desc',
			LIMIT => $limit });
		};
		unless ($rv) {
			return [];
		}

		my $count = $maxstories;
		
		while (my $story = $sth->fetchrow_hashref) {
			#warn "In Elements, getting commentcount for $story->{sid}\n";
			$story->{commentcount} = $S->_commentcount($story->{sid});	
			$story->{archived} = 0;
			push (@{$return_stories}, $story);
			$count --;
		}
		if ($S->{HAVE_ARCHIVE} && ($count > 0) && ( !exists($args->{'-sid'}))) {
			$sth->finish();
			($rv, $sth) = $S->db_select({
				ARCHIVE => 0,
				DEBUG => 0,
				WHAT => qq|count(sid)|,
				FROM => 'stories',
				WHERE => qq|displaystatus >= 0 $sec_where| });
			my $maxoffset = $sth->fetchrow;
			$sth->finish();
			my $newoffset = $offset - $maxoffset + ($maxstories - $count);
			$limit = $newoffset ? "$newoffset, $count" : "$count";
			($rv, $sth) = $S->db_select({
				ARCHIVE => 1,
				DEBUG => 0,
				WHAT => qq|sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus|,
				FROM => "stories s LEFT JOIN $db_name.users u ON s.aid = u.uid",
				WHERE => qq|displaystatus >= 0 $sec_where|,
				ORDER_BY => 'time desc',
				LIMIT => $limit
			});
			
			while (my $story = $sth->fetchrow_hashref) {
				#warn "In Elements, getting commentcount for $story->{sid}\n";
				$story->{commentcount} = $S->_commentcount($story->{sid});	
				$story->{archived} = 1;
				push (@{$return_stories}, $story);
			}
		}
		$sth->finish;
	
		return $return_stories;
	}

	unless ($rv) {
		return [];
	}
	
	while (my $story = $sth->fetchrow_hashref) {
		#warn "In Elements, getting commentcount for $story->{sid}\n";
		$story->{commentcount} = $S->_commentcount($story->{sid});	
		$story->{archived} = $S->_check_archivestatus($story->{sid});
		push (@{$return_stories}, $story);
	}
	#warn "Leaving.\n";
	$sth->finish;
	
	return $return_stories;
}

# Fetch and SQL-format any optional sections to exclude from 
# the "__all__" section
sub excluded_from_all_stories {
	my $S = shift;
	
	my @sections = split /,\s*/, $S->{UI}->{VARS}->{'sections_excluded_from_all'};
	my $sql;
	
	foreach my $sec (@sections) {
		next unless (exists $S->{SECTION_DATA}->{$sec});
		$sql .= qq|AND section != '$sec'|;
	}
	
	return $sql;
}

sub story_nav {
	my $S = shift;
	my $sid = shift;
	
	# Check for nav bar on/off
	return '' if ($S->{UI}->{VARS}->{disable_story_navbar});

	# if they don't have permission to view the story, they won't see the story, so the
	# nav bar looks out of place.  Return ''
	unless( $S->have_section_perm( 'norm_read_stories', $S->_get_story_section($sid) ) ) {
		return '';
	}

	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'time',
		FROM => 'stories',
		WHERE => qq|sid = "$sid"|});
	
	my $story = $sth->fetchrow_hashref;
	$sth->finish;

	#warn "STIME: $story->{time}\n";

	my $excl_sect_sql = ' AND ' . $S->get_disallowed_sect_sql('norm_read_stories');
	$excl_sect_sql = '' if( $excl_sect_sql eq ' AND ' );
	
	# If section is an section in the story_nav_bar_sections var
	# then only display stories from that section, otherwise
	# only display stories that are not in any of those sections
	my $sections = $S->{UI}->{VARS}->{'story_nav_bar_sections'} . ',';
	my $section = $S->_get_story_section($sid);
	if ($sections =~ /$section/) 
	{ 
		$section = $S->dbh->quote($section);
		$excl_sect_sql .= qq|AND section = $section|;
	} else {
		my @section_list = split /,\s*/, $sections;
		foreach $section (@section_list) {
			next unless (exists $S->{SECTION_DATA}->{$section});
			$section = $S->dbh->quote($section);
			$excl_sect_sql .= qq|AND section != $section|;
		}
	}
	
	($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		DEBUG => 0,
		WHAT => 'sid, title',
		FROM => 'stories',
		WHERE => qq|time < "$story->{time}" AND displaystatus >= 0 $excl_sect_sql|,
		ORDER_BY => 'time desc',
		LIMIT => 1});
	
	my $last = undef;
	if ($last = $sth->fetchrow_hashref)
	{
		$last->{commentcount} = $S->_commentcount($last->{sid});
	}
	$sth->finish;
	
	($rv, $sth) = $S->db_select({
		DEBUG => 0,
		WHAT => 'sid, title',
		FROM => 'stories',
		WHERE => qq|time > "$story->{time}" AND displaystatus >= 0 $excl_sect_sql|,
		ORDER_BY => 'time asc',
		LIMIT => 1});

	my $next = undef;
	if ($next = $sth->fetchrow_hashref)
	{
		$next->{commentcount} = $S->_commentcount($next->{sid});
	}
	$sth->finish;
	
	my $nav = qq|
		<TABLE WIDTH="100%" BORDER=0 CELLPADDING=0 CELLSPACING=0>
		<TR BGCOLOR="%%story_nav_bg%%">
			<TD WIDTH="100%" ALIGN="center">
			%%smallfont%%|;
			
	if ($last) {
		$nav .= qq|
			<B>&lt;</B> <A HREF="%%rootdir%%/story/$last->{sid}">$last->{title}</A>|;

		unless( $S->have_section_perm( 'hide_read_comments',$S->_get_story_section($last->{sid}) ) ) {
			$nav .= qq| ($last->{commentcount} comments)|; 
		}
	}
	if ($last && $next) {
		$nav .= ' | ';
	}
	if ($next) {
		$nav .= qq|
			<A HREF="%%rootdir%%/story/$next->{sid}">$next->{title}</A>|;

		unless( $S->have_section_perm( 'hide_read_comments',$S->_get_story_section($next->{sid}) ) ) {
 			$nav .= qq| ($next->{commentcount} comments)|;
		}
		$nav .= q| <B>&gt;</B>|; 
	}
	$nav .= qq|
		%%smallfont_end%%</TD></TR></TABLE>|;
	
	return $nav;
}

#"

sub recent_topics {
	my $S = shift;
	my $images = $S->{UI}->{VARS}->{imagedir}.$S->{UI}->{VARS}->{topics};
	my ($rv, $sth) = $S->db_select({
		WHAT => 'tid, sid',
		FROM => 'stories',
		WHERE => 'displaystatus >= 0',
		ORDER_BY => 'time desc',
		LIMIT => qq|$S->{UI}->{VARS}->{recent_topics_num}|});

	my ($last_topics, $topic);
	while (my $tid = $sth->fetchrow_hashref) {
		$topic = $S->get_topic($tid->{tid});
		if( $topic ) {
			$last_topics .= qq|
				<A HREF="%%rootdir%%/story/$tid->{sid}"><IMG SRC="$images/$topic->{image}" WIDTH="$topic->{width}" HEIGHT="$topic->{height}" ALT="$topic->{alttext}" BORDER=0></A>&nbsp;|;
		} else {
			$last_topics = '';
		}
	}

	$sth->finish;
	
	return $last_topics;
}

sub story_mod_display {
	my $S = shift;
	my $sid = shift;
	
	# See if we've already moderated this story..
	my ($disp_mode, $mod_data) = $S->_mod_or_show($sid);
	
	my ($form, $type);
	my $formkey = $S->get_vote_formkey();

	#If we're go to moderate this one....
	if ($disp_mode eq 'moderate') {
		if ( $S->{UI}->{VARS}->{story_auto_vote_zero} ) {
			$S->save_vote ($sid, '0', 'N');
		} else {
			$form = $S->{UI}->{BLOCKS}->{vote_console};

			my $form_txt = $S->{UI}->{BLOCKS}->{story_vote_form};
			$form_txt =~ s/%%formkey%%/$formkey/;
			$form_txt =~ s/%%sid%%/$sid/;
			$form =~ s/%%vote_form%%/$form_txt/;
			$type = 'content';
		}
		#otherwise, make the stats box
	} elsif ($disp_mode eq 'edit') {
		$type = 'content';
		my $spam_form;
		if ( ($S->_get_user_voted($S->{UID}, $sid) == 0) && 
		     ($S->{UI}->{VARS}->{use_anti_spam})) {
			$spam_form = $S->{UI}->{BLOCKS}->{edit_instructions_abuse};
			$spam_form =~ s/%%formkey%%/$formkey/;
			$spam_form =~ s/%%sid%%/$sid/;
		} else {
			$spam_form = '';
		}
		$form = "$S->{UI}->{BLOCKS}->{edit_instructions}";
		$form =~ s/%%spam_form%%/$spam_form/;
	} else {
		if ($S->{UI}->{VARS}->{story_auto_vote_zero} ) {
			$S->save_vote ($sid, '0', 'N');
		}
		
		$type = 'box';
		$form = $S->_moderation_list($sid);
	}
	
	return ($type, $form);
}

sub get_vote_formkey {
	my $S = shift;
	
	my $user = $S->user_data($S->{UID});

	Crypt::UnixCrypt::crypt($user->{'realemail'}, $user->{passwd}) =~ /..(.*)/;
	my $element = qq|<INPUT TYPE="hidden" NAME="formkey" VALUE="$1">|;	
	
	return $element;
}

sub _mod_or_show {
	my $S = shift;
	my $sid = shift;

	my $quotesid = $S->{DBH}->quote($sid);	
	my ($rv, $sth) = $S->db_select({
		DEBUG => 0,
		WHAT => 'time, vote',
		FROM => 'storymoderate',
		WHERE => qq|sid = $quotesid AND uid = $S->{UID}|});
	
	my ($returncode, $mod_data);
	if ($rv >= 1 && $rv ne '0E0') {
		#warn "Got existing vote!";
		$returncode = 'show';
		$mod_data = $sth->fetchrow_hashref;
	} else {
		#warn "No vote.";
		$returncode = 'moderate';
	}
	$sth->finish;
	
	($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'aid, displaystatus',
		FROM => 'stories',
		WHERE => qq|sid = $quotesid|});

	my ($aid, $displaystatus) = $sth->fetchrow_array() if ($rv && $rv ne '0E0');

	if ($aid eq $S->{UID} && $displaystatus != -3) {
		$returncode = 'show';
	} elsif ($displaystatus == -3) {
		$returncode = 'edit';
	}
	
	$sth->finish;

	return ($returncode, $mod_data);
}

sub _moderation_list {
	my $S = shift;
	my $sid = shift;
	
	return $S->box_magic('mod_stats', $sid);
}

sub _get_story_mods {
	my $S = shift;	
	my $sid = shift;
	my $date_format = $S->date_format('time');

	my $quotesid = $S->{DBH}->quote($sid);	
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => qq|uid, $date_format AS ftime, vote, section_only|,
		FROM => 'storymoderate',
		WHERE => qq|sid = $quotesid|,
		ORDER_BY => 'time desc'});
	
	return $sth;
}
#'

sub _check_for_story {
	my $S = shift;
	my $sid = shift;

	# if its cached, return it.
	return 1 if ( $S->{sid_cache}->{$sid} );

	# otherwise look for it, and cache if it exists	
	my $quotesid = $S->{DBH}->quote($sid);
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'sid',
		FROM => 'stories',
		WHERE => qq|sid = $quotesid|,
		LIMIT => 1});
	my $num = $sth->fetchrow_hashref;
	$sth->finish;
	if ($num->{sid}) {
		
		# cache it, then return 1, cause it exists
		$S->{sid_cache}->{$sid} = 1;
		$S->{qid_cache}->{$sid} = 0;

		return 1;
	}
	
	return 0;
}


sub author_control_display {
	my $S     = shift;
	my $story = shift;
	my $form;
	
	# if the displaystatus mode is set to editing, and the author is viewing
	# then display the edit story button.
	
	if ( ($story->{'aid'} eq $S->{UID}) && ($story->{displaystatus} <= '-2') && $S->have_perm('edit_own_story') ) {
		$form = $S->{UI}->{BLOCKS}->{author_edit_console};
		my $edit_button;
		my $edit_instructions;
		if ($story->{displaystatus} == '-3') {
			$edit_button = '<INPUT TYPE="Submit" NAME="edit" VALUE="Edit Story">';
			$edit_instructions = $S->{UI}->{BLOCKS}->{author_edit_instructions};
		};
		
		$story->{introtext} =~ s/"/&quot;/g;
		$story->{bodytext} =~ s/"/&quot;/g;
		$story->{title} =~ s/"/&quot;/g;

		my $qid = $S->get_qid_from_sid($story->{sid});
		my $author_box_txt = qq|
			%%norm_font%%
			<FORM NAME="editstory" ACTION="%%rootdir%%/" METHOD="POST">
				$edit_button
				<INPUT TYPE="Submit" NAME="delete" VALUE="Cancel Submission">
				<INPUT TYPE="checkbox" NAME="confirm_cancel" VALUE="1"> 
				Confirm cancel?
				<INPUT TYPE="hidden" NAME="edit_in_queue" VALUE="1">
				<INPUT TYPE="hidden" NAME="op" VALUE="submitstory">
				<INPUT TYPE="hidden" NAME="sid" VALUE="$story->{sid}">
				<INPUT TYPE="hidden" NAME="preview" VALUE="1">
				<INPUT TYPE="hidden" NAME="tid" VALUE="$story->{tid}">
				<INPUT TYPE="hidden" NAME="title" VALUE="$story->{title}">
				<INPUT TYPE="hidden" NAME="introtext" VALUE="$story->{introtext}">
				<INPUT TYPE="hidden" NAME="section" VALUE="$story->{section}">
				<INPUT TYPE="hidden" NAME="time" VALUE="$story->{time}">
				<INPUT TYPE="hidden" NAME="bodytext" VALUE="$story->{bodytext}">
				<INPUT TYPE="hidden" NAME="qid" VALUE="$qid)">
				<INPUT TYPE="hidden" NAME="retrieve_poll" VALUE="1">
			</FORM>
			%%norm_font_end%%|;
		$form =~ s/%%author_edit_form%%/$author_box_txt/;
		$form =~ s/%%author_edit_instructions%%/$edit_instructions/;
	}
	
	return $form;
}

1;
