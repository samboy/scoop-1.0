package Scoop;
use strict;
my $DEBUG = 0;

=head1 Users.pm

This file is your one stop shopping destination for all functions having to deal
with user administration.  Right now we're having a special on new user functions
and cleaning up user ratings.  Check it out below.

=head1 FUNCTIONS

The pod for the following functions is added as we need to change anything in them,
so some might not be documented.  

=over 4

=item undo_user_ratings($uid)

Takes a uid and undoes all ratings from that user, essentially. 
Really does 3 things:
A) Sets that user's group to the one specified by 'rating_wipe_group'
B) Deletes all ratings from that user
C) Recalculates mojo for all affected comments.

=cut

sub undo_user_ratings {
	my $S = shift;
	my $uid = shift;
	
	return unless ($uid && ($S->have_perm('edit_user')));

	# Change group right off
	if ($S->{UI}->{VARS}->{rating_wipe_group} && ($uid != -1)) {
		# first make sure the group set by the admin exists
		my ($rv, $sth) = $S->db_select({
			WHAT => 'COUNT(*)',
			FROM => 'perm_groups',
			WHERE => "perm_group_id = '$S->{UI}->{VARS}->{rating_wipe_group}'"
		});
		my ($exists) = $sth->fetchrow_array;
		$sth->finish;

		if ($exists) {
			($rv, $sth) = $S->db_update({
				WHAT  => "users",
				SET   => qq|perm_group = '$S->{UI}->{VARS}->{rating_wipe_group}'|,
				WHERE => "uid = $uid"});
			$sth->finish();
		} else {
			warn "Var rating_wipe_group set to a non-existent group. Rating wipe cancelled.\n";
			return;
		}
	}
	
	my ($rv, $sth) = $S->db_select({
		WHAT  => "sid, cid",
		FROM  => "commentratings",
		WHERE => "uid = $uid"});
	
	my $ratings = $sth->fetchall_arrayref();
	$sth->finish();
	
	return unless $rv;
	
	($rv, $sth) = $S->db_delete({
		FROM  => "commentratings",
		WHERE => "uid = $uid"});
	
	$sth->finish();
	
	my $mojo_update = {};
	my $story_update = {};
	foreach my $one_rating (@{$ratings}) {
		my $comment_uid = $S->_get_uid_of_comment($one_rating->[0], $one_rating->[1]);
		my $c_uid = $S->recalculate_one_rating($one_rating->[0], $one_rating->[1], 0, $comment_uid);
		$mojo_update->{$c_uid} = 1;
		$story_update->{$one_rating->[0]} = 1;
	}
	
	# Update mojo of affected users
	if ($S->{UI}->{VARS}->{use_mojo}) {
		$S->update_mojo($mojo_update);
	}
	
	# Mark the story modified in the cache
	foreach my $story (keys %{$story_update}) {
		next if ($S->_does_poll_exist($story));
		my $time = time();
		my $r = $story.'_mod';
		$S->cache->stamp_cache($r, $time);
	}
	
	return;
		
}


=item rating_undo_link($uid)

Creates a link to put in a page, which when clicked upon will undo
that users ratings.

=cut

sub rating_undo_link {
	my $S = shift;
	my $uid = shift;
	return unless $S->have_perm('edit_user');
	
	my $rating_undo_link = qq|%%norm_font%%<a href="%%rootdir%%/user/uid:$uid/ratings/undo">Undo all ratings</a>%%norm_font_end%%|;
	
	return $rating_undo_link;
}
	
