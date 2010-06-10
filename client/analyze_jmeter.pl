#!/usr/bin/perl

# parse a jmeter result/transaction logfile and create a summary or plotfile depending on what is asked for

####################################################################################################################

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use POSIX qw(ceil floor);
use File::Basename;

####################################################################################################################

my $label_column_width = -40;
my $data_column_width = 15;
my $data_column_offset = 3;
my $float_column_width = $data_column_width + $data_column_offset;
my $offset_column_width = $float_column_width + 1;

sub print_line($ $) {
    my $fp = shift;
    my $arg = shift;

    printf $fp ("%s\n", $arg);
}

sub print_float($ $ $) {
    my $fp = shift;
    my $arg1 = shift;
    my $arg2 = shift;

    printf $fp ("%${label_column_width}s%${float_column_width}.2f\n", $arg1, $arg2);
}

sub print_string($ $ $) {
    my $fp = shift;
    my $arg1 = shift;
    my $arg2 = shift;

    printf $fp ("%${label_column_width}s%${data_column_width}s\n", $arg1, $arg2);
}

sub print_offset_string($ $ $) {
    my $fp = shift;
    my $arg1 = shift;
    my $arg2 = shift;

    printf $fp ("%${label_column_width}s%${offset_column_width}s%s\n", $arg1, "", $arg2);
}

sub blank_line($) {
    my $fp = shift;
    print $fp "\n";
}

# function to initialize options that have 2 input methods from the cli
# option1, option2, default
sub double_option_init($ $ $) {
    my $option1 = shift(@_);
    my $option2 = shift(@_);
    my $default = shift(@_);
    my $ret_val = $default;

    $ret_val = $option1 if $option1;
    $ret_val = $option2 if $option2;

    return $ret_val;
}

sub max($ $) {
	my $a = shift;
	my $b = shift;
	return ($a > $b) ? $a : $b;
}

sub min($ $) {
	my $a = shift;
	my $b = shift;
	return ($a < $b) ? $a : $b;
}

####################################################################################################################

my %cli_options;
my %inputs;

# parse cli options
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("no_auto_abbrev");
GetOptions(\%cli_options,
	   'o=s', 'summary=s',     # Output filename for summary info.
	   'p=s', 'plotdir=s',     # Output directory for plot-files.
	   'c',   'chartscript',   # Create the chart script
	   's=i', 'start=i',       # Relative time from beginning of Jmeter run to the start of actual profiling.
	   'e=i', 'end=i');        # Relative time from beginning of Jmeter run to the end of actual profiling.

$inputs{'summary'}     = double_option_init($cli_options{'o'}, $cli_options{'summary'}, 0);
$inputs{'plotdir'}     = double_option_init($cli_options{'p'}, $cli_options{'plotdir'}, 0);
$inputs{'chartscript'} = double_option_init($cli_options{'c'}, $cli_options{'chartscript'}, 0);
$inputs{'prof_start'}  = double_option_init($cli_options{'s'}, $cli_options{'start'}, 0);
$inputs{'prof_end'}    = double_option_init($cli_options{'e'}, $cli_options{'end'}, 32000000); # Well over 1 full year.

print "JMeter Data Analyzer\n\n";

if (! defined($ARGV[0]) || ! -f "$ARGV[0]") {
    print STDERR "ERROR: Could not locate Jmeter results file.\n";
    exit 1;
} else {
    print "Jmeter Results File: $ARGV[0]\n";
}

if (!$inputs{'summary'}) {
    print STDERR "ERROR: Must specify summary output filename (--summary).\n";
    exit 1;
} elsif (!$inputs{'plotdir'}) {
    print STDERR "ERROR: Must specify directory (--plotdir) for output plot-files.\n";
    exit 1;
} else {
    print "Summary output file: $inputs{'summary'}\n";
    print "Plot-files output directory: $inputs{'plotdir'}\n";
}

if ($inputs{'prof_start'} > $inputs{'prof_end'}) {
    print STDERR "ERROR: Profiling start time must be less than profiling end time.\n";
    exit 1;
} else {
    print "Analyzing data between $inputs{'prof_start'} and $inputs{'prof_end'} seconds from the start of the run.\n";
}

####################################################################################################################

if (!open(INPUT,"<$ARGV[0]")) {
    print STDERR "ERROR: Failed to open Jmeter results file $ARGV[0].\n\n";
    exit 1;
}

my %fp;

if (! open($fp{'summary'}, ">$inputs{'summary'}")) {
    print STDERR "ERROR: Cannot open summary output file: $inputs{'summary'}\n\n";
    exit 1;
}

my @output_plot_files = ("request-histogram",
			 "abs-request-histogram",
			 "main-request-histogram",
			 "abs-main-request-histogram",
			 "sub-request-histogram",
			 "abs-sub-request-histogram",

			 "request-errors-histogram",
			 "abs-request-errors-histogram",
			 "main-request-errors-histogram",
			 "abs-main-request-errors-histogram",
			 "sub-request-errors-histogram",
			 "abs-sub-request-errors-histogram",

			 "transaction-histogram",

			 "request-latency-histogram",
			 "main-request-latency-histogram",
			 "sub-request-latency-histogram",

			 "request-duration-histogram",
			 "main-request-duration-histogram",
			 "sub-request-duration-histogram",
);

foreach my $filename (@output_plot_files) {
    if (! open($fp{$filename}, ">$inputs{'plotdir'}/$filename.plot")) {
	print STDERR "ERROR: Cannot open $filename output plot-file: $inputs{'plotdir'}/$filename.plot\n\n";
	exit 1;
    }
}

print_line($fp{'request-duration-histogram'},      "#LABEL:jmeter request length histogram");
print_line($fp{'main-request-duration-histogram'}, "#LABEL:jmeter main-request length histogram");
print_line($fp{'sub-request-duration-histogram'},  "#LABEL:jmeter sub-request length histogram");

