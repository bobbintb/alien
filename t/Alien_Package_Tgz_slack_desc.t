use strict;
use warnings;
use Test::More;
use Alien::Package::Tgz;

# Helper function to generate the expected ruler block
sub generate_ruler {
    my ($pkgname) = @_;
    my $screen_width = 72 + length($pkgname);
    my $ruler_header = "# HOW TO EDIT THIS FILE:\n# The \"handy ruler\" below makes it easier to edit a package description.\n# Line up the first '|' above the ':' following the base package name, and\n# the '|' on the right side marks the last column you can put a character in.\n# You must make exactly 11 lines for the formatting to be correct.  It's also\n# customary to leave one space after the ':' except on otherwise blank lines.\n\n";
    my $ruler_gap = ' ' x length($pkgname);
    my $ruler_base = $ruler_gap . "|-----handy-ruler--";
    my $ruler_fill_count = $screen_width - 1 - length($ruler_base);
    $ruler_fill_count = 0 if $ruler_fill_count < 0; # Ensure not negative
    my $ruler_line = $ruler_base . ('-' x $ruler_fill_count) . '|';
    return $ruler_header . $ruler_line . "\n";
}

# Helper to calculate max_content_len for a given pkgname
# $max_total_line_length is $screen_width
# $line_prefix_with_space is "$pkgname: "
sub calculate_max_content_len {
    my ($pkgname) = @_;
    my $screen_width = 72 + length($pkgname);
    my $line_prefix_with_space_len = length($pkgname) + 2; # "$pkgname: "
    my $max_content_len = $screen_width - $line_prefix_with_space_len;
    $max_content_len = 10 if $max_content_len < 10;
    return $max_content_len;
}

my $tests = 0;

# Test Case 1: Basic Structure Test
subtest 'Basic Structure Test' => sub {
    my $pkg = Alien::Package::Tgz->new();
    my $pkgname = "BasicPkg";
    $pkg->name($pkgname);
    $pkg->summary("Simple Summary");
    $pkg->description("This is a short description.");

    my $expected_ruler = generate_ruler($pkgname);
    my $expected_content = <<EOF;
${pkgname}: ${pkgname} (Simple Summary)
${pkgname}:
${pkgname}: This is a short description.
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
EOF
    my $expected_slack_desc = $expected_ruler . $expected_content;

    my $actual_slack_desc = $pkg->_format_slack_desc();
    is($actual_slack_desc, $expected_slack_desc, "Basic structure with short summary and description");
    $tests++;
};

# Test Case 2: Long Description Test (Truncation)
subtest 'Long Description Test (Truncation)' => sub {
    my $pkg = Alien::Package::Tgz->new();
    my $pkgname = "LongDescPkg";
    $pkg->name($pkgname);
    $pkg->summary("Summary Here");
    my $line = "This is a very long line of text that is intended to fill up space. ";
    my $description = ($line x 10); # Roughly 10 lines worth of text if each takes one line
                                    # but wrapping will make it more.
    
    my $expected_ruler = generate_ruler($pkgname);
    my @expected_lines;
    push @expected_lines, "${pkgname}: ${pkgname} (Summary Here)";
    push @expected_lines, "${pkgname}:";

    # For this test, description is a single long string, no newlines.
    # The pre-processing in _format_slack_desc won't change it.
    # _format_slack_desc_section will wrap it.
    my @generated_desc_lines = generate_expected_desc_lines($pkgname, $description, 9);
    push @expected_lines, @generated_desc_lines;
    
    my $expected_content = join("\n", @expected_lines) . "\n";
    my $expected_slack_desc = $expected_ruler . $expected_content;
    
    my $actual_slack_desc = $pkg->_format_slack_desc();
    is($actual_slack_desc, $expected_slack_desc, "Long description causing truncation");
    $tests++;
};

