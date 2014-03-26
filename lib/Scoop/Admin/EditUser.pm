package Scoop;
use strict;

my $DEBUG = 0;

=head1 EditUser.pm

This contains all of the functions where you might need to edit a user.
Everything for creating a user is in Users.pm.  This controls the
User Preferences page.

=head1 Functions

=over 4

=item *
edit_user

This is essentially a switch to pass control to the function needed for
displaying the user information, user prefs, or playing with their
ratings.
(sidenote) I think the ratings stuff should be in this file, I might move
it over here later...

=cut

sub edit_user {
	my $S = shift;
	
	my $tool = $S->{CGI}->param('tool');
	my $uid = $S->{CGI}->param('uid');
	my $nick = $S->{CGI}->param('nick');

	if ($nick && !$uid) {
		$uid = $S->get_uid_from_nick($nick);
		# Don't assume the nick is the uid. This just causes trouble.
		#$uid = $nick if (!$uid && $nick =~ /\d+/);
	# we might not need to know the nick, but we need to see if the user
	# exists. finding the nick from the uid accomplishes this
	} elsif (!$nick && $uid) {
		$nick = $S->get_nick_from_uid($uid);
	} elsif (!$nick && !$uid) {
		$uid  = $S->{UID};
		$nick = $S->{NICK};
	}

	unless ($uid && $nick) {
		$S->{UI}->{BLOCKS}->{CONTENT} .= 'I can\'t seem to find that user.';
		$S->{UI}->{VARS}->{subtitle} = 'Error';
		return;
	}

	$S->{UI}->{BLOCKS}->{CONTENT} = qq|
		<TABLE CELLPADDING=0 CELLSPACING=0 BORDER=0 width="100%">|;

	if ($tool eq 'prefs') {
		$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_get_user_prefs($uid);
		$S->{UI}->{BLOCKS}->{subtitle} = 'Edit User Info';
	} elsif ($tool eq 'ratings') {
		my $action = $S->{CGI}->param('action');
		if ($action eq 'undo') {
			$S->undo_user_ratings($uid);
		}
		$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_get_user_ratings($uid);
		$S->{UI}->{BLOCKS}->{subtitle} = 'User Ratings';
	} elsif ($tool eq 'files') {
		$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_get_user_files($uid);
		$S->{UI}->{BLOCKS}->{subtitle} = 'User Files';
	} else {
		$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_get_user_info($uid);
		$S->{UI}->{BLOCKS}->{subtitle} = 'User Info';
	}
	
	$S->{UI}->{BLOCKS}->{CONTENT} .= qq|
		</TABLE>|;
	
	return;
}

sub _get_user_files {
	my $S = shift;
	my $uid = shift;
	my $page;

	# check for incoming uploads
	if ($S->{CGI}->param('file_upload')) {
		my $file_upload_type = $S->{CGI}->param('file_upload_type');
		my ($return, $file_name, $file_size, $file_link) = $S->get_file_upload($file_upload_type);
		my $message;
		if ($return eq '') {
			$message = qq|Saved File: <a href="$file_link">$file_name</a>|;
		} else {
			$message = qq|Error: $return|;
		}
		$page .= qq{<tr><td>%%norm_font%%<b><font color="red">$message</font></b>%%norm_font_end%%<br/>&nbsp;</td></tr>};
	}
	
	my $file_name = $S->{CGI}->param('file_name');

	# check for delete activity
	if ( $S->{CGI}->param('confirm_delete') && $S->{CGI}->param('delete') && $file_name ) {
		my $path;
		return 'Permission Denied' if ($uid ne $S->{UID}) || !$S->var('upload_delete');
		if ( $S->{CGI}->param('list_type') eq 'user' ) {
			$path = $S->var('upload_path_user') . "$uid/";
		} else {
			$path = $S->var('upload_path_admin');
		};

		unlink "$path$file_name";

		$page .= qq{<tr><td>%%norm_font%%<b><font color="red">$file_name deleted.</font></b>%%norm_font_end%%<br/>&nbsp;</td></tr>};
	} 

	# check for rename activity
	if ( $S->{CGI}->param('rename_filename') && $S->{CGI}->param('rename') && $file_name ) {
		my $path;
		my $file_name_new = $S->clean_filename($S->{CGI}->param('rename_filename'));

		return 'Permission Denied' if ($uid ne $S->{UID}) || !$S->var('upload_rename');
		if ( $S->{CGI}->param('list_type') eq 'user' ) {
			$path = $S->var('upload_path_user') . "$uid/";
		} else {
			$path = $S->var('upload_path_admin');
		};

		my $message;
		if (rename "$path$file_name", "$path$file_name_new") {
			$message = "$file_name renamed to $file_name_new.";
		} else {
			$message = "Couldn't rename $file_name to $file_name_new.";
		}

		$page .= qq{<tr><td>%%norm_font%%<b><font color="red">$message</font></b>%%norm_font_end%%<br/>&nbsp;</td></tr>};
	} 

	if ($S->have_perm('upload_user')) {
		# always build the user file list
		$page .= $S->_build_file_list('user', $uid);
	}
 
	# if they are looking at their own files
	if ($S->{UID} eq $uid) {
		# if they are an admin, display those too
		if ($S->have_perm('upload_admin')) {
			$page .= $S->_build_file_list('admin');
		}

		# if they are allowed, show upload form
		if ($S->have_perm('upload_admin') || $S->have_perm('upload_user')) {
			$page .= '<tr><td>' .
				$S->display_upload_form(1, 'files') .
				'</td></tr>';
		}
	}

	return $page;
}

