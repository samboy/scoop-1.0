=head1 Search.pm

This is the main module to drive searching in scoop.  Its called anytime you go to op=search, and the main
access point here is though the search subroutine

=head1 Functions

=cut 

package Scoop;
use strict;


=pod

=over 4

=item *
search()

This is the main search function.  It controls the overall display of the search page (Boxes, Content, etc)
, and calls all the appropriate
functions to populate the page with the answers to your search.  This is the only function in Search.pm that
should be called from outside of this module.  The rest are specific to displaying parts of the search, and
essentially useless for other uses.

=back

=cut

sub search {
	my $S = shift;

	my $args = $S->{CGI}->Vars;
	my $result_count = $args->{count} || 30;

	$S->{UI}->{BLOCKS}->{subtitle} = 'Search';

	# Check res count
	if ($result_count > 50) {
		$result_count = 50;
	} 
	if ($result_count < 1) {
		$result_count = 1;
	}
	
	$args->{count} = $result_count;
	
	$args->{count} = 15 if ($args->{op} eq 'xmlsearch');
	
	my $get_num = $result_count + 1;
	
	$args->{type}       ||= 'story';
	$args->{offset}     ||= 0;
	
	my $offset;
	if ($args->{last}) {
		$offset = $args->{offset} - $args->{count};
	} elsif ($args->{next}) {
		$offset = $args->{offset} + $args->{old_count};
	} else {
		$offset = 0;
	}
	
	$offset = 0 if ($offset < 0);
	
	$args->{offset} = $offset;

	$args->{string} ||= $args->{query_text};
	
	my $query = {};
	
	$query = $S->_determine_search_q($args);

	my $next_page = 1;
	my $last_page = ($offset != 0) ? 1 : 0;
	my $i = $offset + 1;
	my $stop = 	$offset + $result_count;

	$query->{LIMIT} = "$offset, $get_num";
	$query->{DEBUG} = 0;
	
	my ($rv, $sth) = $S->db_select($query);
	if ($rv == 0) {
		$rv = 0;
	}
	my $disp_count = $rv;
	if ($rv > $result_count) {
		$disp_count = "more than $result_count"
	}
	
	if ($rv < ($result_count + 1)) {
		$next_page = 0;
	}
	
	$S->{UI}->{BLOCKS}->{CONTENT} = qq|
			<TABLE WIDTH="100%" BORDER=0 CELLPADDING=0 CELLSPACING=0>
			<TR BGCOLOR="%%title_bgcolor%%">
				<TD>%%title_font%%$args->{type} search results%%title_font_end%%</TD>
			</TR>|;

	if ($args->{op} eq 'xmlsearch') {
		return ($sth, $i, $stop);
	}
	
	my ($result_list, $corrected_count) = $S->_format_search($args, $sth, $i, $stop);
	$sth->finish;

	$disp_count = $corrected_count unless( $corrected_count == -1 );

	$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_search_form($args, $next_page, $last_page, $result_list, $disp_count);

	return;
}	


=pod 

=over 4

=item *
_search_form($args, $next_page, $last_page, $results, $disp_count);

This function is what really generates the layout of the Search page. $args
is a hash reference to a hash containing all of the Vars from the url. 
$next_page and $last_page are true if the buttons for next page and prev page
should be shown, $results is the results of the query, all html formatted. 
Lastly $disp_count is the number of results found.

=back

=cut

