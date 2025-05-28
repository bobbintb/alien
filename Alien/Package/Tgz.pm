#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Tgz - an object that represents a tgz package

=cut

package Alien::Package::Tgz;
use strict;
use base qw(Alien::Package);
use Cwd qw(abs_path);
use Alien::Package::Rpm qw(arch);

my $tarext=qr/\.(?:tgz|tar(?:\.(?:gz|Z|z|bz|bz2))?|taz)$/;

=head1 DESCRIPTION

This is an object class that represents a tgz package, as used in Slackware. 
It also allows conversion of raw tar files.
It is derived from Alien::Package.

=head1 CLASS DATA

=over 4

=item scripttrans

Translation table between canoical script names and the names used in
tgz's.

=cut

use constant scripttrans => {
		postinst => 'doinst.sh',
		postrm => 'delete.sh',
		prerm => 'predelete.sh',
		preinst => 'predoinst.sh',
	};

=back

=head1 METHODS

=over 4

=item checkfile

Detect tgz files by their extension.

=cut

sub checkfile {
        my $this=shift;
        my $file=shift;

        return $file =~ m/$tarext$/;
}

=item install

Install a tgz with installpkg. Pass in the filename of the tgz to install.

installpkg (a slackware program) is used because I'm not sanguine about
just untarring a tgz file. It might trash a system.

=cut

sub install {
	my $this=shift;
	my $tgz=shift;

	if (-x "/sbin/installpkg") {
		my $v=$Alien::Package::verbose;
		$Alien::Package::verbose=2;
		$this->do("/sbin/installpkg", "$tgz")
			or die "Unable to install";
		$Alien::Package::verbose=$v;
	}
	else {
		die "Sorry, I cannot install the generated .tgz file because /sbin/installpkg is not present. You can use tar to install it yourself.\n"
	}
}

=item scan