sub _get_user_ratings {
	my $S = shift;
	my $uid = shift;
	
	my $start = $S->cgi->param('start') || 0;
	my $max_per_page = 29;
	my $next = $start + $max_per_page + 1;
	my $get = $next + 1;
	my $count = $max_per_page + 1;
	
	my $last = $start - $max_per_page - 1;
	$last = 0 if ($last < 0);

	my $nick = $S->get_nick_from_uid($uid);
	my $urlnick = $S->urlify($nick);
		
	my $next_prev = qq|
			<TR>
				<TD width="50%">%%norm_font%%|;

	$next_prev .= ($last || ($start == 30)) ? qq|
				<FORM ACTION="%%rootdir%%/" METHOD="GET">
				<INPUT TYPE="hidden" NAME="op" VALUE="user">
				<INPUT TYPE="hidden" NAME="tool" VALUE="ratings">
				<INPUT TYPE="hidden" NAME="nick" VALUE="$nick">
				<INPUT TYPE="hidden" NAME="start" VALUE="$last">
				<INPUT TYPE="submit" VALUE="&lt;&lt; Last $count">
				</FORM>| : '&nbsp;';

	$next_prev .= qq|
				%%norm_font_end%%</TD>
			|;
	
	my $rate_time_format = $S->date_format('rating_time', 'short');
	my ($rv, $sth) = $S->db_select({
		WHAT => qq|*, $rate_time_format as ftime|,
		FROM => 'commentratings',
		WHERE => qq|uid = $uid|,
		ORDER_BY => 'rating_time DESC, sid DESC, cid DESC',
		LIMIT => qq|$start, $get|,
		DEBUG => 0
	});
	
	my $date_format = $S->date_format('date', 'short');

	my $i = $start+1;
	my $ratings;
	while (($i <= $next) && (my $rating = $sth->fetchrow_hashref())) {
		my ($rv2, $sth2) = $S->db_select({
			ARCHIVE => $S->_check_archivestatus($rating->{sid}),
			WHAT => qq|subject, points, uid, $date_format AS ftime|,
			FROM => 'comments',
			WHERE => qq|sid = "$rating->{sid}" AND cid = $rating->{cid}|
		});
		my $comment = $sth2->fetchrow_hashref();
		$sth2->finish();
		
		my $poster = $S->user_data($comment->{uid});
		
		if ($comment->{points} >= 1 || ($S->{TRUSTLEV} == 2 || $S->have_perm('super_mojo'))) { 
			$ratings .= qq|
				<B>$i)</B> <B><A HREF="%%rootdir%%/comments/$rating->{sid}/$rating->{cid}#$rating->{cid}">$comment->{subject}</A></b> [$comment->{points}], by <A HREF="%%rootdir%%/user/uid:$comment->{uid}">$poster->{nickname}</A>, Rated: <b><A HREF="%%rootdir%%/comments/$rating->{sid}/$rating->{cid}?mode=alone;showrate=1#$rating->{cid}">$rating->{rating}</A></B><br> 
				Posted on $comment->{ftime}<br>
				Rated on $rating->{ftime}<P>|;
		} else {
			$ratings .= qq|
				<B>$i)</B> [Hidden Comment]<P>|;
		}
				
		$i++;
	}
	my $check = $sth->fetchrow_hashref() if $rv > 0;
	$sth->finish();	

	$next_prev .= qq|
				<TD WIDTH="50%" align="right">%%norm_font%%|;

	$next_prev .= ($check) ? qq|
				<FORM ACTION="%%rootdir%%/" METHOD="GET">
				<INPUT TYPE="hidden" NAME="op" VALUE="user">
				<INPUT TYPE="hidden" NAME="tool" VALUE="ratings">
				<INPUT TYPE="hidden" NAME="nick" VALUE="$nick">
				<INPUT TYPE="hidden" NAME="start" VALUE="$next">
				<INPUT TYPE="submit" VALUE="Next $count &gt;&gt;">
				</FORM>| : '&nbsp;';

	$next_prev .= qq|
				%%norm_font_end%%</TD>
			</TR>	
			|;
			
	my $rating_undo_link = $S->rating_undo_link($uid);
	
	return qq|
		<TR>
		<TD COLSPAN=2 BGCOLOR="%%title_bgcolor%%">%%title_font%%<B>Comment Ratings by $nick</B>%%title_font_end%%</TD>
		</TR>
		<tr><td colspan=2>$rating_undo_link</td></tr>
		$next_prev
		<TR>
			<TD COLSPAN=2>%%norm_font%%$ratings%%norm_font_end%%</TD>
		</TR>
		$next_prev|;

}

=item new_user()

This function controls everything having to do with creating a user.
It generates the form to insert an email and choose a nickname (and submits
that to itself).  If you can't tell by now, anything having to do with 
op=newuser :)

=cut