sub _build_file_list {
	my $S = shift;
	my $list_type = shift || 'user';
	my $uid = shift || $S->{UID};

	my $file_link;
	if ($list_type eq 'admin') {
		$file_link = $S->var('upload_link_admin');
	} else {
		$file_link = $S->var('upload_link_user') . "$uid/";
	}
	
	my $title = 'User Files:';
	
	$title = 'Admin Files:' if $list_type eq 'admin';
	my $file_list = qq{
		<tr>
			<TD BGCOLOR="%%title_bgcolor%%">%%title_font%%<B>$title</B>%%title_font_end%%</TD>
		</tr>
		<tr>
			<td><form method="post" name="file_$list_type" action="%%rootdir%%/user/uid:$uid/files/">
			<input type="hidden" name="list_type" value="$list_type">
			%%norm_font%%};

	my @files = $S->get_file_list($uid, $list_type);
	my $file_total_count = scalar @files;
	foreach my $file_name (@files) {
		my $marker;
		if ( ($S->var('upload_rename') || $S->var('upload_delete')) && $uid eq $S->{UID} ) {
			$marker = qq{<input type="radio" name="file_name" value="$file_name">};
		} else {
			$marker = "%%dot%%";
		}
		$file_list .= qq{$marker <a href="$file_link$file_name">$file_name</a><br/>};
	}

	$file_list .= "<p>$file_total_count files found.</p>" if $file_total_count != 1;
	$file_list .= "<p>$file_total_count file found. </p>" if $file_total_count == 1;

	my $buttons;
	if ( $uid eq $S->{UID} && $S->var('upload_rename') ) {
		$buttons .= qq{
			<tr>
			    <td><input type="submit" name="rename" value="Rename Selected File"></td>
			    <td>To: <input type="text" name="rename_filename"></td>
			</tr>
		};
	}

	if ( $uid eq $S->{UID} && $S->var('upload_delete') ) {
		$buttons .= qq{
			<tr>
			    <td><input type="submit" name="delete" value="Delete Selected File"></td>
			    <td>Confirm: <input type="checkbox" name="confirm_delete"></td>
			</tr>
		};
	}
	
	$buttons = qq{<table border=0>$buttons</table>} if $buttons ne '';

	$file_list .= qq|$buttons
		%%norm_font_end%%</form>
			</td>
		</tr>|;
	return $file_list;
}

sub _get_user_info {
	my $S = shift;
	my $uid = shift;
	my $nick = $S->get_nick_from_uid($uid);
	
	# Get user info
	my $user = $S->user_data($uid);
	
	my $user_data;
	
	if ($user->{homepage}) {
		$user_data .= qq|
			<B>Homepage:</B> <A HREF="$user->{homepage}">$user->{homepage}</A><BR>|;
	}
	if ($user->{fakeemail}) {
		$user_data .= qq|
			<B>Email:</B> <A HREF="mailto:$user->{fakeemail}">$user->{fakeemail}</A><BR>|;
	}
	if ($user->{bio}) {
		$user_data .= qq|
			<B>Bio:</B><BR>$user->{bio}<BR>|;
	}
	if ($user->{publickey}) {
		$user_data .= qq|
			<B>Public Key:</B><FONT FACE="courier" SIZE=3><PRE>$user->{publickey}</PRE></FONT>|;
	}

	my $user_tools;
	if ($S->have_perm('edit_user')) {
		$user_tools = qq|%%norm_font%%${nick}'s uid is <b>$uid</b> [<A HREF="%%rootdir%%/user/uid:$uid/prefs">Edit User</A>]%%end_norm_font%%|;
	}

	my $trusted;
	if ($S->{UI}->{VARS}->{use_mojo} &&
		($S->{UID} == $uid) &&
		($S->{TRUSTLEV} == 2 || $S->have_perm('super_mojo'))) {
		$trusted = "<B>$S->{UI}->{BLOCKS}->{trusted_info_message}</B><P>";
	}

	# Get recent Comments
	#my ($num_comm, $comments) = $S->_get_recent_comments($uid, $user);
	my $urlnick = $S->urlify($nick);
	
	my $comments = qq|<A HREF="%%rootdir%%/user/$urlnick/comments">View comments posted by $nick</A>|;
	my $diary = qq|<A HREF="%%rootdir%%/user/$urlnick/diary">View |.$nick.qq|'s diary</A>|;
	my $stories = qq|<A HREF="%%rootdir%%/user/$urlnick/stories">View stories posted by $nick</A>|;
	my $ratings = qq|<A HREF="%%rootdir%%/user/$urlnick/ratings">View comment ratings by $nick</A>|;
	my $ads = qq|<A HREF="%%rootdir%%/user/$urlnick/ads">View advertisements submitted by $nick</A>|;
	my $files = qq|<A HREF="%%rootdir%%/user/$urlnick/files">View |.$nick.qq|'s files</A>|;

	my $ads_link = '';
	if ( $S->{UI}->{VARS}->{use_ads} == 1 ) {
		$ads_link = qq|%%dot%% %%norm_font%% $ads %%norm_font_end%%<br />|;
	}

	my $diary_link = '';
	if ( $S->{UI}->{VARS}->{use_diaries} ) {
		$diary_link = qq{ %%dot%% %%norm_font%% $diary %%norm_font_end%%<BR> };
	}

	my $files_link = '';
	if ( $S->{UI}->{VARS}->{allow_uploads} ) {
		$files_link = qq{ %%dot%% %%norm_font%% $files %%norm_font_end%%<BR> };
	}

	my $page = qq|
		<TR>
		<TD BGCOLOR="%%title_bgcolor%%">%%title_font%%<B>User info for $user->{nickname}</B>%%title_font_end%%</TD>
		</TR>
		<TR><TD>$user_tools&nbsp;</TD></TR>
		<TR>
		<TD>%%norm_font%%
		$trusted
		$user_data
		%%norm_font_end%%</TD>
		</TR>
		<TR><TD>&nbsp;</TD></TR>
		<TR><TD>
				%%dot%% %%norm_font%%$comments%%norm_font_end%%<BR>
				$diary_link
				%%dot%% %%norm_font%%$stories%%norm_font_end%%<BR>
				%%dot%% %%norm_font%%$ratings%%norm_font_end%%<BR>
				$ads_link
				$files_link
		</TD></TR>|;
		
	return $page;
} #'

