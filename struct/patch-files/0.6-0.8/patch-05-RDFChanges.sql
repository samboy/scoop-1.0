INSERT INTO vars VALUES ('allow_rdf_fetch', '1', 'If on, then fetches can be done from the admin interface, otherwise they can''t. Turn this on unless you have a problem with adding or refetching feeds, in which case Apache probably needs to be recompiled. This var is a hack to prevent admins from messing up the server when recompiling isn''t an option.', 'bool', 'RDF');

INSERT INTO templates (template_id, opcode) VALUES ('submitrdf_template', 'submitrdf');

UPDATE perm_groups SET group_perms = CONCAT(group_perms,',submit_rdf') WHERE perm_group_id = 'Users' OR perm_group_id = 'Editors';

UPDATE blocks SET block = CONCAT(block, ',\nsubmitrdf') WHERE bid = 'opcodes';

ALTER TABLE rdf_channels ADD COLUMN submitted INT(1);
ALTER TABLE rdf_channels ADD COLUMN submittor VARCHAR(50);

UPDATE box SET content = 'return unless $S->{UI}->{VARS}->{use_rdf_feeds};

INSERT INTO special (pageid, title, description, content) VALUES ('rdf_preview', 'External Feeds Preview', 'Used to preview external feeds\'s boxes.', 'Below is a preview of what the selected feed will look like once it\'s been added. The headlines within it are the current ones.<p>

INSERT INTO box (boxid, title, content, description, template) VALUES ('submit_rdf', 'Submit Feed', 'return "User submitted feeds are disabled. Why not just mail the admin?"

INSERT INTO blocks (bid, block) VALUES ('submit_rdf_message', 'Know of any good sites that syndicate their headlines, but aren\'t carried by this site yet? Well, most likely this is because the admins don\'t know about the site yet, or that they syndicate headlines with RDF. All it takes is for you to find a URL for the site where their RDF file is, and copy it to the form below. Once submitted, and admin will review it, and will either approve it or delete it.');

INSERT INTO blocks (bid, block) VALUES ('submitrdf_template', '<HTML>

INSERT INTO blocks (bid, block) VALUES ('titled_box', '<TABLE BORDER=0 CELLPADDING=0 CELLSPACING=2 WIDTH="100%">\n	<TR>\n		<TD BGCOLOR="%%title_bgcolor%%">%%title_font%%<B>%%title%%</B>%%title_font_end%%</TD>\n	</TR>\n	<TR>\n		<TD>\n			%%content%%\n		</TD>\n	</TR>\n</TABLE>\n');