print_line($fp{'request-latency-histogram'},      "#LABEL:jmeter request latency histogram");
print_line($fp{'main-request-latency-histogram'}, "#LABEL:jmeter main-request latency histogram");
print_line($fp{'sub-request-latency-histogram'},  "#LABEL:jmeter sub-request latency histogram");

if ($inputs{'chartscript'}) {
    # Use the parent directory of plotdir for the chart.sh file
    # and reset the input variable to the name of the script file
    $inputs{'chartscript'} = dirname($inputs{'plotdir'}) . "/chart.sh";
    if (! open($fp{'chartscript'}, ">$inputs{'chartscript'}")) {
	print STDERR "ERROR: Cannot open chart script output file: $inputs{'chartscript'}\n\n";
	exit 1;
    }
}

my $i;
my @fields;
my $line;
my $key;
my $value;

####################################################################################################################

#<httpSample t="3" lt="3" ts="1200539543569" s="true" lb="req_a" rc="200" rm="OK" tn="tg_a 1-3" dt="text" by="26"/>
#
#<sample t="1484" lt="0" ts="1200539481648" s="true" lb="tc_a" rc="200" rm="Number of samples in transaction : 2, number of failing samples : 0" tn="tg_b 2-1" dt="" by="52"/>
#
# *** All time is in milliseconds ***
#
# lb : name of 'HTTP Request' object
# ts : timestamp
# rc : response code
# tn : thread name '<thread group object name> <thread group object number>-<thread number>'
# dt : data type
# by : byte count
# s  : success (boolean true/flase)
# t  : elapsed time
# lt : latency

# From: http://wiki.apache.org/jakarta-jmeter/LogAnalysis
#
# JMeter JTL field contents:
#
# Attribute & Content
# by      Bytes
# de      Data encoding
# dt      Data type
# ec      Error count (0 or 1, unless multiple samples are aggregated)
# hn      Hostname where the sample was generated
# lb      Label
# lt      Latency = time to initial response (milliseconds) - not all samplers support this
# na      Number of active threads for all thread groups
# ng      Number of active threads in this group
# rc      Response Code (e.g. 200)
# rm      Response Message (e.g. OK)
# s       Success flag (true/false)
# sc      Sample count (1, unless multiple samples are aggregated)
# t       Elapsed time (milliseconds)
# tn      Thread Name
# ts      timeStamp (milliseconds since midnight Jan 1, 1970 UTC)

####################################################################################################################

my $test_length = 0; # Seconds
my $test_start_timestamp = 0; # Milliseconds
my $test_end_timestamp = 0; # Milliseconds
my $test_profiled_start_timestamp = 0; # Seconds
my $test_profiled_end_timestamp = 0; # Seconds

my %requests = (
    "main" => {
	"count"            => 0,
	"skipped_count"    => 0,
	"total_bytes"      => 0,
	"total_duration"   => 0,
	"total_latency"    => 0,
	"success"          => {
	    "true"         => 0,
	    "false"        => 0
	},
	"response_codes"   => {
	    "1xx"          => 0,
	    "2xx"          => 0,
	    "3xx"          => 0,
	    "4xx"          => 0,
	    "5xx"          => 0
	},
	"durations"        => [],
	"durations_sorted" => [],
	"min_duration"     => 1 << 30,
	"max_duration"     => 0,
	"min_latency"      => 1 << 30,
	"max_latency"      => 0,
	"histogram"        => {},
	"abs_histogram"    => {},
	"errors_histogram" => {},
	"abs_errors_histogram" => {}
    },
    "sub" => {
	"count"            => 0,
	"skipped_count"    => 0,
	"total_bytes"      => 0,
	"total_duration"   => 0,
	"total_latency"    => 0,
	"success"          => {
	    "true"         => 0,
	    "false"        => 0
	},
	"response_codes"   => {
	    "1xx"          => 0,
	    "2xx"          => 0,
	    "3xx"          => 0,
	    "4xx"          => 0,
	    "5xx"          => 0
	},
	"min_duration"     => 1 << 30,
	"max_duration"     => 0,
	"min_latency"      => 1 << 30,
	"max_latency"      => 0,
	"histogram"        => {},
	"abs_histogram"    => {},
	"errors_histogram" => {},
	"abs_errors_histogram" => {}
    },
);

my %transactions = (
    "count"             => 0,
    "skipped_count"     => 0,
    "total_duration_ms" => 0,
    "request_count"     => 0,
    "histogram"         => [],
    "success"           => {
	"true"          => 0,
	"false"         => 0
    }
);

sub requests_total($; $)
{
    my $key = shift;
    my $key2 = shift;
    my $total = 0;

    foreach my $type ("main", "sub") {
	if (exists($requests{$type}{$key})) {
	    if (defined($key2) && exists($requests{$type}{$key}{$key2})) {
		$total += $requests{$type}{$key}{$key2};
	    } else {
		$total += $requests{$type}{$key};
	    }
	}
    }

    return $total;
}

####################################################################################################################

# Make an initial pass through the input file to determine the sample with the earliest timestamp.

while(<INPUT>) {
    chomp($line=$_);
    if ($line =~ /<httpSample/ || $line =~ /<sample/) {
	@fields = split('"* ([a-z]+)="', $line);
	for ($i=1; $i<@fields; $i+=2) {
	    $key = $fields[$i];
	    $value = $fields[$i+1];
	    if ($key =~ /^ts$/) {
		if (!$test_start_timestamp || $value < $test_start_timestamp) {
		    $test_start_timestamp = $value;
		}
		if (!$test_end_timestamp || $value > $test_end_timestamp) {
		    $test_end_timestamp = $value;
		}
		last;
	    }
	}
    }
}

print("Starting timestamp is: $test_start_timestamp ms, " . floor($test_start_timestamp / 1000) . " sec.\n");
print("Ending timestamp is: $test_end_timestamp ms, " . floor($test_end_timestamp / 1000) . " sec.\n");

seek(INPUT, 0, 0);