sub _get_recent_comments {
	my $S = shift;
	my $uid = shift;
	my $user = shift;
	
	my $date_format = "%a %b %D, %Y at %r";
	my $list;

	my ($rv, $sth) = $S->db_select({
		WHAT => qq|sid, pid, cid, subject, points, DATE_FORMAT(date, "$date_format") AS ftime|,
		FROM => 'comments',
		WHERE => qq|uid = $uid AND (TO_DAYS(NOW()) - TO_DAYS(date)) <= 30|,
		ORDER_BY => 'date DESC',
		LIMIT => '25'});
	
	if ($rv eq '0E0') {
		$rv = 0;
	}
	
	$list = qq|
		%%norm_font%%|;
	
	my $i = 1;
	while (my $comment = $sth->fetchrow_hashref) {
		if (!$comment->{points}) {
			$comment->{points} = 'none';
		}
	
		my $replies = $S->_num_replies($comment->{cid}, $comment->{sid});
		my $title = $S->_get_story_title($comment->{sid}) || undef;
		my $polltitle = $S->_get_poll_title($comment->{sid}) || undef;
		
		my $s_link = ($title) ? qq|?op=displaystory;sid=$comment->{sid}| 
		                      : qq|?op=view_poll;qid=$comment->{sid}|;
		
		$title = $polltitle unless $title;
		
		$list .= qq|
			<B>$i)</B> <A HREF="%%rootdir%%/?op=comments;sid=$comment->{sid};pid=$comment->{pid};cid=$comment->{cid}#$comment->{cid}">$comment->{subject}</A> ($comment->{points}) Replies: <B>$replies</B>
			<BR>posted on $comment->{ftime}
			<BR>attached to <A HREF="%%rootdir%%/$s_link">$title</A>
			<P>|;
		$i++;
	}
	$sth->finish;
	
	$list .= qq|%%norm_font_end%%|;
	
	return ($rv, $list);
}


sub _num_replies {
	my $S = shift;
	my $cid = shift;
	my $sid = shift;
	
	my ($rv) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'cid',
		FROM => 'comments',
		WHERE => qq|pid = $cid AND sid = "$sid"|});
	if ($rv eq '0E0') {
		$rv = 0;
	}
	return $rv;
}


sub _get_user_prefs {
	my $S = shift;
	my $uid = shift || $S->{UID};

	if ($uid && $uid != $S->{UID} && !$S->have_perm( 'edit_user' )) {
		my $deny = qq|
			<TR><TD>%%title_font%%<B>Permission Denied.</B>%%title_font_end%%</TD></TR>|;
		return $deny;
	} 
	
	if ($S->{UID} == -1) {
		my $deny = qq|
			<TR><TD>%%title_font%%<B>Permission Denied.</B>%%title_font_end%%</TD></TR>|;
		return $deny;
	} 
	
	my $write = $S->{CGI}->param('write');
	my $err = '&nbsp;';
	
	if ($write) {
		$err = $S->_save_user_data($uid);
	}
	
	my $user = $S->user_data($uid);
	return "%%norm_font%%Sorry, I can't seem to find that user%%norm_font_end%%"
		unless $user;
	my $form = $S->_user_prefs_form($uid, $user);

	my $page = qq|
		<TR>
		<TD BGCOLOR="%%title_bgcolor%%">%%title_font%%<B>Edit User Info for $user->{nickname}</B>%%title_font_end%%</TD>
		</TR>
		<TR><TD ALIGN="center">%%title_font%%
		<P><FONT COLOR="#FF0000">$err</FONT><P>%%title_font_end%%</TD></TR>
		$form|;
	
	return $page;
}