# Test Case 3: Paragraphs Test (Newline Handling)
subtest 'Paragraphs Test (Newline Handling)' => sub {
    my $pkg = Alien::Package::Tgz->new();
    my $pkgname = "ParagraphPkg"; # Length 12
    $pkg->name($pkgname);
    $pkg->summary("Paragraph Test Summary");
    # max_content_len for ParagraphPkg = 72 + 12 - (12 + 2) = 70
    # Input: "Line one. Line two.\n\nNew paragraph after empty line.\nSingle newline here then more text."
    # Pre-processed: "Line one. Line two.\nNew paragraph after empty line. Single newline here then more text."
    $pkg->description("Line one.\nLine two.\n\nNew paragraph after empty line.\nSingle newline here then more text.");

    my $expected_ruler = generate_ruler($pkgname);
    my @expected_lines_arr;
    push @expected_lines_arr, "${pkgname}: ${pkgname} (Paragraph Test Summary)";
    push @expected_lines_arr, "${pkgname}:";
    
    my $processed_desc_for_tc3 = "Line one. Line two.\nNew paragraph after empty line. Single newline here then more text.";
    my @generated_tc3_desc_lines = generate_expected_desc_lines($pkgname, $processed_desc_for_tc3, 9);
    push @expected_lines_arr, @generated_tc3_desc_lines;

    my $expected_content = join("\n", @expected_lines_arr) . "\n";
    my $expected_slack_desc = $expected_ruler . $expected_content;
    my $actual_slack_desc = $pkg->_format_slack_desc();
    is($actual_slack_desc, $expected_slack_desc, "Description with mixed newlines (single becomes space, double becomes para break)");
    $tests++;
};

# Test Case 4: Empty/Whitespace Description Test
subtest 'Empty/Whitespace Description Test' => sub {
    my $pkg = Alien::Package::Tgz->new();
    my $pkgname = "EmptyDescPkg";
    $pkg->name($pkgname);
    $pkg->summary("Summary for Empty Desc");
    $pkg->description("   \n   "); # Whitespace only

    my $expected_ruler = generate_ruler($pkgname);
    my $expected_content = <<EOF;
${pkgname}: ${pkgname} (Summary for Empty Desc)
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
EOF
    my $expected_slack_desc = $expected_ruler . $expected_content;
    my $actual_slack_desc = $pkg->_format_slack_desc();
    is($actual_slack_desc, $expected_slack_desc, "Empty/whitespace description");

    $pkg->description(""); # Completely empty
    $actual_slack_desc = $pkg->_format_slack_desc();
    is($actual_slack_desc, $expected_slack_desc, "Completely empty description");
    $tests++;
};

# Test Case 5: Long Summary Test
subtest 'Long Summary Test' => sub {
    my $pkg = Alien::Package::Tgz->new();
    my $pkgname = "LongSumPkg";
    $pkg->name($pkgname);
    my $long_summary_text = "This is an extremely long summary that is designed to test the wrapping and truncation logic for the summary line itself, hopefully it works as expected.";
    $pkg->summary($long_summary_text);
    $pkg->description("Short desc.");

    my $expected_ruler = generate_ruler($pkgname);
    my $max_content_len_summary = calculate_max_content_len($pkgname);
    
    my $summary_line_content = "${pkgname} (" . $long_summary_text . ")";
    if (length($summary_line_content) > $max_content_len_summary) {
        $summary_line_content = substr($summary_line_content, 0, $max_content_len_summary);
    }
    
    my $expected_content = <<EOF;
${pkgname}: $summary_line_content
${pkgname}:
${pkgname}: Short desc.
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
${pkgname}:
EOF
    my $expected_slack_desc = $expected_ruler . $expected_content;
    my $actual_slack_desc = $pkg->_format_slack_desc();
    is($actual_slack_desc, $expected_slack_desc, "Very long summary causing truncation/wrapping on summary line");
    $tests++;
};