while(<INPUT>) {
    chomp($line=$_);

    # Each HTTP request entry starts with "<httpSample". The main requests
    # start at the beginning of the line, and sub-requests are indented.
    if ($line =~ /^(\s*)<httpSample/) {

	my $type;
	if ($1 =~ /\s+/) {
		$type = "sub";
	} else {
		$type = "main";
	}

	@fields = split('"* ([a-z]+)="', $line);

	my $bytes = 0;
	my $duration = 0;
	my $latency = 0;
	my $success = 0;
	my $response_code = 0;
	my $rel_start = 0;
	my $abs_start = 0;
	my $skip_sample = 0;

	for ($i=1; $i<@fields; $i+=2) {
	    $key = $fields[$i];
	    $value = $fields[$i+1];

            # AGLITKE: If an element is sandwiched against the tag closing, value gets
            # an extra "/> appended.  Strip this off.  The proper fix is to update the
            # split regex above but I am too lazy right now.
            if ($value =~ /(.*)"\/>/) {
                $value = $1;
            }

	    if ($key eq "t") {
		# Time length to complete the request. For main requests, this
		# also includes the time to retrieve all the sub-requests.
		$duration = $value;

	    } elsif ($key eq "by") {
		# Number of bytes returned for the request. For main requests,
		# this also includes the size of all sub-requests.
		$bytes = $value;

	    } elsif ($key eq "lt") {
		# Latencyo of the request's response.
		$latency = $value;

	    } elsif ($key eq "rc") {
		# Return code. Genericize a response code so we can track 
		# the class of the codes received - e.g. 404 would become 4xx.
		$response_code = $value;
		$response_code =~ s/[0-9][0-9]$/xx/;

	    } elsif ($key eq "s") {
		# Was the request successful? 'true' or 'false'
		$success = $value;

	    } elsif ($key eq "ts") {
		# Timestamp of the start of the request.
		my $start_ms = $value;

		# capture the absolute time value of the request in seconds
		$abs_start = floor($start_ms / 1000);

		# Convert the timestamp to the start time relative to
		# the start of the entire Jmeter run.  Timestamps are
		# in milliseconds, so convert to seconds.
		my $rel_start_ms = $start_ms - $test_start_timestamp;
		$rel_start = floor($rel_start_ms / 1000);

		# Discard samples that start before the profiling
		# start time or after the profiling end time.
		if ($rel_start < $inputs{'prof_start'} || $rel_start > $inputs{'prof_end'}) {
		    $skip_sample = 1;
		    last;
		}
	    }
	}

	# Even if we're discarding this sample, determine if
	# this is the last sample in the entire Jmeter run.
	if ($rel_start > $test_length) {
	    $test_length = $rel_start;
	}

	if ($skip_sample) {
	    $requests{$type}{"skipped_count"}++;
	    next;
	} else {
	    if (!$test_profiled_start_timestamp || $abs_start < $test_profiled_start_timestamp) {
		$test_profiled_start_timestamp = $abs_start;
	    }
	    if (!$test_profiled_end_timestamp || $abs_start > $test_profiled_end_timestamp) {
		$test_profiled_end_timestamp = $abs_start;
	    }
	}

	$requests{$type}{"total_bytes"}    += $bytes;
	$requests{$type}{"response_codes"}{$response_code}++;
	$requests{$type}{"success"}{$success}++;

	# Update the request-duration-histogram plot-file.
	$requests{$type}{"total_duration"} += $duration;
	push @{$requests{$type}{"durations"}}, $duration;
	print_line($fp{"$type-request-duration-histogram"}, "$requests{$type}{'count'} $duration");
	print_line($fp{"request-duration-histogram"}, requests_total("count") . " $duration");
	$requests{$type}{"min_duration"} = min($requests{$type}{"min_duration"}, $duration);
	$requests{$type}{"max_duration"} = max($requests{$type}{"max_duration"}, $duration);

	# Update the request-latency-histogram plot-file.
	$requests{$type}{"total_latency"}  += $latency;
	print_line($fp{"$type-request-latency-histogram"}, "$requests{$type}{'count'} $latency");
	print_line($fp{"request-latency-histogram"}, requests_total("count") . " $latency");
	$requests{$type}{"min_latency"} = min($requests{$type}{"min_latency"}, $latency);
	$requests{$type}{"max_latency"} = max($requests{$type}{"max_latency"}, $latency);

	$requests{$type}{"count"}++;

	if (! exists $requests{$type}{"histogram"}->{$rel_start}) {
	    $requests{$type}{"histogram"}->{$rel_start} = 0;
	}
	$requests{$type}{"histogram"}->{$rel_start}++;

	if (! exists $requests{$type}{"abs_histogram"}->{$abs_start}) {
	    $requests{$type}{"abs_histogram"}->{$abs_start} = 0;
	}
	$requests{$type}{"abs_histogram"}->{$abs_start}++;

	if ($success eq "false") {
	    if (! exists $requests{$type}{"errors_histogram"}->{$rel_start}) {
    		$requests{$type}{"errors_histogram"}->{$rel_start} = 0;
	    }
    	    $requests{$type}{"errors_histogram"}->{$rel_start}++;

	    if (! exists $requests{$type}{"abs_errors_histogram"}->{$abs_start}) {
    		$requests{$type}{"abs_errors_histogram"}->{$abs_start} = 0;
	    }
    	    $requests{$type}{"abs_errors_histogram"}->{$abs_start}++;
	}

    } elsif ($line =~ /<sample/) {
	@fields = split('"* ([a-z]+)="', $line);

	my $skip_sample = 0;
	my $duration = 0;
	my $duration_ms = 0;
	my $success = 0;
	my $request_count = 0;
	my $rel_start = 0;

	for ($i=1; $i<@fields; $i+=2) {
	    $key = $fields[$i];
	    $value = $fields[$i+1];

	    if ($key eq "t") {
		# Elapsed time for the entire transaction.
		$duration_ms = $value;
		$duration = ceil($duration_ms / 1000);

	    } elsif ($key eq "s") {
		# Was the transaction successful? 'true' or 'false'
		# The transaction will fail if one or more requests in
		# the transaction fail.
		$success = $value;

	    } elsif ($key eq "rm") {
		# Total number of requests in this transaction. This only
		# includes main requests, not sub-requests.
		$value =~ m/Number of samples in transaction : ([0-9]+)/;
		$request_count = $1

	    } elsif ($key eq "ts") {
		# Timestamp of the start of the transaction. Convert the timestamp
		# to the start time relative to the start of the entire Jmeter run.
		# Timestamps are in milliseconds, so convert to seconds.
		my $start_ms = $value;
		my $rel_start_ms = $start_ms - $test_start_timestamp;
		$rel_start = floor($rel_start_ms / 1000);

		# Discard transactions that start before the profiling
		# start time or after the profiling end time.
		if ($rel_start < $inputs{'prof_start'} || $rel_start > $inputs{'prof_end'}) {
		    $skip_sample = 1;
		    last;
		}
	    }
	}

	if ($skip_sample) {
	    $transactions{"skipped_count"}++;
	    next;
	}

	$transactions{"count"}++;
	$transactions{"total_duration_ms"} += $duration_ms;
	$transactions{"success"}{$success}++;
	$transactions{"request_count"} += $request_count;

	# Iterate through however many seconds the transaction lasted and add that to the logical starting
	# second of the transaction in order to track the logical time the transaction was active
	for ($i=0; $i<$duration; $i++) {
	    if (! exists $transactions{"histogram"}->[$rel_start + $i]) {
		$transactions{"histogram"}->[$rel_start + $i] = 0;
	    }
	    $transactions{"histogram"}->[$rel_start + $i]++;
	}
    }
}