sub _user_prefs_form {
	my $S = shift;
	my $uid = shift;
	my $user_in = shift;

	my $params = $S->{CGI}->Vars_cloned();

	my %user = %{$user_in};
	# escape a few fields for display
	foreach my $f (qw(admin_notes bio sig publickey)) {
		$user{$f} =~ s/&/&amp;/g;
		$user{$f} =~ s/</&lt;/g;
		$user{$f} =~ s/>/&gt;/g;
	}
	my $user = \%user;

	my $nickname;
	my $group;
	my $admin_notes;
	my $orig_email;
	my $creation_ip;
	my $creation_time;
	my $subscriber_add;
	my $admin_div;
	my $formkey_element = $S->get_formkey_element();
	if ($S->have_perm('edit_user')) {
		my $form_nick = $params->{nickname} || $user->{nickname};
		$nickname = qq|
			<P><B>Nickname:</B>&nbsp; <input name="nickname" type="text" value="$form_nick" /></P>
			|;

		$group = qq|
			<P><B>User group:</B> |;
		my $cur_group = $params->{perm_group_id} || $user->{perm_group};
		if ($S->have_perm('edit_groups')) {
			$group .= $S->_get_group_selector($cur_group);
		} else {
			$group .= $cur_group;
		}
		$group .= '</P>';

		$orig_email = qq|
			<P><B>Original Email:</B>&nbsp; $user->{origemail}</P>
			|;

		$creation_ip = qq|
			<P><B>Original IP:</B>&nbsp; $user->{creation_ip}</P>
			|;

		$creation_time = qq|
			<P><B>Created At:</B>&nbsp; $user->{creation_time}</P>
			|;
		
		if( $S->{UI}->{VARS}->{allow_admin_notes} ) {
			my $form_notes = $params->{admin_notes} || $user->{admin_notes};
			$admin_notes = qq|
			<B>Admin Notes:</B><BR> |;
			$admin_notes .= qq|<TEXTAREA COLS="50" ROWS="5" NAME="admin_notes" WRAP="soft">$form_notes</TEXTAREA><P>
							|;
		}
		
	   ############## REDO WITH NEW SUS
	   #if ($S->{UI}->{VARS}->{'use_subscriptions'}) {
	   #	$subscriber_add = qq|
	   #	<B>Adjust Subscription:</B> Add <INPUT TYPE="text" SIZE=3 NAME="subscribe_add"> months<P>|;
	   #	
	   #	$subscriber_add .= qq|<b>Last Updated:</b> $user->{prefs}->{subscribe_last_update}<br>Right now, it is |.gmtime(time).qq| GMT.| 
	   #		if ($user->{prefs}->{subscriber});
	   #}
	   ##############
		
		
		$admin_div = '<hr width="100%">';
	}

	my $digest_setting;
	if($S->{UI}->{VARS}->{enable_story_digests}) {
		my $digest_select = $S->_digest_select($user);
		$digest_setting= qq|
			<P><B>Receive Email Story Digest:</B> $digest_select<BR>
			(Choose a value for how often to recieve the email digest)<BR>
			</P>|;
	}

	my ($subscription_info);

	$subscription_info = $S->sub_user_info($uid); 

	my $allowedhtml = $S->html_checker->allowed_html_as_string('prefs');
	my $welcomemessage;
	my $oldpass;
	my $firstlogin = $S->{CGI}->param('firstlogin');
	if ($S->{UI}->{VARS}->{show_prefs_on_first_login} && $firstlogin) {
		my $sitename = $S->{UI}->{VARS}->{sitename};
		$oldpass = $S->{CGI}->param('pass');
		$welcomemessage=qq|
			<p><b>Welcome to $sitename!</b> As this is your first login, you may want to change some of the 
			settings below, including your default password. None of these changes are required,
			however. Enjoy your stay.</p>
			
			<p>If you don't want to make changes, you can <a href="%%rootdir%%/">go to the front page</a>.</p>|
			
	
	}
	
	# If the user logs in for the first time, we store the old password 
	# in a hidden field, otherwise we require him to enter it to change 
	# protected preferences. As an added bonus, we hide the password for 
	# admins who don't need it.
	my $accountpassword;
	if(!$oldpass && !$S->have_perm('edit_user')) {
		$accountpassword=qq|
			<B><font color="#ff0000">Protected settings</font></B><BR>
			<B>Password:</B><BR>
			You must enter your account password to change protected settings.<br>
			<INPUT TYPE="password" SIZE="30" NAME="verify_me"><P>|;
	} else {
		$accountpassword=qq|
			<INPUT TYPE="hidden" NAME="verify_me" VALUE="$oldpass">|;
	}

	# set default values to what the user entered (if we're re-displaying the
	# form because of error), or to what's in the DB
	my %defaults;
	foreach my $field (qw(fakeemail homepage bio sig publickey realemail)) {
		$defaults{$field} = defined($params->{$field}) ?
			$params->{$field} : $user->{$field};
	}

	# if this is their first login, we want to keep showing the message even if
	# there is an error
	my $form_firstlogin = '<input type="hidden" name="firstlogin" value="1">'
		if $firstlogin;

	my $form = qq|
		<TR>
			<TD>%%norm_font%%<FORM NAME="userdata" ACTION="%%rootdir%%/" METHOD="post">
			$formkey_element
			$form_firstlogin
			<INPUT TYPE="hidden" NAME="op" VALUE="user">
			<INPUT TYPE="hidden" NAME="tool" VALUE="prefs">
			<INPUT TYPE="hidden" NAME="uid" VALUE="$uid">
			<INPUT TYPE="hidden" NAME="oldemail" VALUE="$user->{realemail}">						
			$welcomemessage
			$nickname
			$group
			$orig_email
			$creation_time
			$creation_ip
			$admin_notes
			$admin_div
			$subscription_info
			<B>Displayed Email:</B> <BR>
			This is the address that will be displayed in comments and in your user info.
			It will not be used to email forgotten passwords. You may want to add some kind
			of spam protection so that harvesters cannot parse it.<BR>
			<INPUT TYPE="text" SIZE="50" NAME="fakeemail" VALUE="$defaults{fakeemail}"><P>
			<B>Homepage:</B><BR>
			If you have a homepage, enter the address here and it will be added to your
			comments and user info. The full path is required: remember the "http://"!<BR>
			<INPUT TYPE="text" SIZE="50" NAME="homepage" VALUE="$defaults{homepage}"><P>
			The following three fields allow HTML entry.<BR> $allowedhtml
			<P>
			<B>Bio:</B><BR>
			Enter any kind of biographical information you want other users to see about yourself
			here.
			<BR>
			<TEXTAREA COLS=50 ROWS=5 WRAP="soft" NAME="bio">$defaults{bio}</TEXTAREA><P>
			<B>Signature:</B><BR>
		        This will get attached to your comments. Sigs are typically used for quotations or links.<BR>
			<TEXTAREA COLS=50 ROWS=5 WRAP="soft" NAME="sig">$defaults{sig}</TEXTAREA><P>
			<B>Public Key:</B><BR>
			If you have a PGP/GPG public key (used for encrypting and signing email), paste it in here.<BR>
			<TEXTAREA COLS=50 ROWS=5 NAME="publickey">$defaults{publickey}</TEXTAREA><P>
			$digest_setting
			<P>
			$accountpassword
			<B>Real Email:</B><BR>
			This is the address that will be used to email forgotten passwords. It will not be shown. Please do not
			insert any kind of spam protection here, or you will not be able to get a new password!<BR>
			<INPUT TYPE="text" SIZE="50" NAME="realemail" VALUE="$defaults{realemail}"><P>
			<B>New Password:</B><BR>
			Leave both fields blank for no change. This is asked twice to detect typos.<BR>	
			<table border="0" cellpadding="0" cellspacing="0">
			<TR><TD>%%norm_font%%New Password:</font></TD><TD>%%norm_font%%<INPUT TYPE="password" SIZE="30" NAME="pass1"></font></TD></TR>
			<TR><TD>%%norm_font%%New Password Again:</font></TD><TD>%%norm_font%%<INPUT TYPE="password" SIZE="30" NAME="pass2"></font></TD></TR>
			</table>
			<P>
			<INPUT TYPE="submit" NAME="write" VALUE="Save Preferences">
			</FORM>%%norm_font_end%%
			</TD>
		</TR>|;
	
	return $form;
}
#"