sub _search_form {
	my $S 			= shift;
	my $args 		= shift;
	my $next_page	= shift;
	my $last_page 	= shift;
	my $results		= shift;
	my $disp_count	= shift;
		
	my $topic_select = ($S->{UI}->{VARS}->{use_topics}) ? $S->search_topic_select($args->{topic}) : '';
	my $relevance_radio = ($S->{UI}->{VARS}->{use_fulltext_indexes}) ? $S->search_relevance_radio($args->{orderby}) : '';
	my $section_select = $S->search_section_select($args->{section});
	my $search_type_select = $S->search_type_select($args->{type});
	my $phrasebox;
	if($S->{UI}->{VARS}->{use_fulltext_indexes}){
		$phrasebox = "&nbsp;&nbsp;<input type=checkbox name=phrase value=true";
		$phrasebox .= ($args->{phrase})?' CHECKED>':'>';
		$phrasebox .= " as Phrase";
	}
	my $res_num = {};
	$res_num->{$args->{count}} = ' SELECTED';
	
	my $page_buttons = qq|<TABLE WIDTH="100%" CELLPADDING=0 CELLSPACING=0 BORDER=0>
				<TR>
				<TD>%%norm_font%%|;
	
	if ($last_page >= 1) {
		$page_buttons .= qq|
			<INPUT TYPE="submit" NAME="last" VALUE="&lt;&lt; Previous Page">|;
	} else {
		$page_buttons .= '&nbsp;';
	}
	
	$page_buttons .= qq|
		%%norm_font_end%%
		</TD>
		<TD ALIGN="right">
		%%norm_font%%|;
	
	if ($next_page) {
		$page_buttons .= qq|
			<INPUT TYPE="submit" NAME="next" VALUE="Next Page &gt;&gt;">|;
	} else {
		$page_buttons .= '&nbsp;';
	}
	
	$page_buttons .= qq|
			%%norm_font_end%%
			</TD>
			</TR>
			</TABLE>|;
			
	my $story_view = sprintf( "<INPUT type=checkbox name=%s value=%s %s>",
	              '"story_view"', '"long"', 
	              $S->{CGI}->param('story_view') ? 'CHECKED' : '' );
	
	my $search_archive = '';
	
	if ($S->{HAVE_ARCHIVE} && ($S->{UI}->{VARS}->{story_archive_age} > 0)) {
		$search_archive = sprintf( "<INPUT type=\"checkbox\" name=%s value=%s %s> Search Archive",
			'"search_archive"', '"yes"', $S->{CGI}->param('search_archive') ? 'CHECKED' : '');
	}

	my $hidden_view = '';
	
	if ($S->{TRUSTLEV} == 2 || $S->have_perm('super_mojo')) {
		$hidden_view = sprintf( "<INPUT type=\"checkbox\" name=%s value=%s %s> View Hidden Comments",
	              '"hidden_comments"', '"show"',
				  $S->{CGI}->param('hidden_comments') ? 'CHECKED' : '' );
	}
				  
	my $form = qq|
		<TR>
			<TD>%%norm_font%%
			<FORM NAME="Search" ACTION="%%rootdir%%/" METHOD="GET">
			<INPUT TYPE="hidden" NAME="op" VALUE="search">
			<INPUT TYPE="hidden" NAME="offset" VALUE="$args->{offset}">
			<INPUT TYPE="hidden" NAME="old_count" VALUE="$args->{count}">
			<B>Find:</B> $search_type_select 
			<B>In:</B> $topic_select $section_select<BR>  
			<B>Containing:</B> <INPUT TYPE="text" NAME="string" VALUE="$args->{string}" SIZE=30>
			<INPUT TYPE="submit" NAME="search" VALUE="Search">$phrasebox $search_archive<BR>
			<B>Results:</B> 
			<SELECT NAME="count" SIZE=1>
			<OPTION VALUE="10"$res_num->{10}>10
			<OPTION VALUE="20"$res_num->{20}>20
			<OPTION VALUE="30"$res_num->{30}>30
			<OPTION VALUE="40"$res_num->{40}>40
			<OPTION VALUE="50"$res_num->{50}>50
			</SELECT>  
			    $story_view
				View story summaries
				$hidden_view
			<BR> $relevance_radio
			<CENTER>
			$page_buttons
			</CENTER>
			%%norm_font_end%%
			</TD>
		</TR>
		<TR>
			<TD>%%norm_font%%Found $disp_count results.<P>
			$results
			%%norm_font_end%%</TD>
		</TR>
		<TR>
			<TD ALIGN="center">%%norm_font%%
			$page_buttons
			%%norm_font_end%%
			</FORM>
			</TD>
		</TR>
		</TABLE>|;
	
	return $form;
}


=pod

=over 4

=item *
search_type_select($type);

search_type_select() generates the select box for the type of search to perform.  $type is an optional
parameter specifying the default search type.  If no $type argument is given, it defaults to 'story';

=back

=cut