close INPUT;

####################################################################################################################

# Fill in any holes left in the transactions histogram.
for ($i=0; $i<$test_length; $i++) {
    if (! exists $transactions{"histogram"}->[$i]) {
	$transactions{"histogram"}->[$i] = 0;
    }
}

####################################################################################################################
{
    # Prevent divide by zero
    if ($requests{"sub"}{"count"} == 0) {
        $requests{"sub"}{"count"} = 1;
    }

    # Calculate the length of the profiling period.
    if ($test_length < $inputs{'prof_end'}) {
	$inputs{'prof_end'} = $test_length;
    }
    my $profiling_length = $inputs{'prof_end'} - $inputs{'prof_start'};

    # Output summary file
    print_line($fp{'summary'}, "JMeter Summary Output");

    blank_line($fp{'summary'});

    print_string($fp{'summary'}, "Test Length (sec):", $test_length);
    print_string($fp{'summary'}, "Profiling Period Start (sec):", $inputs{'prof_start'});
    print_string($fp{'summary'}, "Profiling Period End (sec):", $inputs{'prof_end'});
    print_string($fp{'summary'}, "Profiling Length (sec):", $profiling_length);

    blank_line($fp{'summary'});

    # Counts of requests.
    print_string($fp{'summary'}, "Total Analyzed Requests:",      requests_total("count"));
    print_string($fp{'summary'}, "Total Analyzed Main-Requests:", $requests{"main"}{"count"});
    print_string($fp{'summary'}, "Total Analyzed Sub-Requests:",  $requests{"sub"}{"count"});

    blank_line($fp{'summary'});

    print_string($fp{'summary'}, "Total Skipped Requests:",       requests_total("skipped_count"));
    print_string($fp{'summary'}, "Total Skipped Main-Requests:",  $requests{"main"}{"skipped_count"});
    print_string($fp{'summary'}, "Total Skipped Sub-Requests:",   $requests{"sub"}{"skipped_count"});

    # Request rate stats.
    print_float($fp{'summary'}, "Total Request Rate (req/sec):", requests_total("count") / $profiling_length);
    print_float($fp{'summary'}, "Main-Request Rate (req/sec):",  $requests{"main"}{"count"} / $profiling_length);
    print_float($fp{'summary'}, "Sub-Request Rate (req/sec):",   $requests{"sub"}{"count"} / $profiling_length);

    blank_line($fp{'summary'});

    # Request latency stats.
    print_float($fp{'summary'},  "Average Request Latency (ms):", requests_total("total_latency") / requests_total("count"));
    print_string($fp{'summary'}, "Minimum Request Latency (ms):", min($requests{"main"}{"min_latency"}, $requests{"sub"}{"min_latency"}));
    print_string($fp{'summary'}, "Maximum Request Latency (ms):", max($requests{"main"}{"max_latency"}, $requests{"sub"}{"max_latency"}));

    blank_line($fp{'summary'});

    print_float($fp{'summary'},  "Average Main-Request Latency (ms):", $requests{"main"}{"total_latency"} / $requests{"main"}{"count"});
    print_string($fp{'summary'}, "Minimum Main-Request Latency (ms):", $requests{"main"}{"min_latency"});
    print_string($fp{'summary'}, "Maximum Main-Request Latency (ms):", $requests{"main"}{"max_latency"});

    blank_line($fp{'summary'});

    print_float($fp{'summary'},  "Average Sub-Request Latency (ms):", $requests{"sub"}{"total_latency"} / $requests{"sub"}{"count"});
    print_string($fp{'summary'}, "Minimum Sub-Request Latency (ms):", $requests{"sub"}{"min_latency"});
    print_string($fp{'summary'}, "Maximum Sub-Request Latency (ms):", $requests{"sub"}{"max_latency"});

    blank_line($fp{'summary'});

    # Request duration stats.
    print_float($fp{'summary'},  "Average Request Duration (ms):", requests_total("total_duration") / requests_total("count"));
    print_string($fp{'summary'}, "Minimum Request Duration (ms):", min($requests{"main"}{"min_duration"}, $requests{"sub"}{"min_duration"}));
    print_string($fp{'summary'}, "Maximum Request Duration (ms):", max($requests{"main"}{"max_duration"}, $requests{"sub"}{"max_duration"}));

    blank_line($fp{'summary'});

    print_float($fp{'summary'},  "Average Main-Request Duration (ms):", $requests{"main"}{"total_duration"} / $requests{"main"}{"count"});
    print_string($fp{'summary'}, "Minimum Main-Request Duration (ms):", $requests{"main"}{"min_duration"});
    print_string($fp{'summary'}, "Maximum Main-Request Duration (ms):", $requests{"main"}{"max_duration"});

    blank_line($fp{'summary'});

    print_float($fp{'summary'},  "Average Sub-Request Duration (ms):", $requests{"sub"}{"total_duration"} / $requests{"sub"}{"count"});
    print_string($fp{'summary'}, "Minimum Sub-Request Duration (ms):", $requests{"sub"}{"min_duration"});
    print_string($fp{'summary'}, "Maximum Sub-Request Duration (ms):", $requests{"sub"}{"max_duration"});

    blank_line($fp{'summary'});

    my $test_result;

    # Sort the main-request durations so we can easily
    # pick out the 95th and 99th percentile durations.
    @{$requests{"main"}{"durations_sorted"}} = sort({$a <=> $b} @{$requests{"main"}{"durations"}});

    # Check if 95th percentile of main-request duration is greater than 2000 milliseconds.
    # This is taken from the TIME_GOOD parameter of the banking test in SPECWEB2005.
    print_string($fp{'summary'}, "95th Percentile Main-Request Duration (ms):",
		 $requests{"main"}{"durations_sorted"}->[ceil($requests{"main"}{"count"} * 0.95)]);
    if ($requests{"main"}{"durations_sorted"}->[ceil($requests{"main"}{"count"} * 0.95)] > 2000) {
	$test_result = "FAILED";
    } else {
	$test_result = "PASSED";
    }
    print_string($fp{'summary'}, "95th Percentile Main-Request Duration Test:", $test_result);

    # Check if the 99th percentile request duration is greater than 4000 milliseconds.
    # This is taken from the TIME_TOLERABLE parameter of the banking test in SPECWEB2005.
    print_string($fp{'summary'}, "99th Percentile Main-Request Duration (ms):",
		 $requests{"main"}{"durations_sorted"}->[ceil($requests{"main"}{"count"} * 0.99)]);
    if ($requests{"main"}{"durations_sorted"}->[ceil($requests{"main"}{"count"} * 0.99)] > 4000) {
	$test_result = "FAILED";
    } else {
	$test_result = "PASSED";
    }
    print_string($fp{'summary'}, "99th Percentile Main-Request Duration Test:", $test_result);

    blank_line($fp{'summary'});

    # Data transfer stats.
    print_float($fp{'summary'}, "Request Total KBytes:",        requests_total("total_bytes")  / 1024);
    print_float($fp{'summary'}, "Request Average KBytes:",      requests_total("total_bytes")  / 1024 / requests_total("count"));
    print_float($fp{'summary'}, "Main-Request Total KBytes:",   $requests{"main"}{"total_bytes"} / 1024);
    print_float($fp{'summary'}, "Main-Request Average KBytes:", $requests{"main"}{"total_bytes"} / 1024 / $requests{"main"}{"count"});
    print_float($fp{'summary'}, "Sub-Request Total KBytes:",    $requests{"sub"}{"total_bytes"}  / 1024);
    print_float($fp{'summary'}, "Sub-Request Average KBytes:", $requests{"sub"}{"total_bytes"}  / 1024 / $requests{"sub"}{"count"});

    blank_line($fp{'summary'});

    print_offset_string($fp{'summary'}, "Total Request Status:",
			sprintf("Success=[%s]/[%.2f%%] Failed=[%s]/[%.2f%%]",
				requests_total("success", "true"),
				requests_total("success", "true") / requests_total("count") * 100,
				requests_total("success", "false"),
				requests_total("success", "false") / requests_total("count") * 100));

    print_offset_string($fp{'summary'}, "Total Request HTTP Response Codes:",
			sprintf("1xx=[%s]/[%.2f%%] 2xx=[%s]/[%.2f%%] 3xx=[%s]/[%.2f%%] 4xx=[%s]/[%.2f%%] 5xx=[%s]/[%.2f%%]",
				requests_total("response_codes", "1xx"),
				requests_total("response_codes", "1xx") / requests_total("count") * 100,
				requests_total("response_codes", "2xx"),
				requests_total("response_codes", "2xx") / requests_total("count") * 100,
				requests_total("response_codes", "3xx"),
				requests_total("response_codes", "3xx") / requests_total("count") * 100,
				requests_total("response_codes", "4xx"),
				requests_total("response_codes", "4xx") / requests_total("count") * 100,
				requests_total("response_codes", "5xx"),
				requests_total("response_codes", "5xx") / requests_total("count") * 100));

    blank_line($fp{'summary'});

    print_offset_string($fp{'summary'}, "Main-Request Status:",
			sprintf("Success=[%s]/[%.2f%%] Failed=[%s]/[%.2f%%]",
				$requests{"main"}{"success"}{"true"},
				$requests{"main"}{"success"}{"true"} / $requests{"main"}{"count"} * 100,
				$requests{"main"}{"success"}{"false"},
				$requests{"main"}{"success"}{"false"} / $requests{"main"}{"count"} * 100));

    print_offset_string($fp{'summary'}, "Main-Request HTTP Response Codes:",
			sprintf("1xx=[%s]/[%.2f%%] 2xx=[%s]/[%.2f%%] 3xx=[%s]/[%.2f%%] 4xx=[%s]/[%.2f%%] 5xx=[%s]/[%.2f%%]",
				$requests{"main"}{"response_codes"}{"1xx"},
				$requests{"main"}{"response_codes"}{"1xx"} / $requests{"main"}{"count"} * 100,
				$requests{"main"}{"response_codes"}{"2xx"},
				$requests{"main"}{"response_codes"}{"2xx"} / $requests{"main"}{"count"} * 100,
				$requests{"main"}{"response_codes"}{"3xx"},
				$requests{"main"}{"response_codes"}{"3xx"} / $requests{"main"}{"count"} * 100,
				$requests{"main"}{"response_codes"}{"4xx"},
				$requests{"main"}{"response_codes"}{"4xx"} / $requests{"main"}{"count"} * 100,
				$requests{"main"}{"response_codes"}{"5xx"},
				$requests{"main"}{"response_codes"}{"5xx"} / $requests{"main"}{"count"} * 100));

    print_offset_string($fp{'summary'}, "Sub-Request Status:",
			sprintf("Success=[%s]/[%.2f%%] Failed=[%s]/[%.2f%%]",
				$requests{"sub"}{"success"}{"true"},
				$requests{"sub"}{"success"}{"true"} / $requests{"sub"}{"count"} * 100,
				$requests{"sub"}{"success"}{"false"},
				$requests{"sub"}{"success"}{"false"} / $requests{"sub"}{"count"} * 100));

    print_offset_string($fp{'summary'}, "Sub-Request HTTP Response Codes:",
			sprintf("1xx=[%s]/[%.2f%%] 2xx=[%s]/[%.2f%%] 3xx=[%s]/[%.2f%%] 4xx=[%s]/[%.2f%%] 5xx=[%s]/[%.2f%%]",
				$requests{"sub"}{"response_codes"}{"1xx"},
				$requests{"sub"}{"response_codes"}{"1xx"} / $requests{"sub"}{"count"} * 100,
				$requests{"sub"}{"response_codes"}{"2xx"},
				$requests{"sub"}{"response_codes"}{"2xx"} / $requests{"sub"}{"count"} * 100,
				$requests{"sub"}{"response_codes"}{"3xx"},
				$requests{"sub"}{"response_codes"}{"3xx"} / $requests{"sub"}{"count"} * 100,
				$requests{"sub"}{"response_codes"}{"4xx"},
				$requests{"sub"}{"response_codes"}{"4xx"} / $requests{"sub"}{"count"} * 100,
				$requests{"sub"}{"response_codes"}{"5xx"},
				$requests{"sub"}{"response_codes"}{"5xx"} / $requests{"sub"}{"count"} * 100));

    blank_line($fp{'summary'});

    print_string($fp{'summary'}, "Total Analyzed Transactions:", $transactions{"count"});
    print_string($fp{'summary'}, "Total Skipped Transactions:", $transactions{"skipped_count"});

    if ($transactions{"count"} > 0) {
	print_float($fp{'summary'}, "Average Main-Requests/Transaction:", $transactions{"request_count"} / $transactions{"count"} );
	print_float($fp{'summary'}, "Average Transaction Duration (sec):", ($transactions{"total_duration_ms"} / 1000) / $transactions{"count"});

	print_offset_string($fp{'summary'}, "Transction Status:",
			    sprintf("Success=[%s]/[%.2f%%] Failed=[%s]/[%.2f%%]",
				    $transactions{"success"}{"true"},
				    $transactions{"success"}{"true"} / $transactions{"count"} * 100,
				    $transactions{"success"}{"false"},
				    $transactions{"success"}{"false"} / $transactions{"count"} * 100));
    }

    blank_line($fp{'summary'});

    print_string($fp{'summary'}, "Relative Timestamps:", "");
    print_string($fp{'summary'}, "Test Start:", $inputs{'prof_start'});
    print_string($fp{'summary'}, "Test Stop:", $inputs{'prof_end'});

    blank_line($fp{'summary'});

    print_string($fp{'summary'}, "Absolute Timestamps:", "");
    print_string($fp{'summary'}, "Test Start:", $test_profiled_start_timestamp);
    print_string($fp{'summary'}, "Test Stop:", $test_profiled_end_timestamp);
}