sub _digest_select {
	my $S = shift;
	my $user = shift;

	my @choices = ("Never", "Daily", "Weekly", "Monthly");
	my $curr = $S->cgi->param('digest') || $user->{prefs}->{digest} || "Never";
	
	my $select = qq|
		<SELECT NAME="digest" SIZE=1>|;
	my $selected = '';
	foreach my $choice (@choices) {
		if ($choice eq $curr) {
			$selected = ' SELECTED';
		} else {
			$selected = '';
		}
		$select .= qq|
			<OPTION VALUE="$choice"$selected>$choice|;
	}
	$select .= qq|
		</SELECT>|;
	
	return $select;
}


sub _save_user_data {
	my $S = shift;
	my $uid = shift || $S->{UID};
	my $user = shift;
	my $safe = shift;
	
	$user = $S->user_data($uid);

	my %params = %{ $S->{CGI}->Vars_cloned() };
	
	if ($uid && $uid != $S->{UID} && !$S->have_perm('edit_user') && !$safe) {
		my $deny = qq|Permission Denied.|;
		return $deny;
	} 
	
	unless($S->check_formkey()) {
	
		my $message=qq|
			Invalid form key. You probably tried to save your
			settings more than once. Do not hit "BACK"! If you 
			are certain that your settings have not been saved,
			try to save them from this screen.			
			|;
		return $message;
	}

	# check that the old password is correct. 
	# get the username for input to check_password()
	my $user_name = $S->get_nick_from_uid($uid);
	if( $params{verify_me} && ($S->check_password( $user_name, $params{verify_me}) == 0) && !$safe) {
		# then the password they typed in is wrong.  Return an error
		return "Your old password is incorrect";
	}
	
	if ( $params{pass1} ne $params{pass2}) {
		return "Passwords do not match!";
	} #elsif ( $params{pass1} ) { 
		# the passwords match, and pass1 is not empty
		# make sure they entered an old password
		# if they didn't return with an error
	#	if( ! $params{oldpass} ) {
	#		return "You must enter your old password to change passwords."
	#	}
	#}
	
	#crypt the password
	my $c_pass;
	if ($params{pass1}) {
		$c_pass = $S->crypt_pass($params{pass1});
	}

	my $update_nickname = 0;
	if ($S->have_perm('edit_user') && ($user_name ne $params{nickname})) {
		if ($S->get_uid_from_nick($params{nickname})) {
			return "The nickname $params{nickname} is already in use.";
		}
		$update_nickname = 1;
	}

	if ($params{realemail} ne $params{oldemail}) {
                if (my $dup_email_err = $S->check_email($params{realemail})) {
			return $dup_email_err;
               }
	}

	#filter stuff...
	$params{homepage} = $S->filter_subject($params{homepage});
	$params{fakeemail} = $S->filter_subject($params{fakeemail});
	$params{realemail} = $S->filter_subject($params{realemail});
	
	foreach my $i (qw(bio sig publickey)) {
		$params{$i} = $S->filter_comment($params{$i}, 'prefs');
		my $errors = $S->html_checker->errors_as_string;
		return $errors if $errors;
	}

	# We need to save this in unquoted form so we can check later
	# if the user has changed it.
	my $newmail=$params{realemail};
	my $max_sig_length = $S->{UI}->{VARS}->{max_sig_length};
	$max_sig_length = 160 unless ($max_sig_length);
	if (length($params{sig}) > $max_sig_length) {
		return "Your sig is too long. Maximum length is $max_sig_length characters";
	}

	$params{homepage} =  $S->{DBH}->quote($params{homepage});
	$params{fakeemail} =  $S->{DBH}->quote($params{fakeemail});
	$params{realemail} =  $S->{DBH}->quote($params{realemail});
	$params{bio} = $S->{DBH}->quote($params{bio});
	$params{sig} = $S->{DBH}->quote($params{sig});
	$params{perm_group_id} = $S->{DBH}->quote($params{perm_group_id});
	$params{publickey} = $S->{DBH}->quote($params{publickey});
	$params{admin_notes} = $S->{DBH}->quote($params{admin_notes});
	$params{nickname} = $S->{DBH}->quote($params{nickname});
		
	my $set;
	
	if ($params{realemail}) {
		$set = qq|realemail = $params{realemail}, |;
	}
	if ($params{fakeemail}) {
		$set .= qq|fakeemail = $params{fakeemail}, |;
	}
	if ($params{homepage}) {
		$set .= qq|homepage = $params{homepage}, |;
	}
	if ($params{bio}) {
		$set .= qq|bio = $params{bio}, |;
	}
	if ($params{publickey}) {
		$set .= qq|publickey = $params{publickey}, |;
	}
	if ($params{sig}) {
		$set .= qq|sig = $params{sig}, |;
	}
	if ($c_pass) {
		$set .= qq|passwd = "$c_pass", |;
	}
	if ($params{perm_group_id} && $S->have_perm('edit_groups')) {
		$set .= qq|perm_group = $params{perm_group_id}, |;
	}
	if ($params{admin_notes} && $S->have_perm('edit_user')) {
		$set .= qq|admin_notes = $params{admin_notes}, |;
	}
	if ($update_nickname) {
		$set .= qq|nickname = $params{nickname}, |;
	}
	
	$set =~ s/, $//;

	# Check to see if they will try to change protected settings.
	# If they do, make sure they entered a correct password.
	unless( ($params{verify_me} && ($S->check_password( $user_name, $params{verify_me}) > 0)) ||
		$S->have_perm('edit_user') ) {
		
		
		my $oldmail=$user->{realemail};
		if ( ($newmail ne $oldmail) || $params{pass1} || $params{pass2} ) {
			return "You must enter your password to change protected account settings";
		}
	}

	
	my ($rv, $sth);
	my ($oldsig, $newsig);

	if ($params{sig}) {
		#warn "Getting old sig\n";
		($rv, $sth) = $S->db_select({
			DEBUG => 0,
			WHAT => 'sig',
			FROM => 'users',
			WHERE => qq|uid = $uid|});
		$oldsig = $sth->fetchrow;
		$sth->finish;
	}
	
	($rv, $sth) = $S->db_update({
		DEBUG => 0,
		WHAT => 'users',
		SET => $set,
		WHERE => qq|uid = $uid|});
	
	unless ($rv) {
		my $err = $S->{DBH}->errstr;
		return $err;
	}
	$sth->finish;

	if ($params{sig}) {
		#warn "Checking new sig\n";
		($rv, $sth) = $S->db_select({
			DEBUG => 0,
			WHAT => 'sig',
			FROM => 'users',
			WHERE => qq|uid = $uid|});
		$newsig = $sth->fetchrow;
		$sth->finish;
		$newsig = $S->{DBH}->quote($newsig);
		$oldsig = $S->{DBH}->quote($oldsig);
		#warn "Saved sig : $newsig\n";
		#warn "Submitted sig : $params{sig}\n";
		if ($newsig ne $params{sig}) {
			($rv, $sth) = $S->db_update({
				DEBUG => 0,
				WHAT => 'users',
				SET => qq|sig = $oldsig|,
				WHERE => qq|uid = $uid|});
			$params{sig} = $oldsig;
			$S->{CGI}->{params}{sig} = $oldsig;
			$sth->finish if ($rv);
		}
	}

	# if the user's nickname is changed, then we also need to update some other
	# tables to reflect the new nickname
	if ($update_nickname) {
		my $old_nick = $S->{DBH}->quote($user_name);

		# update the rdf_channels table
		($rv, $sth) = $S->db_update({
			WHAT  => 'rdf_channels',
			SET   => "submittor = $params{nickname}",
			WHERE => "submittor = $old_nick"
		});
		$sth->finish;
	}

	if ($params{subscribe_add} && $S->have_perm('edit_user')) {
		warn "Subscription expires $user->{prefs}->{subscription_expire}\n";
		
		my $new_expire = $S->add_to_subscription($user, $params{subscribe_add});
		my $updated = "$S->{NICK}, ".gmtime(time)." GMT";
		
		($rv, $sth) = $S->db_delete({
			FROM  => 'userprefs',
			WHERE => "uid = $uid AND (prefname = 'subscriber' OR prefname = 'subscription_expire' OR prefname = 'subscribe_last_update')"
		});
		
		($rv,$sth)=$S->db_insert({
			INTO 	=> 'userprefs',
			COLS	=> qq|uid,prefname,prefvalue|,
			VALUES	=> qq|$uid,'subscription_expire',"$new_expire"|
		});

		unless($rv) {
			my $err=$S->{DBH}->errstr;
			return $err;
		}
		$sth->finish;

		($rv,$sth)=$S->db_insert({
			INTO 	=> 'userprefs',
			COLS	=> qq|uid,prefname,prefvalue|,
			VALUES	=> qq|$uid,'subscriber',1|
		});

		unless($rv) {
			my $err=$S->{DBH}->errstr;
			return $err;
		}
		$sth->finish;
		
		($rv,$sth)=$S->db_insert({
			INTO 	=> 'userprefs',
			COLS	=> qq|uid,prefname,prefvalue|,
			VALUES	=> qq|$uid,'subscribe_last_update',"$updated"|
		});

		unless($rv) {
			my $err=$S->{DBH}->errstr;
			return $err;
		}
		$sth->finish;
	}
		

	($rv,$sth)=$S->db_delete( {
		FROM 	=> 'userprefs',
		WHERE	=> qq|uid=$uid and prefname='showad'|
	});
		
	if ($params{'showad'} eq 'Yes') {
		($rv,$sth)=$S->db_insert({
			INTO 	=> 'userprefs',
			COLS	=> qq|uid,prefname,prefvalue|,
			VALUES	=> qq|$uid,'showad','Yes'|
		});
		unless ($rv) {
			my $err=$S->{DBH}->errstr;
			return $err;
		}
	}	

	# Added by Srijith 06/02/2001
	($rv,$sth)=$S->db_delete( {
		FROM 	=> 'userprefs',
		WHERE	=> qq|uid=$uid and prefname ='digest'|
	});
		
	unless ($rv) {
		my $err=$S->{DBH}->errstr;
		return $err;
	}
	unless($params{digest} eq 'Never' || $params{digest} eq '' ) {
	
		($rv,$sth)=$S->db_insert({
			INTO 	=> 'userprefs',
			COLS	=> qq|uid,prefname,prefvalue|,
			VALUES	=> qq|$uid,'digest','$params{digest}'|
		});
	
		unless($rv) {
			my $err=$S->{DBH}->errstr;
			return $err;
		}
		$sth->finish;
	}
	# Addition Over
	
	$S->_refresh_group_perms();
	#Load new values from 'userprefs' table
	$S->_set_prefs();

	# Drop user from cache for updating
	delete $S->{USER_DATA_CACHE}->{$uid};
	
	return "User Updated";
}