sub new_user {
	my $S = shift;

	$S->{UI}->{BLOCKS}->{subtitle} = 'New User';
	
	my $tool = $S->{CGI}->param('tool');
	my $email = $S->{CGI}->param('email');

	my $is_advertiser = 0;
	my $no_create = 0;

	# this controls whether or not they will see the extra advertising
	# account information fields.
	$is_advertiser = 1 if ($tool eq 'advertiser' || $S->{CGI}->param('advertiser') == 1 );

	$is_advertiser = 0 unless( $S->{UI}->{VARS}->{use_ads} && $S->{UI}->{VARS}->{req_extra_advertiser_info} );
	
	my $new_user_page = "";

	my $really_new_user = ( $S->{GID} eq 'Anonymous' ? 1 : 0 );
	$really_new_user = 1 if ($S->have_perm('make_new_accounts')); 
			#accounts with this perm set will never see the new advertiser page
	
	# if this is a person visiting this page not logged in, or a non-advertiser trying to 
	# set up an ad account, they get the page to create an account.  Otherwise give them 
	# an error message tailored to their situation, whether they are a normal user trying 
	# to create another account or an advertiser trying to create another advertising account
	if( $really_new_user ) {
 		$new_user_page .= $S->{UI}->{BLOCKS}->{new_user_html};

	} elsif( !$is_advertiser ) {

		$new_user_page .= $S->{UI}->{BLOCKS}->{new_user_has_account};
		$no_create = 1;

	} elsif( $is_advertiser && $S->{GID} eq $S->{UI}->{VARS}->{advertiser_group} ) {

		$new_user_page .= $S->{UI}->{BLOCKS}->{new_advertiser_has_account};
		$no_create = 1;

	} elsif( $is_advertiser ) {	
		$new_user_page .= $S->{UI}->{BLOCKS}->{new_advertiser_html};
	}

	my $formkey = $S->make_blowfish_formkey();


	my ($uname, $pass1, $error);

	# if they click the "Create User" button, create the account
	if ($tool eq 'writeuser') {
		$uname = $S->{CGI}->param('nickname');
		
		if( $really_new_user ) {
			if ($error .= $S->filter_new_username($uname)) {
				$uname = '';
			}
			
			if ($error .= $S->check_for_user($uname)) {
				$uname = '';
			} 
			
			if ($error .= $S->check_email($email)) {
				$email = '';
			} 
		}

		if ($is_advertiser) {	
			$error .= $S->check_address_fields();
		}
	
		$error .= $S->check_ip();
		
		$error .= $S->check_creation_rate();
			
		$pass1 = $S->_random_pass();
		
		unless ($error) {
			my $rv;
			if ($really_new_user) {
				$rv = $S->create_user_step_1($uname, $pass1, $email);
			} elsif ($is_advertiser) {
				$rv = $S->store_advertiser_info($S->{UID});
			}

			if ($rv == 1) {
				# Run the new user hook
				$S->run_hook('user_new', $uname, $is_advertiser);

				my $return_page = $S->{UI}->{BLOCKS}->{newuser_confirm_page};
					
				my $user_email = $email || $S->get_email_from_uid($S->{UID});
				$return_page =~ s/%%EMAIL%%/$user_email/g;
				$return_page =~ s/%%SITENAME%%/$S->{UI}->{VARS}->{sitename}/g;
				
				$S->{UI}->{BLOCKS}->{CONTENT} .= $return_page;

				return;
			} else {
				$error .= $rv;
			}
		}
	}

	$new_user_page =~ s/%%error%%/$error/g;
	$new_user_page =~ s/%%uname%%/$uname/g;
	$new_user_page =~ s/%%email%%/$email/g;
	$new_user_page =~ s/%%formkey%%/$formkey/g;


	$S->{UI}->{BLOCKS}->{CONTENT} = $new_user_page;
	
	return;
}

sub check_ip {
	my $S = shift;
	my $formkey = $S->cgi->param('formkey');
	
	return '<BR> Invalid IP number, or old formkey. Please try again.' unless
		($S->check_blowfish_formkey($formkey));
	
	return '';
}


sub check_creation_rate {
	my $S = shift;
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'uid',
		FROM => 'users',
		WHERE => qq|creation_ip = "$S->{REMOTE_IP}" AND creation_time >= DATE_SUB(NOW(), INTERVAL 24 HOUR)|
	});

	my $count = $sth->fetchall_arrayref();
	$sth->finish();
	
	if (scalar(@$count) >= $S->{UI}->{VARS}->{max_accounts_per_day} ) {
		return '<BR> Sorry, but account creation is restricted to '. $S->{UI}->{VARS}->{max_accounts_per_day} .'new accounts per IP per day. If you are behind a proxy or firewall that serves a large number of clients, others may have already created accounts today. Just wait till tomorrow, and try again.';
	}
	
	return '';
}