Scan a tgz file for fields. Has to scan the filename for most of the
information, since there is little useful metadata in the file itself.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::scan(@_);
	my $file=$this->filename;

	# Get basename of the filename.
	my ($basename)=('/'.$file)=~m#^/?.*/(.*?)$#;

	# Strip out any tar extensions.
	$basename=~s/$tarext//;

	if ($basename=~m/([\w-]+)-([0-9\.?]+).*/) {
		$this->name($1);
		$this->version($2);
	}
	else {
		$this->name($basename);
		$this->version(1);
	}

	$this->arch('all');

	# Attempt to extract slack-desc
	my $slack_desc_content = $this->runpipe(1, "tar Oxf '$file' install/slack-desc 2>/dev/null");
	my $pkg_name = $this->name(); # Get package name early

	if ($slack_desc_content && $slack_desc_content =~ /\S/) {
		my @slack_lines = split /\n/, $slack_desc_content;
		
		# Default values if parsing fails or parts are missing
		my $default_summary_text = "Package from tgz file (slack-desc found)";
		my $default_description_text = "Package from tgz file (slack-desc found)";
		$this->summary($default_summary_text);
		$this->description($default_description_text);

		my $summary_parsed_successfully = 0;

		if (@slack_lines) {
			my $first_line = $slack_lines[0]; # Peek at first line
			# Try to parse summary from the first line using the strict format
			if ($first_line =~ /^\Q$pkg_name\E: \Q$pkg_name\E \((.+)\)\s*$/) {
				my $summary_candidate = $1;
				if ($summary_candidate =~ /\S/) { # Check if captured summary is not just whitespace
					$this->summary($summary_candidate);
					$this->description($summary_candidate); # Initial guess for description
					shift @slack_lines; # Consume the line as it was successfully parsed
					$summary_parsed_successfully = 1;
				}
			}
		}
		
		# Description Parsing from remaining lines (or all lines if summary parse failed)
		my @description_parts;
		my $expected_prefix_regex = qr/^\Q$pkg_name\E: /; # $pkg_name: <text>
		my $paragraph_break_regex = qr/^\Q$pkg_name\E:$/;  # $pkg_name:

		foreach my $line (@slack_lines) {
			if ($line =~ $paragraph_break_regex) {
				push @description_parts, ""; # Paragraph break
			} elsif ((my $desc_content = $line) =~ s/$expected_prefix_regex//) {
				# Prefix was stripped, $desc_content now holds the rest
				push @description_parts, $desc_content;
			} else {
				# Line does not match strict format, ignore it for description.
				# This handles cases where the first line was not a valid summary
				# and is now being re-evaluated here but doesn't fit description format either.
			}
		}

		if (@description_parts) {
			my $parsed_description = join("\n", @description_parts);
			# Remove leading/trailing empty lines from the final description block
			$parsed_description =~ s/^\n+//;
			$parsed_description =~ s/\n+$/\n/; # Keep single trailing newline if content, or make it one if many
            $parsed_description =~ s/\s+$//; # Trim trailing whitespace overall, including last newline if it was just that

			if ($parsed_description =~ /\S/) {
				$this->description($parsed_description);
				# If summary is still the generic default, but we have a description,
				# try to set summary from the first line of this description.
				if ($this->summary() eq $default_summary_text) {
					my ($first_desc_line) = split /\n/, $parsed_description;
					if ($first_desc_line && length($first_desc_line) < 100 && $first_desc_line =~ /\S/) {
						$this->summary($first_desc_line);
					}
				}
			} else {
			    # Description parts were found but resulted in an empty string (e.g. only paragraph markers)
			    # Revert to summary if summary was good, or default if summary was also default.
			    if ($summary_parsed_successfully) {
			        $this->description($this->summary());
			    } else {
			        $this->description($default_description_text); # Keep default
			    }
			}
		} elsif (!$summary_parsed_successfully) {
            # No description parts AND summary was not parsed successfully means slack-desc was
            # present but entirely unparsable or empty after the first line (if any).
            # Summary and Description remain $default_summary_text.
        }
        # If summary was parsed but no description lines, description is already set to summary.

	} else {
		# Original behavior if slack-desc is not found or empty
		$this->summary("Converted tgz package");
		$this->description($this->summary);
	}

	$this->copyright('unknown');
	$this->release(1);
	$this->distribution("Slackware/tarball");
	$this->group("unknown");
	$this->origformat('tgz');
	$this->changelogtext('');
	$this->binary_info($this->runpipe(0, "ls -l '$file'"));

	# Now figure out the conffiles. Assume anything in etc/ is a
	# conffile.
	my @conffiles;
	open (FILELIST,"tar vtf $file | grep etc/ |") ||
		die "getting filelist: $!";
	while (<FILELIST>) {
		# Make sure it's a normal file. This is looking at the
		# permissions, and making sure the first character is '-'.
		# Ie: -rw-r--r--
		if (m:^-:) {
			# Strip it down to the filename.
			m/^(.*) (.*)$/;
			push @conffiles, "/$2";
		}
	}
	$this->conffiles(\@conffiles);

	# Now get the whole filelist. We have to add leading /'s to the
	# filenames. We have to ignore all files under /install/
	my @filelist;
	open (FILELIST, "tar tf $file |") ||
		die "getting filelist: $!";
	while (<FILELIST>) {
		chomp;
		unless (m:^install/:) {
			push @filelist, "/$_";
		}
	}
	$this->filelist(\@filelist);

	# Now get the scripts.
	foreach my $script (keys %{scripttrans()}) {
		$this->$script(scalar $this->runpipe(1, "tar Oxf '$file' install/${scripttrans()}{$script} 2>/dev/null"));
	}

	return 1;
}

=item unpack

Unpack tgz.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);
	my $file=abs_path($this->filename);

	$this->do("cd ".$this->unpacked_tree."; tar xpf $file")
		or die "Unpacking of '$file' failed: $!";
	# Delete the install directory that has slackware info in it.
	$this->do("cd ".$this->unpacked_tree."; rm -rf ./install");

	return 1;
}