####################################################################################################################

{
    # Output request histograms with relative timestamps
    print_line($fp{'request-histogram'}, "#LABEL:jmeter request histogram");
    foreach $key (sort {$a <=> $b} (keys(%{{%{$requests{"main"}{"histogram"}}, %{$requests{"sub"}{"histogram"}}}}))) {
	if (defined($requests{"main"}{"histogram"}->{$key}) && defined($requests{"sub"}{"histogram"}->{$key})) {
	    print_line($fp{'request-histogram'}, "$key " . ($requests{'main'}{'histogram'}->{$key} + $requests{'sub'}{'histogram'}->{$key}));
	} elsif (defined($requests{"main"}{"histogram"}->{$key})) {
	    print_line($fp{'request-histogram'}, "$key $requests{'main'}{'histogram'}->{$key}");
	} elsif (defined($requests{"sub"}{"histogram"}->{$key})) {
	    print_line($fp{'request-histogram'}, "$key $requests{'sub'}{'histogram'}->{$key}");
	}
    }

    print_line($fp{'main-request-histogram'}, "#LABEL:jmeter main-request histogram");
    foreach $key (sort {$a <=> $b} (keys %{$requests{"main"}{"histogram"}})) {
	print_line($fp{'main-request-histogram'}, "$key $requests{'main'}{'histogram'}->{$key}");
    }

    print_line($fp{'sub-request-histogram'}, "#LABEL:jmeter sub-request histogram");
    foreach $key (sort {$a <=> $b} (keys %{$requests{"sub"}{"histogram"}})) {
	print_line($fp{'sub-request-histogram'}, "$key $requests{'sub'}{'histogram'}->{$key}");
    }
}