# Test Case 6: Line Length and Wrapping Test (Specific Width)
subtest 'Line Length and Wrapping Test' => sub {
    my $pkg = Alien::Package::Tgz->new();
    my $pkgname = "WrapTest"; # Length 8
    $pkg->name($pkgname);
    $pkg->summary("Wrapping Test");

    # screen_width = 72 + 8 = 80
    # line_prefix_with_space = "WrapTest: " (length 8 + 2 = 10)
    # max_content_len = 80 - 10 = 70
    my $max_content_len = calculate_max_content_len($pkgname); # Should be 70
    is($max_content_len, 70, "Calculated max_content_len for WrapTest is 70");

    my $desc_line1 = "This line has exactly seventy characters to test the full line width."; # 70 chars
    my $desc_line2_part1 = "This part fits"; # 14 chars
    my $desc_line2_part2 = "and this part wraps to the next line because it is too long."; # 60 chars
    
    # Original input: "$desc_line1\n$desc_line2_part1 $desc_line2_part2"
    # Pre-processed: "$desc_line1 $desc_line2_part1 $desc_line2_part2" (single string)
    my $input_desc_tc6 = "$desc_line1 $desc_line2_part1 $desc_line2_part2";
    $pkg->description("$desc_line1\n$desc_line2_part1 $desc_line2_part2"); # Input still has \n

    my $expected_ruler = generate_ruler($pkgname);
    my @expected_lines_arr_tc6;
    push @expected_lines_arr_tc6, "${pkgname}: ${pkgname} (Wrapping Test)";
    push @expected_lines_arr_tc6, "${pkgname}:";

    my @generated_tc6_desc_lines = generate_expected_desc_lines($pkgname, $input_desc_tc6, 9);
    push @expected_lines_arr_tc6, @generated_tc6_desc_lines;
    
    my $expected_content = join("\n", @expected_lines_arr_tc6) . "\n";
    my $expected_slack_desc = $expected_ruler . $expected_content;
    my $actual_slack_desc = $pkg->_format_slack_desc();
    is($actual_slack_desc, $expected_slack_desc, "Specific line length and word wrapping test (single newline in desc becomes space)");
    $tests++;
};

# Test Case 7: User's "ply" Example Test
subtest 'User "ply" Example Test' => sub {
    my $pkg = Alien::Package::Tgz->new();
    my $pkgname = "ply"; # Length 3
    $pkg->name($pkgname);
    $pkg->summary("Light-weight dynamic tracer for Linux");
    
    # max_content_len for ply = 72 + 3 - (3 + 2) = 70
    my $max_content_len = calculate_max_content_len($pkgname);
    is($max_content_len, 70, "Calculated max_content_len for ply is 70");

    my $input_description = <<'DESC_INPUT';
A light-weight dynamic tracer for Linux that leverages the kernel's
BPF
VM in concert with kprobes and tracepoints to attach probes to
arbitrary
points in the kernel.

ply follows the Little Language approach of yore, compiling ply
scripts
into Linux BPF programs that are attached to kprobes and tracepoints
DESC_INPUT
    chomp $input_description; # Remove trailing newline from heredoc

    $pkg->description($input_description);

    # Expected pre-processed description (manual simulation):
    # "A light-weight dynamic tracer for Linux that leverages the kernel's BPF VM in concert with kprobes and tracepoints to attach probes to arbitrary points in the kernel.\nply follows the Little Language approach of yore, compiling ply scripts into Linux BPF programs that are attached to kprobes and tracepoints"
    my $processed_description_ply = "A light-weight dynamic tracer for Linux that leverages the kernel's BPF VM in concert with kprobes and tracepoints to attach probes to arbitrary points in the kernel.\nply follows the Little Language approach of yore, compiling ply scripts into Linux BPF programs that are attached to kprobes and tracepoints";

    my $expected_ruler = generate_ruler($pkgname);
    my @expected_lines_arr_ply;
    push @expected_lines_arr_ply, "${pkgname}: ${pkgname} (Light-weight dynamic tracer for Linux)";
    push @expected_lines_arr_ply, "${pkgname}:";

    my @generated_ply_desc_lines = generate_expected_desc_lines($pkgname, $processed_description_ply, 9);
    push @expected_lines_arr_ply, @generated_ply_desc_lines;

    my $expected_content = join("\n", @generated_ply_desc_lines) . "\n";
     # The join for $expected_content should be on all lines for the slack_desc
    $expected_content = join("\n", @expected_lines_arr_ply) . "\n";


    my $expected_slack_desc = $expected_ruler . $expected_content;
    my $actual_slack_desc = $pkg->_format_slack_desc();
    is($actual_slack_desc, $expected_slack_desc, "User 'ply' example with mixed newlines");
    $tests++;
};