sub search_type_select {
	my $S = shift;
	my $type = shift || 'story';
		
	my $form = qq|
		<SELECT NAME="type" SIZE=1>
	|;
	
	my %diary = ( ($S->{UI}->{VARS}->{use_diaries} && !$S->{UI}->{VARS}->{hide_diary_search}) ? 
					("diary" => 'Diaries', "diary_by" => 'Diaries By') :
					()
				);
	
	my %types = ("story"		=> 'Stories', 
			     "user"			=> 'Users',
				 "comment"		=> 'Comments', 
				 "author"		=> 'Authors',
				 "comment_by"	=> 'Comments By',
				 "polls"		=> 'Polls',
				 %diary
				 );

	foreach my $t (sort keys %types) {
		my $sel = ($type eq $t) ? ' SELECTED' : '';
		$form .= qq|
			<OPTION VALUE="$t"$sel>$types{$t}|;
	}
	
	$form .= qq|
		</SELECT>|;
	
	return $form;
}


=pod

=over 4

=item *
search_topic_select($topic);

Same as search_type_select(), this generates the select box for the topic to search.  If no $topic argument
is given, it defaults to All Topics being selected

=back

=cut

sub search_topic_select	{
	my $S = shift;
	my $topic = shift;
	
	my $form = qq|
		<SELECT NAME="topic" SIZE=1>
		<OPTION VALUE="">All Topics|;
		
	my $selected = '';
	foreach my $t (sort keys %{$S->{TOPIC_DATA}}) {
		next if ($t eq 'all' or $t eq 'diary');
		if ($topic eq $t) {
			$selected = ' SELECTED';
		} else {
			$selected = '';
		}
		$form .= qq|
		<OPTION VALUE="$t"$selected>$S->{TOPIC_DATA}->{$t}->{alttext}|;
	}
	$form .= qq|
		</SELECT>|;
	
	return $form;
}

sub search_section_select {
	my $S = shift;
	my $section = shift;
	
	my $form = qq|
		<SELECT NAME="section" SIZE=1>
		<OPTION VALUE="">All Sections|;

	my $list = $S->_make_section_optionlist('', 'allowed');
	
	$list =~ s/<OPTION VALUE="$section">/<OPTION VALUE="$section" SELECTED>/;
	
	$form .= qq{
		$list
		</SELECT>};
		
	return $form;
}

=pod

=over 4

=item *
search_relevance_radio($orderBy);

search_relevance_radio generates the radio buttons that determine sort order when using FULLTEXT
indexes. MySQL Version 3.23.23 and beyond (as well as various other DBs) support FULLTEXT indexes.
Because some Scoop users may be using a DB/version that does not support this functionality, it is
only active if the administrator sets the Scoop variable 'use_fulltext_indexes' to '1'. FULLTEXT
indexes allow search results scored and sorted by relevance based on the semantic value of the search
terms. As such, the most frequently used words are completely ignored and less frequently used words
are assigned progresively higher values when scoring search results. When this functionality is
turned on users are given the option to sort by date.

Before turning on this functionality be sure to create the two required FULLTEXT indexes:
alter table stories add FULLTEXT storysearch_idx (title,introtext,bodytext)
alter table comments add fulltext commentsearch_idx (subject,comment)


=back

=cut

sub search_relevance_radio {
	my $S = shift;
	my $orderby = shift || 'relevance';
	my $form = qq|<b>Sort Results By:</b>
		<input type="radio" name="orderby" value="relevance"> Relevance
		&nbsp;&nbsp;&nbsp;&nbsp;
		<input type="radio" name="orderby" value="date"> Date<br>|;
	$form =~ s/value="$orderby">/value="$orderby" CHECKED>/;
	return $form;
}