sub add_to_subscription	{
	my $S = shift;
	my $user = shift;
	my $months = shift;
	
	my $add = $months * 2678400;
	my $exp = $user->{prefs}->{subscription_expire} || time;
	
	return ($exp + $add);
}


=item *
pref()

This is a nice convenient method for getting and setting preferences 
for the logged in user. It's intended for use from within boxes and
other places where you don't want the hastle of having to address
the prefs table directly. It can be used one of three ways:

$S->pref({pref1 => 'value1', pref2 => 'value2'}); # Sets multiple prefs

$S->pref('pref1','value1');	# Sets a single preference value

my $value = $S->pref('pref1');	# Returns the value for the named preference

It is hoped that this method will become the standard for accessing preferences

=cut

sub pref {
	my $S     = shift;
	my $key   = shift;
	my $value = shift;
	my ($rv, $sth);

	return unless defined $key;

	if( ref($key) eq 'HASH') {	# Set a bunch of prefs
		my $quid = $S->dbh->quote($S->{UID});
		for (keys %{$key}) {
			if ( exists $S->{prefs}->{$_} ) {
				my $qkey = $S->dbh->quote($_);
				my $qvalue = $S->dbh->quote($key->{$_});

				($rv, $sth) = $S->db_update({
					WHAT	=> 'userprefs',
					SET		=> qq| prefvalue = $qvalue |,
					WHERE	=> qq|uid = $quid AND prefname = $qkey |
				});
			} else {
				my $qkey = $S->dbh->quote($_);
				my $qvalue = $S->dbh->quote($key->{$_});

				($rv, $sth) = $S->db_insert({
					INTO	=> 'userprefs',
					COLS	=> 'uid, prefname, prefvalue',
					VALUES	=> qq| $quid, $qkey, $qvalue |
				});

			}

			# Don't forget to update the cache and stuff
			$S->{prefs}->{$_} = $key->{$_};
			$S->{USER_DATA_CACHE}->{ $S->{UID} }->{prefs}->{$_} = $key->{$_};

			unless( $rv ) {
				return $S->dbh->errstr();
			}
		}

	} elsif (defined $value) {  # Set only one pref
		if (defined $S->{prefs}->{$key}) {
			my $qkey = $S->dbh->quote($key);
			my $qvalue = $S->dbh->quote($value);

			($rv, $sth) = $S->db_update({
				DEBUG	=> 0,
				WHAT	=> 'userprefs',
				SET		=> qq| prefvalue = $qvalue |,
				WHERE	=> qq|uid = $S->{UID} AND prefname = $qkey |
			});

		} else {
			my $qkey = $S->dbh->quote($key);
			my $qvalue = $S->dbh->quote($value);

			($rv, $sth) = $S->db_insert({
				DEBUG	=> 0,
				INTO	=> 'userprefs',
				COLS	=> 'uid, prefname, prefvalue',
				VALUES	=> qq| $S->{UID}, $qkey, $qvalue |
			});
		}

		# Don't forget to update the cache and stuff
		$S->{prefs}->{$key} = $value;
		$S->{USER_DATA_CACHE}->{ $S->{UID} }->{prefs}->{$key} = $value;

		unless ($rv) {
			warn "errstr is ", $S->dbh->errstr(), "\n";
			return $S->dbh->errstr();
		}
	} else {
		return $S->{prefs}->{$key};
	}

	return;
}