done_testing($tests);

# Helper function to simulate _format_slack_desc_section's wrapping for expected output
sub generate_expected_desc_lines {
    my ($pkgname, $processed_description, $num_lines) = @_;
    my $max_content_len = calculate_max_content_len($pkgname);
    my @output_lines;

    my @paragraphs = split /\n/, $processed_description;

    PARAGRAPH: foreach my $paragraph (@paragraphs) {
        last PARAGRAPH if scalar(@output_lines) >= $num_lines;
        $paragraph =~ s/^\s+|\s+$//g; # Trim whitespace from paragraph

        if ($paragraph eq "" && $processed_description =~ /\n\n/) { # Check if it was an intentional paragraph break
            # Only add a blank line if we haven't reached the target number of lines
            if (scalar(@output_lines) < $num_lines) {
                push @output_lines, "${pkgname}:";
            }
            next PARAGRAPH;
        }
        # If paragraph is empty due to trimming but wasn't from \n\n, it might have been "  \n  "
        # which after pre-proc could be "   ". This should not produce a blank line unless it's the only content.
        # The main logic of splitting words handles empty $paragraph after trim if it wasn't \n\n
        next PARAGRAPH if $paragraph eq "" && !($processed_description =~ /\n\n/ && (split /\n/, $processed_description)[0] eq "");


        my @words = split /\s+/, $paragraph;
        next PARAGRAPH if !@words; # Skip if paragraph had only whitespace and became empty

        my $current_line_content = "";
        WORD_LOOP: foreach my $word (@words) { # Added label
            if (scalar(@output_lines) >= $num_lines && $current_line_content eq "") {
                last PARAGRAPH;
            }

            if (length($word) > $max_content_len) {
                if ($current_line_content ne "") {
                    if (scalar(@output_lines) < $num_lines) {
                        push @output_lines, "${pkgname}: $current_line_content";
                        $current_line_content = "";
                    } else {
                        last PARAGRAPH; 
                    }
                }
                if (scalar(@output_lines) < $num_lines) {
                    push @output_lines, "${pkgname}: " . substr($word, 0, $max_content_len);
                } else {
                    last PARAGRAPH;
                }
                next WORD_LOOP; # continue to next word
            }

            if ($current_line_content eq "") {
                $current_line_content = $word;
            } else {
                my $potential_content = $current_line_content . " " . $word;
                if (length($potential_content) <= $max_content_len) {
                    $current_line_content = $potential_content;
                } else {
                    if (scalar(@output_lines) < $num_lines) {
                        push @output_lines, "${pkgname}: $current_line_content";
                        $current_line_content = $word;
                    } else {
                         $current_line_content = ""; # clear buffer as it won't be used
                        last PARAGRAPH;
                    }
                }
            }
        } # End WORD_LOOP
        
        if ($current_line_content ne "") {
            if (scalar(@output_lines) < $num_lines) {
                push @output_lines, "${pkgname}: $current_line_content";
            }
        }
    } # End PARAGRAPH loop

    # Pad with "$pkgname:" to meet exactly $num_lines
    while (scalar(@output_lines) < $num_lines) {
        push @output_lines, "${pkgname}:";
    }
    # Ensure that if we overshot (should not happen with checks), we truncate
    if (scalar(@output_lines) > $num_lines) {
        @output_lines = @output_lines[0 .. $num_lines - 1];
    }
    return @output_lines;
}
