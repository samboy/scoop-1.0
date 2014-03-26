INSERT INTO admin_tools VALUES('search', '50', 'Search Admin Tools', 'Search Admin Tools', 'admin_search', 'admin_search', '1');
UPDATE vars SET value = CONCAT(value, ",\nadmin_search") WHERE name='perms';
UPDATE perm_groups SET group_perms = CONCAT(group_perms, ',admin_search') WHERE perm_group_id='Superuser' OR perm_group_id='Admins';
INSERT INTO box (boxid, title, content, description, template) VALUES ('admin_search', 'Search Admin Tools', '# search terms?\r\nmy $query = $S->cgi->param(\'query\');\r\n\r\n# search where?\r\n# extract the chosen search locations\r\nmy $search_param = $S->cgi->param(\'search_in\');\r\nmy %search_in;\r\nmy $searches_selected = 0;\r\nforeach (ref($search_param) eq \'ARRAY\' ? @{$search_param} : ($search_param)) {\r\n	next unless $_;\r\n	$search_in{$_} = 1;\r\n	$searches_selected++;\r\n}\r\n\r\n# if they didn\'t select any searches, or this is a fresh load, then select all\r\nunless ($searches_selected) {\r\n	foreach (qw(blockval blockdesc boxval boxdesc specval vardesc)) {\r\n		$search_in{$_} = 1;\r\n	}\r\n}\r\n\r\nmy ($blockval, $blockdesc, $boxval, $boxdesc, $specval, $vardesc) = "";\r\nmy ($blocksearchwhere, $boxsearchwhere, $specsearchwhere, $varsearchwhere) = "";\r\nmy ($type_phrase, $type_any, $type_all) = "";\r\n\r\n# remember what was previously selected. yes, this is kind of ugly\r\n$blockval  = \' selected="selected"\' if $search_in{blockval};\r\n$blockdesc = \' selected="selected"\' if $search_in{blockdesc};\r\n$boxval    = \' selected="selected"\' if $search_in{boxval};\r\n$boxdesc   = \' selected="selected"\' if $search_in{boxdesc};\r\n$specval   = \' selected="selected"\' if $search_in{specval};\r\n$vardesc   = \' selected="selected"\' if $search_in{vardesc};\r\n\r\n# same thing for search type, though set a default of all\r\nif ($S->cgi->param(\'search_type\') eq \'phrase\') {\r\n	$type_phrase = \' checked="checked"\';\r\n} elsif($S->cgi->param(\'search_type\') eq \'all\') {\r\n	$type_all = \' checked="checked"\';\r\n} elsif($S->cgi->param(\'search_type\') eq \'any\') {\r\n	$type_any = \' checked="checked"\';\r\n} else {\r\n	$type_all = \' checked="checked"\';\r\n}\r\n\r\n# set up search fields\r\nmy $search_for_field = qq{<input type="text" name="query" value="$query" /><input type="submit" value="Search" />};\r\n\r\nmy $search_in_field = \'<select name="search_in" multiple="multiple" size="6">\';\r\n$search_in_field .= qq{\r\n	<option value="blockval"$blockval>Block values</option>\r\n	<option value="blockdesc"$blockdesc>Block descriptions</option>} if $S->have_perm(\'edit_blocks\');\r\n\r\n$search_in_field .= qq{\r\n	<option value="boxval"$boxval>Box code</option>\r\n	<option value="boxdesc"$boxdesc>Box descriptions</option>} if $S->have_perm(\'edit_boxes\');\r\n\r\n$search_in_field .= qq{\r\n	<option value="specval"$specval>Special Pages</option>} if $S->have_perm(\'edit_special\');\r\n\r\n$search_in_field .= qq{\r\n	<option value="vardesc"$vardesc>Site Controls descriptions</option>} if $S->have_perm(\'edit_vars\');\r\n\r\n$search_in_field .= "\\n</select>";\r\n\r\nmy $search_opt_field = qq{<input type="radio" name="search_type" value="all"$type_all /> All words<br />\r\n<input type="radio" name="search_type" value="any"$type_any /> Any words<br />\r\n<input type="radio" name="search_type" value="phrase"$type_phrase /> Phrase};\r\n\r\nmy $content .= qq{\r\n<form method="get" action="%%rootdir%%/admin/search">\r\n<table border="0">\r\n	<tr>\r\n		<td valign="top" rowspan="2">%%norm_font%%Search in:<br />$search_in_field%%norm_font_end%%</td>\r\n		<td>%%norm_font%%Search for:<br />$search_for_field%%norm_font_end%%</td>\r\n	</tr>\r\n	<tr>\r\n		<td>%%norm_font%%$search_opt_field%%norm_font_end%%</td>\r\n	</tr>\r\n</table>\r\n</form>\r\n   };\r\n\r\nif ($query) {\r\n	my ($blockresults, $boxresults, $specresults, $varresults) = ("","","","");\r\n\r\n	# of the three column names which might be needed, these are used\r\n	# repeatedly, so stick them in a var instead of re-building them\r\n	my $content_string = &search_string($S, $query, \'content\');\r\n	my $desc_string    = &search_string($S, $query, \'description\');\r\n\r\n	$blocksearchwhere .= &search_string($S, $query, \'block\') if ($blockval);\r\n	$blocksearchwhere .= \' OR \' if ($blockdesc && $blockval);\r\n	$blocksearchwhere .= $desc_string if ($blockdesc);\r\n	$boxsearchwhere   .= $content_string if ($boxval);\r\n	$boxsearchwhere   .= \' OR \' if ($boxdesc && $boxval);\r\n	$boxsearchwhere   .= $desc_string if ($boxdesc);\r\n	$specsearchwhere  .= $content_string if ($specval);\r\n	$varsearchwhere   .= $desc_string if ($vardesc);\r\n\r\n	if ($blocksearchwhere && $S->have_perm(\'edit_blocks\')) {\r\n		my ($rv, $sth) = $S->db_select({\r\n			WHAT  => \'bid,description,theme\',\r\n			FROM  => \'blocks\',\r\n			WHERE => $blocksearchwhere\r\n		});\r\n		while (my $rec = $sth->fetchrow_hashref) {\r\n			my $desc = $rec->{description} || "<i>(no description)</i>";\r\n			$blockresults .= qq{\r\n	<dt><a href="%%rootdir%%/admin/blocks/edit/$rec->{theme}/$rec->{bid}">$rec->{bid}</a></dt>\r\n	<dd>$desc</dd>}\r\n		}\r\n		$blockresults = "<dl> $blockresults </dl>" if $blockresults;\r\n	}\r\n\r\n	if ($boxsearchwhere && $S->have_perm(\'edit_boxes\')) {\r\n		my ($rv, $sth) = $S->db_select({\r\n			WHAT  => \'boxid, description\',\r\n			FROM  => \'box\',\r\n			WHERE => $boxsearchwhere\r\n		});\r\n		while (my $rec = $sth->fetchrow_hashref) {\r\n			my $desc = $rec->{description} || "<i>(no description)</i>";\r\n			$boxresults .= qq{\r\n	<dt><a href="%%rootdir%%/admin/boxes/$rec->{boxid}">$rec->{boxid}</a></dt>\r\n	<dd>$desc</dd>}\r\n		}\r\n		$boxresults = "<dl> $boxresults </dl>" if $boxresults;\r\n	}\r\n\r\n	if ($specsearchwhere && $S->have_perm(\'edit_special\')) {\r\n		my ($rv, $sth) = $S->db_select({\r\n			WHAT => \'pageid,title,description\',\r\n			FROM => \'special\',\r\n			WHERE => $specsearchwhere\r\n		});\r\n		while (my $rec = $sth->fetchrow_hashref) {\r\n			my $desc = $rec->{description} || "<i>(no description)</i>";\r\n			$specresults .= qq{\r\n	<dt><a href="%%rootdir%%/admin/special?id=$rec->{pageid}">$rec->{title}</a></dt>\r\n	<dd>$desc</dd>}\r\n		}\r\n		$specresults = "<dl> $specresults </dl>" if $specresults;\r\n	}\r\n\r\n	if ($varsearchwhere && $S->have_perm(\'edit_vars\')) {\r\n		my ($rv, $sth) = $S->db_select({\r\n			WHAT => \'name,description\',\r\n			FROM => \'vars\',\r\n			WHERE => $varsearchwhere\r\n		});\r\n		while (my $rec = $sth->fetchrow_hashref) {\r\n			my $desc = $rec->{description} || "<i>(no description)</i>";\r\n			$varresults .= qq{\r\n	<dt><a href="%%rootdir%%/admin/vars/edit/$rec->{name}">$rec->{name}</a></dt>\r\n	<dd>$desc</dd>}\r\n		}\r\n		$varresults = "<dl> $varresults </dl>" if $varresults;\r\n	}\r\n\r\n	$content .= "<H3>Blocks found:</H3>\\n%%norm_font%%$blockresults%%norm_font_end%%" if $blockresults;\r\n	$content .= "<H3>Boxes found:</H3>\\n%%norm_font%%$boxresults%%norm_font_end%%" if $boxresults;\r\n	$content .= "<H3>Special Pages found:</H3>\\n%%norm_font%%$specresults%%norm_font_end%%" if $specresults;\r\n	$content .= "<H3>Site Controls found:</H3>\\n%%norm_font%%$varresults%%norm_font_end%%" if $varresults;\r\n	unless ($varresults || $blockresults || $boxresults || $specresults) {\r\n		$content .= "%%norm_font%%Nothing matching your search phrase was found in the selected tools.%%norm_font_end%%";\r\n	}\r\n}\r\n\r\n$content = "<table width=\\"100%\\">\r\n	<tr width=\\"100%\\" bgcolor=\\"%%title_bgcolor%%\\"><td>%%title_font%%Search Admin Tools%%title_font_end%%</td></tr>\r\n	<tr><td>$content</td></tr>\r\n</table>";\r\n\r\nreturn $content;\r\n\r\nsub search_string {\r\n	my ($S, $query, $field) = @_;\r\n\r\n	my $search_string;\r\n	if ($S->cgi->param(\'search_type\') eq \'phrase\') {\r\n		# easy enough\r\n		$search_string = "$field LIKE " . $S->dbh->quote("%${query}%");\r\n	} else {\r\n		while ($query =~ /([\\w-]+)/g) {\r\n			if ($search_string) {\r\n				$search_string .= \' AND \'\r\n					if $S->cgi->param(\'search_type\') eq \'all\';\r\n				$search_string .= \' OR \'\r\n					if $S->cgi->param(\'search_type\') eq \'any\';\r\n			}\r\n			$search_string .= "$field LIKE " . $S->dbh->quote("%${1}%");\r\n		}\r\n	}\r\n\r\n	return "($search_string)";\r\n}\r\n', 'Simple admin search tool for locating blocks by content or description. This is called from the admin tools menu.', 'blank_box');