=item *
clear_prefs( \@prefs )

Given a list of prefs, it will delete them from the userprefs table.
Given a single pref, it will just delete that one.  Given the single pref
'CLEAR_ALL_USER_PREFS' it will clear all of the prefs for the current user.
Not a safe thing to do.  Returns nothing or the error generated by $S->dbh->errstr()
.

=cut

sub clear_prefs {
	my $S = shift;
	my $prefs = shift;
	my ($rv, $sth);

	# if changing a list of prefs, create a sql query to delete all listed
	if( ref($prefs) eq 'ARRAY' ) {
		my $where = "uid = $S->{UID} AND (";
		for my $p ( @$prefs ) {
			$p = $S->dbh->quote($p);
			$where .= qq|prefname = $p OR |;

			# Don't forget to update the cache and stuff
			$S->{prefs}->{$p} = undef;
			$S->{USER_DATA_CACHE}->{ $S->{UID} }->{prefs}->{$p} = undef;
		}
		$where =~ s/OR $/\)/;

		# now that we have the list, delete
		($rv, $sth) = $S->db_delete({
			FROM	=> 'userprefs',
			WHERE	=> $where,
			DEBUG	=> 0,
		});

	}
	else {
		# else just delete the one pref, unless its the special pref, then delete
		# all
		warn "deleting prefs $prefs" if $DEBUG;
		my $where = "uid = $S->{UID}";
		unless( $prefs eq 'CLEAR_ALL_USER_PREFS' ) {
			$prefs = $S->dbh->quote($prefs);
			$where .= " AND prefname = $prefs";
		}

		($rv, $sth) = $S->db_delete({
			FROM	=> 'userprefs',
			WHERE	=> $where,
			DEBUG	=> 0,
		});

		# Get all of this users' prefs out of the cache
		$S->{prefs} = undef;
		$S->{USER_DATA_CACHE}->{ $S->{UID} }->{prefs} = undef;


	}

	unless( $rv ) {
		return $S->dbh->errstr();
	}

	return;
}

1;