sub check_address_fields {
	my $S = shift;

	my $err_start = '<BR> You forgot to fill in the following fields: ';
	my $err = '';

	$err .= 'Business Name, ' unless ( $S->{CGI}->param('bizname') );
	$err .= 'Your Name, ' unless ( $S->{CGI}->param('realname') );
	$err .= 'Contact Phone Number, ' unless ( $S->{CGI}->param('bizphone') );
	$err .= 'Mailing Address' unless ( $S->{CGI}->param('snailmail') );

	$err =~ s/, $//;

	return '' unless $err ne '';

	$err = $err_start . $err;

	return $err;
}


sub filter_new_username {
	my $S = shift;
	my $name = shift;
	
	if ($name =~ /^\s/ || $name =~ /\s$/) {
		return "Username cannot begin or end with a space.";
	}
	if ($name =~ /\s\s/) {
		return "Username cannot contain multiple spaces in a row.";
	}
		
	if ($name =~ /[^a-zA-Z0-9\s]/) {
		return "Username contains an illegal character.";
	}
	
	if ($name =~ /&nbsp;/) {
		return "Username cannot contain &amp;nbsp; entity.";
	}	
	
	return '';
}

sub create_user_step_1 {
	my $S = shift;
	my ($nick, $pass, $email) = @_;
	
	my $c_pass = $S->crypt_pass($pass);
	my $f_nick = $S->dbh->quote($nick);
	my $f_email = $S->dbh->quote($email);

	my $default_group = $S->_get_default_group;

	my ($rv, $sth) = $S->db_insert({
		INTO => 'users',
		COLS => 'nickname, origemail, realemail, passwd, perm_group, creation_ip, creation_time, is_new_account',
		VALUES => qq|$f_nick, $f_email, $f_email, "$c_pass", "$default_group", "$S->{REMOTE_IP}", NOW(),1|});
	$sth->finish;
	
	return "Error creating new user! Database said: ".$DBI::errstr if !$rv;

	my $uid = $S->dbh->{'mysql_insertid'};

	my $path = $S->{UI}->{VARS}->{site_url} . $S->{UI}->{VARS}->{rootdir};
	my $subject = $S->{UI}->{BLOCKS}->{new_user_email_subject};
	my $from = $S->{UI}->{VARS}->{new_user_email_from} || $S->{UI}->{VARS}->{local_email};
	my $sitename = $S->{UI}->{VARS}->{sitename};
	
	my $showprefs;
	if($S->{UI}->{VARS}->{show_prefs_on_first_login}) {
		$showprefs = $S->{UI}->{BLOCKS}->{new_user_email_showprefs};
	}

	my $content = $S->{UI}->{BLOCKS}->{new_user_email};

	$content =~ s/%%nick%%/$nick/;
	$content =~ s/%%pass%%/$pass/;
	$content =~ s/%%url%%/$path/;
	$content =~ s/%%showprefs%%/$showprefs/;
	$content =~ s/%%from%%/$from/;
	$content =~ s/%%sitename%%/$sitename/;

	$subject =~ s/%%sitename%%/$sitename/;

	$rv = $S->mail($email, $subject, $content, $from);
	warn 'Return from $S->mail is '.$rv."\n" if $DEBUG;

	unless ($rv == 1) {
		$S->rollback_account($uid);
	}
		
	return $rv;
}


sub rollback_account {
	my $S = shift;
	my $uid = shift;
	
	my ($rv) = $S->db_delete({
		DEBUG => 0,
		FROM => 'users',
		WHERE => qq|uid = $uid|});
	
	return;
}


# this creates an entry for them in the advertiser table
sub store_advertiser_info {
	my $S = shift;
	my $uid = shift;

	my $cname = $S->dbh->quote( $S->{CGI}->param('realname') );
	my $business = $S->dbh->quote( $S->{CGI}->param('bizname') );
	my $bizphone = $S->dbh->quote( $S->{CGI}->param('bizphone') );
	my $snailmail = $S->dbh->quote( $S->{CGI}->param('snailmail') );

	my ($rv,$sth) = $S->db_insert({
		DEBUG	=> 0,
		INTO	=> 'advertisers',
		COLS	=> 'advertisor_id, contact_name, contact_phone, company_name, snail_mail',
		VALUES	=> qq|$uid, $cname, $bizphone, $business, $snailmail|,
		});

	return qq|<br />Couldn't create new advertiser account for $uid| unless $rv;

	# find the advertiser's group name
	my $f_group = $S->dbh->quote($S->_get_default_group(1));
	($rv, $sth) = $S->db_update({
		WHAT  => 'users',
		SET   => "perm_group = $f_group",
		WHERE => "uid = $uid"
	});
	$sth->finish;

	return qq|<br />Couldn't upgrade to advertiser group for $uid| unless $rv;

	return 1;
}

