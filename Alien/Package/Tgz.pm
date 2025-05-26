#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Tgz - an object that represents a tgz package

=cut

package Alien::Package::Tgz;
use strict;
use base qw(Alien::Package);
use Cwd qw(abs_path);

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

	if ($slack_desc_content && $slack_desc_content =~ /\S/) {
		my @lines = split /\n/, $slack_desc_content;
		my $pkg_name = $this->name();
		my $original_first_line = $lines[0]; # Keep a copy for potential description use
		my $summary_line_processed = 0;

		# Try to parse summary from the first line
		if (@lines && $lines[0] =~ /^$pkg_name:\s*$pkg_name\s*\((.+)\)\s*$/) {
			$this->summary($1);
			shift @lines; # Remove the processed summary line
			$summary_line_processed = 1;
		} elsif (@lines && $lines[0] =~ /^$pkg_name:\s*(.+)$/) {
			my $potential_summary = $1;
			if (length($potential_summary) < 100 && $potential_summary !~ /^[A-Z ]{5,}:\s*.*/) { # Avoid long lines or typical headers
				$this->summary($potential_summary);
				shift @lines; # Remove the processed summary line
				$summary_line_processed = 1;
			} else {
				$this->summary("Converted tgz package");
			}
		} else {
			$this->summary("Converted tgz package");
		}

		my @description_lines;
		my $pkg_name_prefix_regex = qr/^\Q$pkg_name\E:\s*/;
		# Regex for typical headers in slack-desc, case-insensitive for key
		# Matches "KEY:", "KEY WORDS:"
		my $header_regex = qr/^([A-Z][A-Z\s()]+):\s*.*/i;

		my @temp_lines_for_desc;
		if (!$summary_line_processed && $original_first_line) {
		    # If first line was not used for summary, add it to the pool of lines for description processing
		    @temp_lines_for_desc = ($original_first_line, @lines);
		} else {
		    @temp_lines_for_desc = @lines;
		}
		
		foreach my $line (@temp_lines_for_desc) {
			my $cleaned_line = $line;
			$cleaned_line =~ s/$pkg_name_prefix_regex//;

			if ($cleaned_line =~ $header_regex) {
				# Check if the part before colon looks like a standard header key
				my $header_key = $1;
				my @standard_headers = ("PACKAGE NAME", "PACKAGE LOCATION", "PACKAGE SIZE (COMPRESSED)", 
				                        "PACKAGE SIZE (UNCOMPRESSED)", "PACKAGE REQUIRED", "PACKAGE SUGGESTS", 
				                        "PACKAGE CONFLICTS", "PACKAGE PROVIDES", "PACKAGE TAGS");
				my $is_standard_header = 0;
				foreach my $sh (@standard_headers) {
				    if (uc($header_key) eq $sh) {
				        $is_standard_header = 1;
				        last;
				    }
				}
				if ($is_standard_header) {
				    next; # Skip standard header lines
				}
			}
			
			if ($line eq $pkg_name.":" || $line eq $pkg_name.": ") {
			    push @description_lines, ""; 
			} else {
			    push @description_lines, $cleaned_line;
			}
		}

		# Remove leading/trailing empty lines from the description block
		while (@description_lines && $description_lines[0] !~ /\S/) {
		    shift @description_lines;
		}
		while (@description_lines && $description_lines[-1] !~ /\S/) {
		    pop @description_lines;
		}

		my $final_description = join("\n", @description_lines);

		if ($final_description =~ /\S/) {
			$this->description($final_description);
		} else {
			# Fallback if description is empty after parsing
			# If summary was also default, this keeps the original fallback
			$this->description($this->summary()); 
		}
		
		# Refine summary if it's still default but we have a good description
		if ($this->summary() eq "Converted tgz package" && $final_description =~ /\S/ && $this->description() ne "Converted tgz package") {
		    my ($first_desc_line) = split /\n/, $final_description;
		    # Ensure first_desc_line is not empty and is reasonably short for a summary
		    if ($first_desc_line && $first_desc_line =~ /\S/ && length($first_desc_line) < 100 && length($first_desc_line) > 5) { 
		        $this->summary($first_desc_line);
		    }
		}
		# If description is multi-line but summary is identical to the whole description, try to shorten summary.
		if (index($this->description(), "\n") != -1 && $this->summary() eq $this->description()) {
		    my ($first_desc_line) = split /\n/, $this->description();
		     if ($first_desc_line && $first_desc_line =~ /\S/ && length($first_desc_line) < 100 && length($first_desc_line) > 5) {
		        $this->summary($first_desc_line);
		     }
		}


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

sub _format_slack_desc {
	my $this = shift;

	my $pkg_name = $this->name() || "unknown";
	my $version = $this->version() || "0.0";
	my $arch = $this->arch();
	$arch = 'noarch' if !$arch || $arch eq 'all'; # Slackware often uses 'noarch'
	my $release = $this->release() || "1"; # Default release
	
	my $summary_text = $this->summary() || "No summary available.";
	# Remove "Converted tgz package" if it's still the summary and a better one wasn't found
	if ($summary_text eq "Converted tgz package" && $this->description() && $this->description() ne "Converted tgz package") {
	    my ($first_desc_line) = split /\n/, $this->description();
	    if ($first_desc_line && length($first_desc_line) < 100 && length($first_desc_line) > 5) {
	        $summary_text = $first_desc_line;
	    }
	}
	# Ensure summary doesn't contain newlines for the header line
	$summary_text =~ s/\n.*//s;


	my $description_text = $this->description() || "No detailed description available.";
	if ($description_text eq $summary_text && $summary_text eq "Converted tgz package") {
	    $description_text = "This is a tgz package converted by alien."; # A bit more descriptive default
	}


	my $filename = "$pkg_name-$version-$arch-$release.tgz";

	my $header = <<'EOF';
# HOW TO EDIT THIS FILE:
# The script REGENERATES this file description from the files
# contents in the package. For this reason, you should edit
# the files contents BEFORE running the package generator.
#
# The file is a standard slack-desc file. It contains a
# description of the package. It will be installed in
# /var/log/packages/ and can be viewed using pkgtool.
#
# Lines that begin with '#' are comments and will be ignored.
# The first non-comment line should be the package name,
# version, and a short description, formatted like this:
#
#<pkgname>: <pkgname> (This is a short description of the package)
#
# The rest of the lines are a more detailed description of the
# package. They should be formatted like this:
#
#<pkgname>: This is a line of the detailed description. All lines
#<pkgname>: of the description should be prefixed with the
#<pkgname>: package name, followed by a colon and a space.
#<pkgname>:
#<pkgname>: This is another paragraph of the description.
#
EOF
	chomp $header; # Remove trailing newline from heredoc

	my @slack_desc_lines;
	push @slack_desc_lines, $header;
	push @slack_desc_lines, ""; # Empty line after header
	push @slack_desc_lines, "PACKAGE NAME: $filename";
	push @slack_desc_lines, "PACKAGE LOCATION: ./";
	# Other PACKAGE fields like SIZE could be added here if available
	push @slack_desc_lines, ""; # Empty line before main description

	# Summary line
	push @slack_desc_lines, "$pkg_name: $pkg_name ($summary_text)";
	
	# Description lines
	my @desc_paras = split /\n/, $description_text; # Simple split, treat each line as a potential paragraph start for now
                                                    # More sophisticated paragraph handling might be needed if original desc has \n\n

	my $line_prefix = "$pkg_name: ";
	my $max_len = 72; # Target maximum line length for slack-desc

	if (!@desc_paras || (@desc_paras == 1 && $desc_paras[0] eq $summary_text) || $description_text eq "No detailed description available." || $description_text eq "This is a tgz package converted by alien.") {
	    # If description is same as summary or default, add a generic line or two.
	    if ($description_text ne $summary_text) { # only add if not redundant with summary line
	        push @slack_desc_lines, "$line_prefix"; # Empty paragraph line
	        push @slack_desc_lines, $line_prefix . $description_text;
	    }
	} else {
	    push @slack_desc_lines, "$line_prefix"; # Start with an empty paragraph line after summary.
	    foreach my $para_line (@desc_paras) {
	        if ($para_line =~ /^\s*$/) { # Original empty line, treat as paragraph separator
	            push @slack_desc_lines, $line_prefix;
	            next;
	        }

	        my $current_line = $line_prefix . $para_line;
	        while (length($current_line) > $max_len) {
	            my $breakpoint = -1;
	            # Try to find a space to break at, within the allowed length
	            # Search backwards from $max_len - length($line_prefix) in the non-prefixed part
	            my $search_part = substr($current_line, length($line_prefix), $max_len - length($line_prefix));
	            $breakpoint = rindex($search_part, ' ');

	            if ($breakpoint > 0) { # Found a space
	                push @slack_desc_lines, substr($current_line, 0, length($line_prefix) + $breakpoint);
	                $current_line = $line_prefix . substr($current_line, length($line_prefix) + $breakpoint + 1);
	            } else { # No space found, hard break (should be rare with typical text)
	                push @slack_desc_lines, substr($current_line, 0, $max_len);
	                $current_line = $line_prefix . substr($current_line, $max_len);
	            }
	        }
	        push @slack_desc_lines, $current_line; # Add the remainder or the full line if it was short enough
	    }
	}
	return join("\n", @slack_desc_lines) . "\n"; # Ensure trailing newline
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
	my $tgz=$this->name."-".$this->version.".tgz";

	$this->do("cd ".$this->unpacked_tree."; tar czf ../$tgz .")
		or die "Package build failed";

	return $tgz;
}

=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