####################################################################################################################

{
    # Output request histograms with absolute timestamps
    print_line($fp{'abs-request-histogram'}, "#LABEL:jmeter request absolute histogram");
    foreach $key (sort {$a <=> $b} (keys(%{{%{$requests{"main"}{"abs_histogram"}}, %{$requests{"sub"}{"abs_histogram"}}}}))) {
	if (defined($requests{"main"}{"abs_histogram"}->{$key}) && defined($requests{"sub"}{"abs_histogram"}->{$key})) {
	    print_line($fp{'abs-request-histogram'}, "$key " . ($requests{'main'}{'abs_histogram'}->{$key} + $requests{'sub'}{'abs_histogram'}->{$key}));
	} elsif (defined($requests{"main"}{"abs_histogram"}->{$key})) {
	    print_line($fp{'abs-request-histogram'}, "$key $requests{'main'}{'abs_histogram'}->{$key}");
	} elsif (defined($requests{"sub"}{"abs_histogram"}->{$key})) {
	    print_line($fp{'abs-request-histogram'}, "$key $requests{'sub'}{'abs_histogram'}->{$key}");
	}
    }

    print_line($fp{'abs-main-request-histogram'}, "#LABEL:jmeter main-request absolute histogram");
    foreach $key (sort {$a <=> $b} (keys %{$requests{"main"}{"abs_histogram"}})) {
	print_line($fp{'abs-main-request-histogram'}, "$key $requests{'main'}{'abs_histogram'}->{$key}");
    }

    print_line($fp{'abs-sub-request-histogram'}, "#LABEL:jmeter sub-request absolute histogram");
    foreach $key (sort {$a <=> $b} (keys %{$requests{"sub"}{"abs_histogram"}})) {
	print_line($fp{'abs-sub-request-histogram'}, "$key $requests{'sub'}{'abs_histogram'}->{$key}");
    }
}