=item * 
get_uid_from_nick($nickname)

Given a nickname returns the corresponding uid

=cut

sub get_uid_from_nick {
	my $S = shift;
	my $nick = shift;

	return -1 if $nick eq $S->{UI}->{VARS}->{anon_user_nick};

	$nick = $S->{DBH}->quote($nick);
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'uid',
		FROM => 'users',
		WHERE => qq|nickname = $nick|});
	
	return undef unless ($rv);
	my $id = $sth->fetchrow();
	$sth->finish;
	return $id;
}

=item *
get_nick_from_uid($uid)

Given a uid returns the corresponding nickname.

=cut

sub get_nick_from_uid {
	my $S = shift;
	my $uid = shift;

	return $S->{UI}->{VARS}->{anon_user_nick} if $uid == -1;
	return $S->{USER_DATA_CACHE}->{$uid}->{nickname} if $S->{USER_DATA_CACHE}->{$uid};

	my $f_uid = $S->dbh->quote($uid);

	my ($rv, $sth) = $S->db_select({
		WHAT	=> 'nickname',
		FROM	=> 'users',
		WHERE	=> qq|uid = $f_uid|});

	my $id = $sth->fetchrow_hashref;
	$sth->finish;
	my $nick = $id->{nickname};
	return $nick;
}

=item *
get_email_from_uid

Given an uid returns the corresponding email address

=cut

sub get_email_from_uid {
	my $S = shift;
	my $uid = shift;

	return '' if $uid == -1;
	return $S->{USER_DATA_CACHE}->{$uid}->{realemail} if $S->{USER_DATA_CACHE}->{$uid};

	my $f_uid = $S->dbh->quote($uid);

	my ($rv, $sth) = $S->db_select({
		WHAT	=> 'realemail',
		FROM	=> 'users',
		WHERE	=> qq|uid = $f_uid|});

	my $id = $sth->fetchrow_hashref;
	$sth->finish;
	my $email = $id->{realemail};
	return $email;
}

sub check_for_user {
	my $S = shift;
	my $nick = shift;

	return '<br />Username is already in use.<br />Please try a different one.'
		if $nick eq $S->{UI}->{VARS}->{anon_user_nick};

	unless ($nick) {
		return '<br />You must choose a user name';
	}
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'uid',
		FROM => 'users',
		WHERE => qq|nickname = "$nick"|});
	$sth->finish;
	
	if ($rv eq '0E0' or $rv == 0) {
		return '';
	} else {
		return '<br />Username is already in use.<br />Please try a different one.';
	}
}

sub check_email {
	my $S = shift;
	my $email = shift;
	
	unless ($email) {
		return '<BR>You must enter an email address, which must be working to activate your account.<BR><BR>';
	}
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'uid',
		FROM => 'users',
		WHERE => qq|realemail = "$email" OR origemail = "$email"|});
	#$sth->finish;
	
	# Return an error if it fails since they can't use that address
	if ($rv eq '0E0'	||
		$rv == 0 		|| # if it fails the address is already in use, so return
		$sth->fetchrow_hashref->{uid} == $S->{UID} ||	# unless its theirs
		$S->have_perm('edit_user') ) {					# or they are an admin

		$sth->finish;
	} else {
		$sth->finish;
		return '<BR>' . $email . ' belongs to a registered user already.<BR>All accounts must have a unique email address.<BR><BR>';
	}
	
	# Check that the domain is legal. 
	# Add domains to block in Var 'blocked_domains', separated by commas.
	
	my %blocked_dom = ();
	foreach(split /\s*,[\n\r\s]*/, $S->{UI}->{VARS}->{blocked_domains}) {
		#warn "Blocked $_\n";
		$blocked_dom{$_} = 1;
	}
	
	$email =~ /\@(.*)\s*$/;
	my $dom = $1;
	
	return '<BR>' . $email . " is from a blocked domain." if ($blocked_dom{$dom});
}

1;