sub _determine_search_q {
	my $S = shift;
	my $args = shift;
	my $query = {};

	# keep people honest :)
	# following 4 are for > and <
	$args->{string} =~ s/>/&gt;/g; 
	$args->{string} =~ s/</&lt;/g; 
	$args->{string} =~ s/%3e/&gt;/g;
    $args->{string} =~ s/%3c/&lt;/g;

	# these 2 are for "
	$args->{string} =~ s/%22/&quot;/g;
    $args->{string} =~ s/"/&quot;/g;
	
	#remove double % signs
	$args->{string} =~ s/%%//g;

	# used for joining stories to users, as when looking in the archive, the
	# users table is in a different database
	my $db_name = $S->{CONFIG}->{db_name};

	# get sql to not list the stories that are in sections they can't read
	my $excl_sect_sql = ' AND ' . $S->get_disallowed_sect_sql('norm_read_stories');
	$excl_sect_sql = '' if( $excl_sect_sql eq ' AND ' );

	if ($args->{type} eq 'user') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% User';
		$query->{WHAT} = '*';
		$query->{FROM} = 'users';
		if ($args->{string}) {
			$query->{WHERE} = qq|nickname LIKE "%$args->{string}%" OR fakeemail LIKE "%$args->{string}%"|;
		}
		$query->{ORDER_BY} = 'nickname asc';

	} elsif ($args->{type} eq 'comment') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Comments';
		my $date_format = $S->date_format('c1.date', 'short');
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{WHAT} = qq|c1.*, $date_format AS ftime, COUNT(c2.pid) AS replies|;
		$query->{WHAT} .= qq|, MATCH(c1.subject,c1.comment) AGAINST('$args->{string}') as rank| if($S->{UI}->{VARS}->{use_fulltext_indexes});
		$query->{FROM} = 'comments AS c1 LEFT JOIN comments AS c2 ON c1.cid=c2.pid AND c1.sid=c2.sid';
		if ($args->{string}) {
			if($S->{UI}->{VARS}->{use_fulltext_indexes} && !$args->{phrase}){
				$query->{WHERE} = qq| MATCH(c1.subject,c1.comment) AGAINST('$args->{string}')|;
			} else{
				$query->{WHERE} = qq|(c1.comment LIKE "%$args->{string}%" OR c1.subject LIKE "%$args->{string}%")|;
			}
		}
		$query->{WHERE} .= ($query->{WHERE}) ? ' AND ' : '';
		if ($args->{hidden_comments} && (($S->{TRUSTLEV} == 2) || $S->have_perm('super_mojo'))) {
			$query->{WHERE} .= qq|c1.points < 1|;
		} else {
			$query->{WHERE} .= qq|(c1.points >= 1 OR c1.points IS NULL)|;
		}
		
		# hide comments to stories in the queue unless the user can moderate
		if (!$S->have_perm('moderate') || $S->{UI}->{VARS}->{hide_disabled_comments}) {
			$query->{FROM} .= ' LEFT JOIN stories AS s ON c1.sid=s.sid';
			if(!$S->have_perm('moderate')){
				$query->{WHERE} .= ' AND ' if $query->{WHERE};
				$query->{WHERE} .= 's.displaystatus > -2';
			}
			if($S->{UI}->{VARS}->{hide_disabled_comments}){
				$query->{WHERE} .= ' AND ' if $query->{WHERE};
				$query->{WHERE} .= 's.commentstatus > -1';
			}
		}

		$query->{GROUP_BY} = 'c1.sid,c1.cid';
		unless($S->{UI}->{VARS}->{use_fulltext_indexes} && $args->{orderby} eq 'relevance') {
			$query->{ORDER_BY} = 'c1.date desc';
		} else {
			$query->{ORDER_BY} = 'rank desc';
		}

	} elsif ($args->{type} eq 'comment_by') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Comments By';
		my $date_format = $S->date_format('c1.date', 'short');
		my $uid = '';
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$uid = $args->{uid};
		$uid = $S->get_uid_from_nick($args->{string}) unless defined($uid);
		$uid = 'NULL' unless defined($uid);
		
		$query->{WHAT} = qq|c1.*, COUNT(c2.pid) AS replies, $date_format AS ftime|;
		$query->{FROM} = 'comments AS c1 LEFT JOIN comments AS c2 ON c1.cid=c2.pid AND c1.sid=c2.sid';
		$query->{WHERE} = qq|(c1.uid = $uid) AND |;
		$query->{GROUP_BY} = 'c1.date DESC';
		if ($args->{hidden_comments} && (($S->{TRUSTLEV} == 2) || $S->have_perm('super_mojo'))) {
			$query->{WHERE} .= qq|(c1.points < 1)|;
		} else {
			$query->{WHERE} .= qq|(c1.points >= 1 OR c1.points IS NULL)|;
		}

		if (!$S->have_perm('moderate') || $S->{UI}->{VARS}->{hide_disabled_comments}) {
			$query->{FROM} .= ' LEFT JOIN stories AS s ON c1.sid=s.sid';
			if(!$S->have_perm('moderate')){
				$query->{WHERE} .= ' AND ' if $query->{WHERE};
				$query->{WHERE} .= 's.displaystatus > -2';
			}
			if($S->{UI}->{VARS}->{hide_disabled_comments}){
				$query->{WHERE} .= ' AND ' if $query->{WHERE};
				$query->{WHERE} .= 's.commentstatus > -1';
			}
		}
		$query->{ORDER_BY} = ($args->{orderby} eq 'relevance')?'c2.date DESC':'c1.date DESC';

	} elsif ($args->{type} eq 'author') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Stories By';
		my $date_format = $S->date_format('time', 'short');
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{FROM} = "stories s LEFT JOIN $db_name.users u ON s.aid = u.uid";
		$query->{WHAT} = qq|*, $date_format AS ftime, u.nickname AS nick|;
		$query->{GROUP_BY} = qq|sid|;

		$query->{WHERE} = qq|displaystatus >= 0  AND section != 'Diary' $excl_sect_sql|;
		
		if ($args->{string}) {
			my $uid = $S->get_uid_from_nick($args->{string});
			my $q_uid = $S->{DBH}->quote($uid);
			$query->{WHERE} .= qq| AND aid = $q_uid|;
		} 

		if ($args->{topic}) {
			$query->{WHERE} .= ($query->{WHERE}) ? ' AND ' : '';
			$query->{WHERE} .= qq|tid = "$args->{topic}"|;
		}

		if ($args->{section}) {
			$query->{WHERE} .= ($query->{WHERE}) ? ' AND ' : '';
			$query->{WHERE} .= qq|section = "$args->{section}"|;
		}

		$query->{ORDER_BY} = 'time desc';

	} elsif ($args->{type} eq 'diary_by') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Diaries By';
		my $date_format = $S->date_format('time', 'short');
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{FROM} = "stories s LEFT JOIN $db_name.users u ON s.aid = u.uid";
		$query->{WHAT} = qq|*, $date_format AS ftime, u.nickname AS nick|;
		$query->{GROUP_BY} = qq|sid|;
	
		$query->{WHERE} = qq|displaystatus >= 0 AND section = 'Diary' $excl_sect_sql|;

		if ($args->{string}) {
			my $uid = $S->get_uid_from_nick($args->{string});
			my $q_uid = $S->{DBH}->quote($uid);
			$query->{WHERE} .= qq| AND aid = $q_uid|;
		}
		
		if ($args->{topic}) {
			$query->{WHERE} .= qq| AND tid = "$args->{topic}"|;
		}
		
		$query->{ORDER_BY} = 'time desc';

	} elsif ($args->{type} eq 'diary') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Diaries';
		my $date_format = $S->date_format('time', 'short');
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{WHAT} = qq|*, $date_format AS ftime, u.nickname AS nick|;
		$query->{FROM} = "stories s LEFT JOIN $db_name.users u ON s.aid = u.uid";
		if($S->{UI}->{VARS}->{use_fulltext_indexes} && !$args->{phrase}){
			$query->{WHERE} = qq|displaystatus >= 0 and section = 'Diary' and  MATCH(title,introtext,bodytext) AGAINST('$args->{string}') $excl_sect_sql|;
		} else{
			$query->{WHERE} = qq|displaystatus >= 0 and section = 'Diary' and (introtext LIKE "%$args->{string}%" OR bodytext LIKE "%$args->{string}%" OR title LIKE "%$args->{string}%") $excl_sect_sql|;
			$query->{GROUP_BY} = qq|sid|;
		}
		$query->{ORDER_BY} = 'time desc' unless($S->{UI}->{VARS}->{use_fulltext_indexes} && $args->{orderby} eq 'relevance');
	} elsif ($args->{type} eq 'polls') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Polls';
		my $date_format = $S->date_format('post_date', 'short');
		$query->{WHAT} = qq|*, $date_format AS ftime|;
		$query->{FROM} = 'pollquestions,pollanswers';
		$query->{WHERE} = qq|pollquestions.qid = pollanswers.qid AND ( pollquestions.question LIKE "%$args->{string}%" OR pollanswers.answer LIKE "%$args->{string}%" ) |;
		$query->{GROUP_BY} = qq|pollquestions.qid|;
		$query->{ORDER_BY} = 'pollquestions.post_date desc';

	} else {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Stories';
		my $date_format = $S->date_format('time', 'short');
		my $search_str = $args->{string}; $search_str =~ s/["'%]//g;
		
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{WHAT} = qq|*, $date_format AS ftime, u.nickname AS nick|;
		$query->{WHAT} .= qq|, MATCH(title,introtext,bodytext) AGAINST('$search_str') as rank| if($S->{UI}->{VARS}->{use_fulltext_indexes});
		$query->{FROM} = "stories s LEFT JOIN $db_name.users u ON s.aid = u.uid";
		
		my $ad_section_excl;
		if ($S->{UI}->{VARS}->{use_ads} && $S->{UI}->{VARS}->{ad_story_section}) {
			$ad_section_excl = qq|AND section != "$S->{UI}->{VARS}->{ad_story_section}"|;
		}
		
		if($S->{UI}->{VARS}->{use_fulltext_indexes} && $args->{string} && !$args->{phrase}){
			$query->{WHERE} = qq|displaystatus >= 0 AND MATCH(title,introtext,bodytext) AGAINST('$search_str') AND section != "Diary" $ad_section_excl $excl_sect_sql|;
		} else{
			$query->{WHERE} = qq|displaystatus >= 0 AND (introtext LIKE '%$search_str%' OR bodytext LIKE '%$search_str%' OR title LIKE '%$search_str%') AND section != "Diary" $ad_section_excl $excl_sect_sql|;
			$query->{GROUP_BY} = qq|sid|;
		}

		if($S->{UI}->{VARS}->{use_fulltext_indexes} && $args->{orderby} eq 'relevance' ) {
			$query->{ORDER_BY} = 'rank desc';
		} else {
			$query->{ORDER_BY} = 'time desc';
		}

		if ($args->{topic}) {
			$query->{WHERE} .= qq| AND tid = "$args->{topic}"|;
		}
		if ($args->{section}) {
			$query->{WHERE} .= qq| AND section = "$args->{section}"|;
		}
	}

	return $query;
}	

