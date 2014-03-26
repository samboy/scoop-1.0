=pod

=head1 Introduction

ForumZilla.pm enables ForumZilla support in Scoop.  ForumZilla 
is a Mozilla XUL application for reading web discussion forums 
with a Usenet newsreader-like interface.  This module publishes
story and comment meta-data (title, url, author, date, replies,
etc.) in RDF format, which ForumZilla reads and uses to display
a tree of available stories and comments.  When a user selects
a story or comment to read, ForumZilla loads the story or comment
content from the Scoop server.  Thus this module publishes only
meta-data, not content.

=head1 Installation

To get FZ working with Scoop, apply the necessary patches to
your Scoop installation (if you are reading this then you have
already done so), then apply the ForumZilla database patch
to your database like so:

cat <scoop-install-directory>/struct/patch-files/patch-ForumZilla.sql | mysql --user=<your-username> --password=<your-password> <your-scoop-database> 

=head1 Random Info That Helped Me Understand Scoop

In Scoop, a block is a section of HTML text that contains codes like %%name%% 
(where name is a unique name) that get replaced with additional HTML or text
during the processing of the request.  For example, a block may contain
the text "<title>%%pageTitle%%</title>" which gets translated into
<title>My Story</title> during processing of a request to display a story.

Codes can represent any text: some codes are replaced by dynamic elements
like the title of a story; other codes are replaced by variables stored
in the variables table like the root directory; still other codes are
stand-ins for other blocks like the COMMENT or CONTENT or STORY blocks
(the names for these are all caps to distinguish them from other codes).

A template is a special kind of block that contains an entire HTML document.
from opening to closing <HTML> tags.

When Scoop receives a request, it retrieves all blocks from the database
and passes them to the function corresponding with the operation being
requested (display a story, vote in a poll, etc.).  This function
does key substitution (keys are the codes embedded in blocks) for certain
blocks.  And then returns the blocks to the request handler, which then
calls the "page_out" function to do a final few rounds of key substitution
(at which time blocks get inserted into the particular template block
being used to construct the HTML page) and then passes the page back to
Apache, which passes it to the user.

=cut



package Scoop;
use strict;
#use vars qw($CACHE);
my $DEBUG = 0;

use XML::RSS;


################################################################################

sub fzDescribeForum {
	my $S = shift;
	my $args = shift;
	
	my $page = qq|
    <rdf:Description about="http://$S->{SERVER_NAME}%%rootdir%%/">
      <fz:title>%%sitename%%</fz:title>
      <fz:description resource="http://$S->{SERVER_NAME}%%rootdir%%/?op=fz"/>
      <fz:slogan>%%slogan%%</fz:slogan>
      <fz:navigation resource="%%fz_navigation_url%%"/>
      <fz:ads resource="%%fz_ad_url%%"/>
      <fz:articles>
        <rdf:Seq>|;

	$page .= $S->fzListStories($args);
	
	$page .= qq|
        </rdf:Seq>
      </fz:articles>
    </rdf:Description>|;

	return $page;

}

sub fzListStories {
	my $S = shift;
	my $args = shift;
	my $page;
	
	my $date_format = $S->date_format('time', 'W3C');

	my $select = {
		WHAT => qq|sid, title, $date_format as time|,
		FROM => 'stories',
		WHERE => 'displaystatus >= 0',
		LIMIT => 25,
		ORDER_BY => 'time DESC'
	};
	
	if ($args->{'section'}) {
		$args->{'section'} = $S->{DBH}->quote($args->{'section'});
		$select->{WHERE} .= qq| AND section = $args->{'section'}|;
	} else {
		$select->{WHERE} .= qq| AND section != 'Diary'|;
	}

	if ($args->{limit}) {
		$args->{'limit'} = $S->{DBH}->quote($args->{'limit'});
		$select->{LIMIT} = $args->{'limit'};
	}
	

	my ($rv, $sth) = $S->db_select($select);
	
	while (my $story = $sth->fetchrow_hashref()) {
		$story->{title} =~ s/<.*?>//g;
		$story->{title} =~ s/&/&amp;/g;
		$page .= qq|
          <rdf:li>
            <rdf:Description about="http://$S->{SERVER_NAME}%%rootdir%%/?op=fzdisplay;action=story;sid=$story->{sid}">
              <fz:title>$story->{title}</fz:title>
              <fz:date>$story->{time}</fz:date>
              <fz:description resource="http://$S->{SERVER_NAME}%%rootdir%%/?op=fz;action=describestory;sid=$story->{sid}" />            
            </rdf:Description>
          </rdf:li>|;
	}
	$sth->finish();
	return $page;
}