# Helper function for _format_slack_desc
sub _format_slack_desc_section {
    my ($pkgname, $text_content, $num_target_lines, $max_total_line_length) = @_;

    my $line_prefix_with_space = "$pkgname: ";
    my $line_prefix_no_space = "$pkgname:";
    # Max length for the actual content, after the prefix
    my $max_content_len = $max_total_line_length - length($line_prefix_with_space);
    # Ensure max_content_len is somewhat reasonable if pkgname is very long
    $max_content_len = 10 if $max_content_len < 10;

    my @formatted_lines;
    $text_content = "" if !defined $text_content; # Ensure defined

    my @paragraphs = split /\n/, $text_content;

    PARAGRAPH: foreach my $paragraph (@paragraphs) {
        if (scalar(@formatted_lines) >= $num_target_lines) {
            last PARAGRAPH;
        }

        $paragraph =~ s/^\s+|\s+$//g; # Trim whitespace from paragraph

        if ($paragraph eq "") {
            # This handles intentional paragraph breaks (empty lines in input)
            if (scalar(@formatted_lines) < $num_target_lines) {
                push @formatted_lines, $line_prefix_no_space;
            }
            next PARAGRAPH;
        }

        my @words = split /\s+/, $paragraph;
        next PARAGRAPH if !@words; # Skip if paragraph had only whitespace

        my $current_line_content = "";

        foreach my $word (@words) {
            if (scalar(@formatted_lines) >= $num_target_lines && $current_line_content eq "") {
                # Target lines reached, and no pending content for the current paragraph line.
                last PARAGRAPH;
            }
            if (scalar(@formatted_lines) >= $num_target_lines && $current_line_content ne "") {
                # Target lines reached, but there's pending content. Try to push it.
                # This case should ideally be caught before starting a new word if possible,
                # but acts as a safeguard.
                # The main check before adding to @formatted_lines will handle this.
            }


            # Handle very long words: truncate and place on its own line
            if (length($word) > $max_content_len) {
                # If there's content in the buffer, push it first
                if ($current_line_content ne "") {
                    if (scalar(@formatted_lines) < $num_target_lines) {
                        push @formatted_lines, $line_prefix_with_space . $current_line_content;
                        $current_line_content = "";
                    } else {
                        last PARAGRAPH; # No space for this buffered line
                    }
                }
                # Now push the truncated long word
                if (scalar(@formatted_lines) < $num_target_lines) {
                    push @formatted_lines, $line_prefix_with_space . substr($word, 0, $max_content_len);
                } else {
                    last PARAGRAPH; # No space for the long word line
                }
                next; # Word handled, move to the next word in the paragraph
            }

            # Regular word processing
            if ($current_line_content eq "") {
                $current_line_content = $word;
            } else {
                my $potential_content = $current_line_content . " " . $word;
                if (length($potential_content) <= $max_content_len) {
                    $current_line_content = $potential_content;
                } else {
                    # Word doesn't fit, so push the current line
                    if (scalar(@formatted_lines) < $num_target_lines) {
                        push @formatted_lines, $line_prefix_with_space . $current_line_content;
                        $current_line_content = $word; # Start new line with current word
                    } else {
                        # No space for this line, and we have a word that needs to start a new line.
                        # This means we must stop processing this paragraph.
                        $current_line_content = ""; # Discard current word as it won't fit
                        last PARAGRAPH;
                    }
                }
            }
        } # End foreach my $word

        # After processing all words in a paragraph, if there's remaining content, push it
        if ($current_line_content ne "") {
            if (scalar(@formatted_lines) < $num_target_lines) {
                push @formatted_lines, $line_prefix_with_space . $current_line_content;
            }
            # If no space, the remaining content of this paragraph is truncated.
        }
    } # End PARAGRAPH loop

    # Final padding or truncation to meet exactly $num_target_lines
    while (scalar(@formatted_lines) < $num_target_lines) {
        push @formatted_lines, $line_prefix_no_space;
    }
    # Ensure that if we overshot, we truncate back to num_target_lines
    if (scalar(@formatted_lines) > $num_target_lines) {
        @formatted_lines = @formatted_lines[0 .. $num_target_lines - 1];
    }

    return @formatted_lines;
}