sub _format_search {
	my $S 		= shift;
	my $args 	= shift;
	my $sth 	= shift;
	my $i 		= shift;
	my $stop 	= shift;
	my $page;
	my $real_count = -1;
	
	if ($args->{type} eq 'user') {
		$page = $S->_format_user_search($sth, $i, $stop);
	} elsif ($args->{type} eq 'comment' || $args->{type} eq 'comment_by') {
		($page, $real_count) = $S->_format_comment_search($sth, $i, $stop, $args->{type});
	} elsif ($args->{type} eq 'polls' ) {
		$page = $S->_format_polls_search($sth, $i, $stop);
	} else {
		$page = $S->_format_story_search($sth, $i, $stop, $args->{type});
	}
	
	return ($page, $real_count);
}

sub _format_story_search {
	my $S 		= shift;
	my $sth 	= shift;
	my $i 		= shift;
	my $stop 	= shift;
	my $type    = shift;
	my $list;
	
	
	while ((my $story = $sth->fetchrow_hashref) && ($i <= $stop)) 
	{
	    my $topic = {};
		my $comments = $S->_commentcount($story->{sid});
		$story->{commentcount} = $comments;
		
	    if ($story->{tid}) {
			$topic = $S->get_topic($story->{tid});
	    }
		
		$topic->{alttext} = 'All Topics' unless $topic->{alttext};
	   
		my $urltid = $S->urlify($story->{tid});
		my $tid_link = qq|search?topic=$urltid|;
		$tid_link .= qq|;type=diary_by| if ($type eq 'diary') || ($type eq '$diary_by');
		
		my $section_link = qq|section/$story->{section}|;
		
	    if( $S->{CGI}->param('story_view') ne "long" ) {
			my $story_nick = $S->get_nick_from_uid($story->{aid});
			$list .= qq|
		    	<P>
				<B>$i. <A HREF="%%rootdir%%/story/$story->{sid}">$story->{title}</A></B>&nbsp; 
				(<a href="%%rootdir%%/$section_link">$S->{SECTION_DATA}->{$story->{section}}->{title}</a>, <A HREF="%%rootdir%%/$tid_link">$topic->{alttext}</A>)<br>
				posted by $story_nick on $story->{ftime}|;

			# don't display comment count if they aren't supposed to know about it
			unless( $S->have_section_perm( 'hide_read_comments', $story->{section} ) ) {
				my $show = $S->{UI}->{VARS}->{show_new_comments};
				my $num_new = 'no';
				$num_new = $S->new_comments_since_last_seen($story->{sid}) if ($show eq "all" && $S->{UID} != -1);
				my $end_s = ($story->{commentcount} == 1) ? '' : 's';
				
				$list .= qq|<BR>$comments comment|.$end_s;
				if ($num_new ne 'no') {
					$list .= qq| (<b>$num_new</b> new)|;
				}
			} else {
				$list .= qq|<BR>|;
			}

			if( ($type eq 'story' || $type eq 'diary')		&&
				$S->{UI}->{VARS}->{use_fulltext_indexes}	&&
				($S->cgi->param('phrase') ne 'true')		) {
				$list .= qq| <BR> Rank: <b>| . sprintf( "%.2f", $story->{rank} ) . "</b>";
			}

	    } else {
			$list .= $S->story_summary( $story, 1 );
	    }
	    $i++;
	}
	return $list;
}


