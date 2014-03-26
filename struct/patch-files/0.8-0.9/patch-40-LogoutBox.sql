INSERT INTO vars VALUES ('logout_url','http://www.mysite.org','This is the url users will be redirected to when they logout','text','General');
INSERT INTO box VALUES ('logout_box','Logout','\r\n$S = $S->reset_user;\r\n\r\nmy $logout_url = $S->{UI}->{VARS}->{logout_url};\r\n\r\nunless( defined( $logout_url ) ) {\r\n  warn \"Hey! Don\'t forget to define the var \'logout_url\' for when your users logout!  Set it to the url that you want them to go to on logout!\";\r\n  $logout_url = $S->{UI}->{VARS}->{site_url} . $S->{UI}->{VARS}->{rootdir};\r\n}\r\n\r\n$S->{APACHE}->header_out( Location => $logout_url );\r\n\r\n# the following is probably unessesary, but just in case...\r\nreturn { content => qq{Redirecting to <a href=\"$logout_url\">$logout_url</a>} }\r\n','This logs a user out.  For /logout','blank_box',0);
UPDATE ops set template = 'blank_template', func = 'logout_box', is_box = 1 where op = 'logout';