sub _format_slack_desc {
	my $this = shift;

	my $pkgname = $this->name() || "unknown"; # Should usually be defined
	my $summary = $this->summary();
	my $description = $this->description();
	# Homepage URL removed as per new requirements

	# Ensure summary is a single, trimmed line
	$summary = "" if !defined $summary;
	$summary =~ s/\n.*//s;    # Keep only the first line
	$summary =~ s/^\s+|\s+$//g; # Trim whitespace
	$summary = "No summary" if $summary eq "";


	$description = "" if !defined $description;
    # Pre-process description to handle newlines for flowing text vs. paragraph breaks
    # 1. Replace double (or more) newlines with a placeholder
    $description =~ s/\n\n+/_PARAGRAPH_BREAK_/g;
    # 2. Replace remaining single newlines with spaces
    $description =~ s/\n/ /g;
    # 3. Convert placeholder back to a single newline for actual paragraph breaks
    $description =~ s/_PARAGRAPH_BREAK_/\n/g;
    # Now, $description has single newlines only for intended paragraph breaks.
    # Other newlines that were for readability are now spaces.

	my $screen_width = 72 + length($pkgname);

	my $ruler_header = "# HOW TO EDIT THIS FILE:\n# The \"handy ruler\" below makes it easier to edit a package description.\n# Line up the first '|' above the ':' following the base package name, and\n# the '|' on the right side marks the last column you can put a character in.\n# You must make exactly 11 lines for the formatting to be correct.  It's also\n# customary to leave one space after the ':' except on otherwise blank lines.\n\n";
	
	my $ruler_gap = ' ' x length($pkgname);
	my $ruler_base = $ruler_gap . "|-----handy-ruler--";
	# Screen width is total, ruler includes the final '|', so -1 from screen_width for filling
	my $ruler_fill_count = $screen_width - 1 - length($ruler_base);
	$ruler_fill_count = 0 if $ruler_fill_count < 0; # Ensure not negative
	my $ruler_line = $ruler_base . ('-' x $ruler_fill_count) . '|';

	my $complete_ruler_block = $ruler_header . $ruler_line . "\n";

	# Section 1: Summary (1 line)
	# The format "$pkgname ($summary)" is part of the text_content for this section
	my $summary_content_for_section = "$pkgname ($summary)";
	my @summary_section = _format_slack_desc_section($pkgname, $summary_content_for_section, 1, $screen_width);

	# Section 2: Empty line (1 line)
	# This is effectively an empty paragraph
	my @empty_section = _format_slack_desc_section($pkgname, "", 1, $screen_width);
    # Ensure it's just "$pkgname:" as per spec for empty lines
    $empty_section[0] = "$pkgname:" if @empty_section;


	# Section 3: Description (9 lines) - Adjusted from 8 to 9
	my @description_section = _format_slack_desc_section($pkgname, $description, 9, $screen_width);

	# Section 4: Homepage (REMOVED)

	my $all_content_lines = join("\n", @summary_section, @empty_section, @description_section);
	
	return $complete_ruler_block . $all_content_lines . "\n";
}

=item prep

Adds a populated install directory to the build tree.

=cut

sub prep {
	my $this=shift;
	my $dir=$this->unpacked_tree || die "The package must be unpacked first!";
	my $install_dir = $dir."/install";
	my $install_made=0;

	# Check if install directory already exists (e.g. from unpacking)
	if (-d $install_dir) {
	    $install_made = 1;
	}

	# Generate and write slack-desc if description is meaningful
	my $description = $this->description();
	my $summary = $this->summary();
	if (defined $description && $description =~ /\S/ && $description ne "Converted tgz package" && $description ne $summary) {
		my $slack_desc_content = $this->_format_slack_desc();
		if ($slack_desc_content && $slack_desc_content =~ /\S/) {
			if (!$install_made) {
				mkdir($install_dir, 0755) 
					|| die "unable to mkdir $install_dir: $!";
				$install_made=1;
			}
			my $slack_desc_path = $install_dir."/slack-desc";
			open (SLACKDESC, ">$slack_desc_path") || die "Unable to open $slack_desc_path for writing: $!";
			print SLACKDESC $slack_desc_content;
			close SLACKDESC;
			chmod(0644, $slack_desc_path) || $this->warn("Could not chmod $slack_desc_path: $!");
		}
	}

	if ($this->usescripts) {
		foreach my $script (keys %{scripttrans()}) {
			my $data=$this->$script();
			my $out=$install_dir."/".${scripttrans()}{$script};
			next if ! defined $data || $data =~ m/^\s*$/;
			if (!$install_made) {
				mkdir($install_dir, 0755) 
					|| die "unable to mkdir $install_dir: $!";
				$install_made=1;
			}
			open (OUT, ">$out") || die "$out: $!";
			print OUT $data;
			close OUT;
			$this->do("chmod", 755, $out);
		}
	}
}

=item build

Build a tgz.

=cut

sub build {
	my $this=shift;
	my $arch = Alien::Package::Rpm::arch($this, @_);
	my $tgz=$this->name."-".$this->version."-".$arch."-1_alien.tgz";
	if (-x "/sbin/makepkg") {
		my $v=$Alien::Package::verbose;
		$Alien::Package::verbose=2;
		$this->do("cd ".$this->unpacked_tree."; makepkg -l y -c n ../$tgz .")
			or die "Unable to make pkg";
		$Alien::Package::verbose=$v;
	}
	else {
		die "Sorry, I cannot generate the .tgz file because /sbin/makepkg is not present.\n"
	}
	return $tgz;
}

=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