sub fzDescribeStory {

	# The $S object is the object that owns this method, and it is passed into
	# this method automatically when the method is called via $S->methodname
	my $S = shift;

	# Blocks are text strings containing HTML/RDF content as well as placeholders
	# for data that gets inserted into the content during processing of the
	# request.  The result of the processing of the block is a document containing
	# both static content and dynamically generated data that gets returned to
	# the requesting browser.
 	#my %blocks = @_;
	my $story;
	
	warn('fzDescribeStory: start');

	# Grab the unique key for the story from the URL
	my $sid = $S->{CGI}->param('sid');
	
	# Begin the RDF description of the story.
	$story = 
		qq|  <fz:story about="http://$S->{SERVER_NAME}%%rootdir%%/?op=fzdisplay;action=story;sid=$sid">\n|;

	# Display a list (RDF Sequence) of all comments for this story.
	# This list will be used by the XUL template builder to construct
	# the comment tree.
	$story .= $S->fzListAllComments($sid);

	# Display a list (RDF Sequence) of top-level replies to this story.
	# This list is used by the XUL template builder to organize
	# the comment tree in threaded mode (along with the reply lists
	# that appear in each comment description).
	$story .= $S->fzListReplies($sid, 0);
	
	# End the RDF description of the story.
	$story .= qq|  </fz:story>\n\n|;

	# Display RDF descriptions of the comments.
	$story .= $S->fzDescribeComments($sid);

	warn('fzDescribeStory: end');

	# Return content blocks which now contain the story description
	return $story;

}


################################################################################

sub fzDescribeComments {
	my $S = shift;
	my $sid = shift;

	# There are some story IDs that actually refer to polls that are attached
	# to stories.  If the story ID passed into this method actually refers to
	# a poll, get the story ID of the story to which the poll is attached, since
	# the comments we are looking for are those attached to the story, not the poll.
	# ???: Will ForumZilla ever encounter such a story?
	if( $S->_does_poll_exist($sid) && $S->get_sid_from_qid($sid) ) {
		$sid = $S->get_sid_from_qid($sid);
	}

	# Create a MySQL function call that formats the "date" field
	# in W3C format while accounting for the user's time zone preference.
	my $date_format = $S->date_format('date', 'W3C');

	# The function call created above will be used in place of the "date" field
	# in the SELECT statement below that retrieves comments from the database.

	# It looks something like one of these two examples, the first of which
	# merely formats the date and the second of which converts the date
	# from the Scoop server's time zone into the user's time zone:
	# 	DATE_FORMAT((date), "%Y-%m-%dT%H:%i:%S-05:00")
	# 	DATE_FORMAT((DATE_SUB(date, INTERVAL 10800 SECOND)), "%Y-%m-%dT%H:%i:%S-08:00")

	my $select_this = {
		ARCHIVE => $S->_check_archivestatus($sid),
		   DEBUG => 0,
		    WHAT => qq|	sid, cid, pid, $date_format as date, subject, uid, points |,
		    FROM => 'comments',
		   WHERE => qq|sid = "$sid"|,
		ORDER_BY => 'cid'
	};

	# Execute the query and retrieve the result set.
	my ($rv, $sth) = $S->db_select($select_this);

	# Stores the generated RDF descriptions of the comments
	my $description;

	# Loop over every comment, generate its RDF description, and add
	# the description to the string containing all generated descriptions
	while (my $comment = $sth->fetchrow_hashref) {

		$description .= $S->fzDescribeComment($comment);
	
	}

	$sth->finish;
	
	return $description;
}