####################################################################################################################

{
    # Output request errors histograms with relative timestamps
    print_line($fp{'request-errors-histogram'}, "#LABEL:jmeter request errors histogram");
    foreach $key (sort {$a <=> $b} (keys(%{{%{$requests{"main"}{"errors_histogram"}}, %{$requests{"sub"}{"errors_histogram"}}}}))) {
	if (defined($requests{"main"}{"errors_histogram"}->{$key}) && defined($requests{"sub"}{"errors_histogram"}->{$key})) {
	    print_line($fp{'request-errors-histogram'}, "$key " . ($requests{'main'}{'errors_histogram'}->{$key} + $requests{'sub'}{'errors_histogram'}->{$key}));
	} elsif (defined($requests{"main"}{"errors_histogram"}->{$key})) {
	    print_line($fp{'request-errors-histogram'}, "$key $requests{'main'}{'errors_histogram'}->{$key}");
	} elsif (defined($requests{"sub"}{"errors_histogram"}->{$key})) {
	    print_line($fp{'request-errors-histogram'}, "$key $requests{'sub'}{'errors_histogram'}->{$key}");
	}
    }

    print_line($fp{'main-request-errors-histogram'}, "#LABEL:jmeter main-request errors histogram");
    foreach $key (sort {$a <=> $b} (keys %{$requests{"main"}{"errors_histogram"}})) {
	print_line($fp{'main-request-errors-histogram'}, "$key $requests{'main'}{'errors_histogram'}->{$key}");
    }

    print_line($fp{'sub-request-errors-histogram'}, "#LABEL:jmeter sub-request errors histogram");
    foreach $key (sort {$a <=> $b} (keys %{$requests{"sub"}{"errors_histogram"}})) {
	print_line($fp{'sub-request-errors-histogram'}, "$key $requests{'sub'}{'errors_histogram'}->{$key}");
    }
}

####################################################################################################################

{
    # Output request errors histograms with absolute timestamps
    print_line($fp{'abs-request-errors-histogram'}, "#LABEL:jmeter request errors absolute histogram");
    foreach $key (sort {$a <=> $b} (keys(%{{%{$requests{"main"}{"abs_errors_histogram"}}, %{$requests{"sub"}{"abs_errors_histogram"}}}}))) {
	if (defined($requests{"main"}{"abs_errors_histogram"}->{$key}) && defined($requests{"sub"}{"abs_errors_histogram"}->{$key})) {
	    print_line($fp{'abs-request-errors-histogram'}, "$key " . ($requests{'main'}{'abs_errors_histogram'}->{$key} + $requests{'sub'}{'abs_errors_histogram'}->{$key}));
	} elsif (defined($requests{"main"}{"abs_errors_histogram"}->{$key})) {
	    print_line($fp{'abs-request-errors-histogram'}, "$key $requests{'main'}{'abs_errors_histogram'}->{$key}");
	} elsif (defined($requests{"sub"}{"abs_errors_histogram"}->{$key})) {
	    print_line($fp{'abs-request-errors-histogram'}, "$key $requests{'sub'}{'abs_errors_histogram'}->{$key}");
	}
    }

    print_line($fp{'abs-main-request-errors-histogram'}, "#LABEL:jmeter main-request errors absolute histogram");
    foreach $key (sort {$a <=> $b} (keys %{$requests{"main"}{"abs_errors_histogram"}})) {
	print_line($fp{'abs-main-request-errors-histogram'}, "$key $requests{'main'}{'abs_errors_histogram'}->{$key}");
    }

    print_line($fp{'abs-sub-request-errors-histogram'}, "#LABEL:jmeter sub-request errors absolute histogram");
    foreach $key (sort {$a <=> $b} (keys %{$requests{"sub"}{"abs_errors_histogram"}})) {
	print_line($fp{'abs-sub-request-errors-histogram'}, "$key $requests{'sub'}{'abs_errors_histogram'}->{$key}");
    }
}

####################################################################################################################

{
    # Output transaction histogram
    print_line($fp{'transaction-histogram'}, "#LABEL:jmeter transaction histogram");

    for ($i=0; $i<@{$transactions{"histogram"}}; $i++) {
	print_line($fp{'transaction-histogram'}, "$i $transactions{'histogram'}->[$i]");
    }
}

####################################################################################################################