sub _format_user_search {
	my $S 		= shift;
	my $sth 	= shift;
	my $i 		= shift;
	my $stop 	= shift;
	
	my $list;
	while ((my $user = $sth->fetchrow_hashref) && ($i <= $stop)) {
		$list .= qq|
			<P>
			<B><A HREF="%%rootdir%%/user/uid:$user->{uid}">$user->{nickname}</A></B>|;
		
		if ($S->have_perm('edit_user')) {
			$list .= qq| [ <A HREF="%%rootdir%%/user/uid:$user->{uid}/edit">Edit</A> ]|;
		}
		
	}
	
	return $list;
}

sub _format_comment_search {
	my $S 		= shift;
	my $sth 	= shift;
	my $i 		= shift;
	my $stop 	= shift;
	my $argtype = shift;
	
	my ($title, $nick, $num_rate, $list);
	my $counted = 0;
	
	while ((my $comment = $sth->fetchrow_hashref) && ($i <= $stop)) {

		# don't display comments from stories that aren't posted
		next if ($S->{UI}->{VARS}->{hide_unposted_comments} && ($S->_check_story_mode($comment->{sid}) < 0));

		# also don't display if they don't have perms to read it
		next unless($S->_does_poll_exist($comment->{sid})	||
					$S->have_section_perm('norm_read_comments',$S->_get_story_section( $comment->{sid} ))
					);

		$num_rate = $comment->{lastmod};
		$num_rate = 0 if ($num_rate == '-1');
		
		my $score = $comment->{points} || 'none';
		
		if( $S->_does_poll_exist($comment->{sid}) ) {
			$title = $S->get_poll_hash($comment->{sid})->{question};
		} else {
			$title = $S->_get_story_title($comment->{sid});
		}

		$nick = $S->get_nick($comment->{uid});
		
		# Edited to go to the cid link. this is more efficient for page loading, usually.
		$list .= qq|
			<B>$i) <A HREF="%%rootdir%%/comments/$comment->{sid}/$comment->{cid}#$comment->{cid}">$comment->{subject}</A></B> [<A HREF="%%rootdir%%/comments/$comment->{sid}/$comment->{cid}?mode=alone;showrate=1#$comment->{cid}">$score / $num_rate</A>] Replies: <B>$comment->{replies}</B>
			<BR>posted by <A HREF="%%rootdir%%/user/uid:$comment->{uid}">$nick</A> on $comment->{ftime}|;

		# if its a poll it needs a different link to display it
		if( $S->_does_poll_exist($comment->{sid}) ) {
			$list .= qq|<BR>attached to <A HREF="%%rootdir%%/view_poll/$comment->{sid}">$title</A>|;
		} elsif( !$S->have_section_perm('hide_read_stories', $S->_get_story_section($comment->{sid})) ) {
			$list .= qq|<BR>attached to <A HREF="%%rootdir%%/story/$comment->{sid}">$title</A>|;
		}

		$list .= qq|<P>|;

		$i++;
		$counted++;
	}
	
	return ($list, $counted);
}


sub _format_polls_search {
	my $S       = shift;
	my $sth     = shift;
	my $i       = shift;
	my $stop    = shift;

	my ($qid, $question, $list, $post_date, $vote);

	while( (my $poll = $sth->fetchrow_hashref) && ($i <= $stop) ) {
		$qid = $poll->{qid};
		$question = $poll->{question};
		$post_date = $poll->{post_date};

		if( $S->_can_vote( $qid ) ) {
			$vote = qq|\| <a href="%%rootdir%%/?op=poll_vote;qid=$qid">Vote</a>|;
		} 
	
		$list .= qq|<P>$i) "$question" [ <A HREF="%%rootdir%%/poll/$qid">View</A> $vote ]<br>&nbsp;&nbsp;&nbsp;&nbsp; posted on $poll->{ftime}</P>|;
		
		# to make sure we don't get the value sticking around for later polls
		$vote = '';

		$i++;
	}

	return $list;
}

1;	
