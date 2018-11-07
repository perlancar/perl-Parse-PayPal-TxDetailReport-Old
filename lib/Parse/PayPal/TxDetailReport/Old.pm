package Parse::PayPal::TxDetailReport::Old;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(parse_paypal_old_txdetail_report);

use DateTime; # XXX find a more lightweight alternative

our %SPEC;

sub _parse_date {
    my ($fmt, $date) = @_;
    if ($fmt eq 'MM/DD/YYYY') {
        $date =~ m!^(\d\d?)/(\d\d?)/(\d\d\d\d)$!
            or die "Invalid date format in '$date', must be MM/DD/YYYY";
        return DateTime->new(year => $3, month => $1, day => $2)->epoch;
    } elsif ($fmt eq 'DD/MM/YYYY') {
        $date =~ m!^(\d\d?)/(\d\d?)/(\d\d\d\d)$!
            or die "Invalid date format in '$date', must be DD/MM/YYYY";
        return DateTime->new(year => $3, month => $2, day => $1)->epoch;
    } else {
        die "Unknown date format, please use MM/DD/YYYY or DD/MM/YYYY";
    }
}

$SPEC{parse_paypal_old_txdetail_report} = {
    v => 1.1,
    summary => 'Parse PayPal transaction detail report (older version, 2015 and earlier) into data structure',
    description => <<'_',

The result will be a hashref. The main key is `transactions` which will be an
arrayref of hashrefs.

Dates will be converted into Unix timestamps.

_
    args => {
        file => {
            schema => 'filename*',
            description => <<'_',

File can all be in tab-separated or comma-separated (CSV) format.

_
            pos => 0,
        },
        string => {
            schema => ['str*'],
            description => <<'_',

Instead of `file`, you can alternatively provide the file content in `string`.

_
        },
        format => {
            schema => ['str*', in=>[qw/tsv csv/]],
            description => <<'_',

If unspecified, will be deduced from the first filename's extension (/csv/ for
CSV, or /txt|tsv/ for tab-separated).

_
        },
        date_format => {
            schema => ['str*', in=>['MM/DD/YYYY', 'DD/MM/YYYY']],
            default => 'MM/DD/YYYY',
        },
    },
    args_rels => {
        req_one => ['file', 'string'],
    },
};
sub parse_paypal_old_txdetail_report {
    my %args = @_;

    my $format = $args{format};
    my $date_format = $args{date_format} // 'MM/DD/YYYY';

    my $fh;
    my $file;
    if (defined(my $str = $args{string})) {
        require IO::Scalar;
        require String::BOM;

        if (!$format) {
            $format = $str =~ /\t/ ? 'tsv' : 'csv';
        }
        $str = String::BOM::strip_bom_from_string($str);
        $fh = IO::Scalar->new(\$str);
        $file = "string";
    } elsif (defined(my $file0 = $args{file})) {
        require File::BOM;

        if (!$format) {
            $format = $file0 =~ /\.(csv)\z/i ? 'csv' : 'tsv';
        }
        open $fh, "<:encoding(utf8):via(File::BOM)", $file0
            or return [500, "Can't open file '$file': $!"];
        $file = $file0;
    } else {
        return [400, "Please specify file (or string)"];
    }

    my $res = [200, "OK", {
        format => "txdetail_old",
        transactions => [],
    }];

    my $code_parse_row = sub {
        my ($rownum, $row) = @_;

        if ($rownum == 1) {
            unless (@$row > 10 && $row->[0] eq 'Date') {
                $res = [400, "Doesn't look like old transaction detail ".
                            "format, I expect first row to be column names ".
                            "and first column header to be Date"];
                goto RETURN_RES;
            }
            $res->[2]{_transaction_columns} = $row;
            return;
        }
        my $tx = {};
        my $txcols = $res->[2]{_transaction_columns};
        for (0..$#{$row}) {
            my $field = $txcols->[$_];
            if ($field =~ /Date$/ && $row->[$_]) {
                $tx->{$field} = _parse_date($date_format, $row->[$_]);
            } else {
                $tx->{$field} = $row->[$_];
            }
        }
        push @{ $res->[2]{transactions} }, $tx;
    };

    my $csv;
    if ($format eq 'csv') {
        require Text::CSV;
        $csv = Text::CSV->new({binary=>1})
            or return [500, "Cannot use CSV: ".Text::CSV->error_diag];
    }

    if ($format eq 'csv') {
        my $rownum = 0;
        while (my $row = $csv->getline($fh)) {
            $rownum++;
            $code_parse_row->($rownum, $row);
        }
        say $csv->error_diag;
    } else {
        my $rownum = 0;
        while (my $line = <$fh>) {
            $rownum++;
            chomp($line);
            $code_parse_row->($rownum, [split /\t/, $line]);
        }
    }
    delete $res->[2]{_transaction_columns};

  RETURN_RES:
    $res;
}

1;
# ABSTRACT:

=head1 SYNOPSIS

 use Parse::PayPal::TxDetailReport qw(parse_paypal_old_txdetail_report);

 my $res = parse_paypal_txdetail_report(
     file => "report.csv",
     #date_format => 'DD/MM/YYYY', # optional, default is MM/DD/YYYY
 );

Sample result when there is a parse error:

 [400, "Doesn't look like old transaction detail format, I expect first row to be column names and first column header to be Date"]

Sample result when parse is successful:

 [200, "OK", {
     format => "txdetail_old",
     transactions           => [
         {
             "3PL Reference ID"                   => "",
             "Auction Buyer ID"                   => "",
             "Auction Closing Date"               => "",
             "Auction Site"                       => "",
             "Authorization Review Status"        => 1,
             ...
             "Transaction Completion Date"        => 1467273397,
             ...
         },
         ...
     ],
 }]


=head1 DESCRIPTION

PayPal provides various kinds of reports which you can retrieve from their
website under Reports menu. This module provides routine to parse PayPal old
transaction detail report (2015 and earlier). Both the tab-separated format and
comma-separated (CSV) format are supported.


=head1 SEE ALSO

L<https://www.paypal.com>

L<Parse::PayPal::TxDetailReport>

L<Parse::PayPal::TxFinderReport>