{
    my $base_plotdir = basename($inputs{'plotdir'});

    if ($inputs{'chartscript'}) {
	print_line($fp{'chartscript'}, '#!/bin/bash');
	blank_line($fp{'chartscript'});
	print_line($fp{'chartscript'}, 'DIR=`dirname $0`');
	blank_line($fp{'chartscript'});
	print_line($fp{'chartscript'}, 'if [ $# != 2 ]; then');
	print_line($fp{'chartscript'}, '  echo "You must specify the path to the chart.pl script' .
					' and the Chart Directory libraries."');
	print_line($fp{'chartscript'}, '  exit 1');
	print_line($fp{'chartscript'}, 'fi');
	blank_line($fp{'chartscript'});
	print_line($fp{'chartscript'}, 'SCRIPT=$1');
	print_line($fp{'chartscript'}, 'LIBRARIES=$2');
	print_line($fp{'chartscript'}, 'export PERL5LIB=$LIBRARIES');
	blank_line($fp{'chartscript'});
	print_line($fp{'chartscript'}, 'pushd $DIR > /dev/null');
	blank_line($fp{'chartscript'});
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "01 Histogram of Requests"' .
					' --table html' .
					' -x "Time (Secs.)" -y "Requests/sec"' .
					" --x-range=$inputs{'prof_start'}:$inputs{'prof_end'}" .
					" $base_plotdir/request-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "02 Histogram of Main-Requests"' .
					' --table html' .
					' -x "Time (Secs.)" -y "Requests/sec"' .
					" --x-range=$inputs{'prof_start'}:$inputs{'prof_end'}" .
					" $base_plotdir/main-request-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "03 Histogram of Sub-Requests"' .
					' --table html' .
					' -x "Time (Secs.)" -y "Requests/sec"' .
					" --x-range=$inputs{'prof_start'}:$inputs{'prof_end'}" .
					" $base_plotdir/sub-request-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "04 Combined Histogram of Requests"' .
					' --table html' .
					' -s stackedlines' .
					' -x "Time (Secs.)" -y "Requests/sec"' .
					" --x-range=$inputs{'prof_start'}:$inputs{'prof_end'}" .
					" $base_plotdir/main-request-histogram.plot" .
					" $base_plotdir/sub-request-histogram.plot");

	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "05 Histogram of Request Errors"' .
					' --table html' .
					' -x "Time (Secs.)" -y "Errors/sec"' .
					" --x-range=$inputs{'prof_start'}:$inputs{'prof_end'}" .
					" $base_plotdir/request-errors-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "06 Histogram of Main-Request Errors"' .
					' --table html' .
					' -x "Time (Secs.)" -y "Errors/sec"' .
					" --x-range=$inputs{'prof_start'}:$inputs{'prof_end'}" .
					" $base_plotdir/main-request-errors-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "07 Histogram of Sub-Request Errors"' .
					' --table html' .
					' -x "Time (Secs.)" -y "Errors/sec"' .
					" --x-range=$inputs{'prof_start'}:$inputs{'prof_end'}" .
					" $base_plotdir/sub-request-errors-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "08 Combined Histogram of Request Errors"' .
					' --table html' .
					' -s stackedlines' .
					' -x "Time (Secs.)" -y "Errors/sec"' .
					" --x-range=$inputs{'prof_start'}:$inputs{'prof_end'}" .
					" $base_plotdir/main-request-errors-histogram.plot" .
					" $base_plotdir/sub-request-errors-histogram.plot");

	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "09 Histogram of Completed Transactions"' .
					' --table html' .
					' -x "Time (Secs.)" -y "Transactions Running"' .
					" --x-range=$inputs{'prof_start'}:$inputs{'prof_end'}" .
					" $base_plotdir/transaction-histogram.plot");

	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "10 Individual Request Latency"' .
					' --table html' .
					' -x "Samples" -y "Latency (ms)"' .
					" $base_plotdir/request-latency-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "11 Individual Main-Request Latency"' .
					' --table html' .
					' -x "Samples" -y "Latency (ms)"' .
					" $base_plotdir/main-request-latency-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "12 Individual Sub-Request Latency"' .
					' --table html' .
					' -x "Samples" -y "Latency (ms)"' .
					" $base_plotdir/sub-request-latency-histogram.plot");

	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "13 Individual Request Duration"' .
					' --table html' .
					' -x "Samples" -y "Duration (ms)"' .
					" $base_plotdir/request-duration-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "14 Individual Main-Request Duration"' .
					' --table html' .
					' -x "Samples" -y "Duration (ms)"' .
					" $base_plotdir/main-request-duration-histogram.plot");
	print_line($fp{'chartscript'}, '$SCRIPT -s lines --title "15 Individual Sub-Request Duration"' .
					' --table html' .
					' -x "Samples" -y "Duration (ms)"' .
					" $base_plotdir/sub-request-duration-histogram.plot");

	print_line($fp{'chartscript'}, 'echo -e "<html>\n<head>\n<title>JMeter Charts</title>\n</head>\n<body>\n" > chart.html');

	print_line($fp{'chartscript'}, 'for i in `ls -1 *.png`; do');
	print_line($fp{'chartscript'}, '  echo -e "<table>\n<tr valign=\'top\'>\n" >> chart.html');
	print_line($fp{'chartscript'}, '  echo -e "<td><img src=\'$i\'></td>\n" >> chart.html');
	print_line($fp{'chartscript'}, '  html_file=`echo $i | sed -e "s/png/html/"`');
	print_line($fp{'chartscript'}, '  if [ -e $html_file ]; then');
	print_line($fp{'chartscript'}, '    echo -e "<td>\n" >> chart.html');
	print_line($fp{'chartscript'}, '    cat $html_file >> chart.html');
	print_line($fp{'chartscript'}, '    echo -e "</td>\n" >> chart.html');
	print_line($fp{'chartscript'}, '  fi');
	print_line($fp{'chartscript'}, '  echo -e "</tr>\n</table>\n" >> chart.html');
	print_line($fp{'chartscript'}, 'done');

	print_line($fp{'chartscript'}, 'echo -e "</body>\n</html>\n" >> chart.html');
    }
}

####################################################################################################################

foreach $key (keys(%fp)) {
	close $fp{$key};
}

if ($inputs{'chartscript'}) {
	chmod(0777, "$inputs{'chartscript'}");
}