################################################################################
sub fzDescribeComment {
	my $S = shift;
	my $comment = shift; # HASHREF

	# Information about the user, including nickname and email.
	# The only information ForumZilla currently uses is nickname.
	my $user = $S->user_data($comment->{uid});

	# The points field must be numeric, so if it is undefined (which means there
	# is a NULL value in the database because no one has rated this comment yet)
	# then set it to zero.  The score field, on the other hand, should contain
	# a textual representation of the score, and no score at all is different
	# from a score of zero, so set the score field to "none" if the points field
	# is undefined (otherwise set it to the value of the points field).
	$comment->{score} = $comment->{points} || 'none';
	$comment->{points} = 0 unless defined($comment->{points});

	# The text that represents the RDF description of the comment
	# words with %% around them represent variables that will be replaced
	# with their values during processing of the text, either in this method
	# or during processing by Scoop of the entire document before it gets returned
	# to the user.  For example, %%rootdir%% is replaced by Scoop.
	my $description = qq|
  <fz:comment about="http://$S->{SERVER_NAME}%%rootdir%%/?op=fzdisplay;action=comment;sid=%%sid%%;pid=%%pid%%;cid=%%cid%%">
    <fz:title>%%subject%%</fz:title>
    <fz:author>%%name%%</fz:author>
    <fz:datetime>%%date%%</fz:datetime>
    <fz:score>%%score%%</fz:score>
    <fz:points>%%points%%</fz:points>
%%replies%%
  </fz:comment>
	|;

	# Interpolate variables into their values
	$description =~ s/%%subject%%/$comment->{subject}/g;
	$description =~ s/%%name%%/$user->{nickname}/g;
	$description =~ s/%%date%%/$comment->{date}/g;
	$description =~ s/%%score%%/$comment->{score}/g;
	$description =~ s/%%points%%/$comment->{points}/g;
	$description =~ s/%%cid%%/$comment->{cid}/g;
	$description =~ s/%%sid%%/$comment->{sid}/g;
	$description =~ s/%%pid%%/$comment->{pid}/g;
	
	# Append to the comment description a list of replies to this comment
	my $replies = $S->fzListReplies($comment->{sid}, $comment->{cid});
	$description =~ s/%%replies%%/$replies/;

	return $description;
}


################################################################################


# Returns an RDF list of all comments for a particular story
sub fzListAllComments {
	my $S = shift;
	my $sid = shift;

	return $S->fzListComments("comments", $sid);
}

# Returns an RDF list of all comments which are replies to a particular comment
sub fzListReplies {
	my $S = shift;
	my $sid = shift;
	my $pid = shift;

	return $S->fzListComments("replies", $sid, $pid);

}

# Returns an RDF list of comments for a particular story or which are replies
# to a particular comment
sub fzListComments {
	my $S = shift;
	my $type = shift; # Can be either "comments" or "replies"
	my $sid = shift;
	my $pid = shift;
	
	# The WHERE clause for the query that returns the comments to list.
	# Either specify that all comments for the story should be returned,
	# or only comments that are replies to a particular comment should be returned.
	my $where_clause = qq|sid = '$sid'|;
	if ($type eq 'replies') { $where_clause .= " AND pid = $pid"; }
	
	# The query that will be used to retrieve the list of replies to the given comment
	my $select_this = {
		ARCHIVE => $S->_check_archivestatus($sid),
		DEBUG => 0,
		WHAT => 'sid, cid, pid',
		FROM => 'comments',
		WHERE => $where_clause ,
		ORDER_BY => 'cid'
	};
	
	# Execute query and retrieve results.
	my ($rv, $sth) = $S->db_select($select_this);

	# Stores the list of comments formatted as an RDF sequence
	my $list;

	# If there are any comments, create the list (otherwise the list is an empty string).
	if ($rv and $rv != 0) {
		# start the list
		$list .= qq|    <fz:$type>\n      <rdf:Seq>\n|;

		# Loop over the comments and add a list item to the list for each one
		while (my $comment = $sth->fetchrow_hashref) {
			$list .= qq|        <rdf:li resource="http://$S->{SERVER_NAME}%%rootdir%%/?op=fzdisplay;action=comment;sid=$comment->{sid};pid=$comment->{pid};cid=$comment->{cid}"/>\n|;
		}

		# end the list
		$list .= qq|      </rdf:Seq>\n    </fz:$type>\n|;
	}
	$sth->finish;
	
	return $list;
}

################################################################################

1;
