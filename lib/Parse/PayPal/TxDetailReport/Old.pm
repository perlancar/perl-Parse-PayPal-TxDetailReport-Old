package Parse::PayPal::TxDetailReport::Old;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(parse_paypal_old_txdetail_report);

use DateTime::Format::Flexible; # XXX find a more lightweight alternative

our %SPEC;

sub _parse_date {
    DateTime::Format::Flexible->parse_datetime(shift)->epoch;
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

    my $fh;
    my $file;
    if (defined(my $str0 = $args{string})) {
        require IO::Scalar;
        require String::BOM;

        if (!$format) {
            $format = $strings->[0] =~ /\t/ ? 'tsv' : 'csv';
        }
        my $str = String::BOM::strip_bom_from_string($str0);
        $fh = IO::Scalar->new(\$str);
        $file = "string";
    } elsif (defined(my $file0 = $args{file})) {
        require File::BOM;

        if (!$format) {
            $format = $files->[0] =~ /\.(csv)\z/i ? 'csv' : 'tsv';
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
        my ($row, $rownum) = @_;

        if ($rownum == 1) {
            unless (@$row > 10 && $row->[0] eq 'Date') {
                $res = [400, "Doesn't look like old transaction detail ".
                            "format, I expect first row to be column names ".
                            "and first column header to be Date"];
                goto RETURN RES;
            }
            $res->[2]{_transaction_columns} = $row;
            return;
        }
        my $tx = {};
        my $txcols = $res->[2]{_transaction_columns};
        for (1..$#{$row}) {
            my $field = $txcols->[$_-1];
            if ($field =~ /Date$/ && $row->[$_]) {
                $tx->{$field} = _parse_date($date_format, $row->[$_]);
            } else {
                $tx->{$header} = $row->[$_];
            }
        }
        push @{ $res->[2]{transactions} }, $tx;
    };

    my $csv;
    if ($format eq 'csv') {
        require Text::CSV;
        $csv = Text::CSV->new
            or return [500, "Cannot use CSV: ".Text::CSV->error_diag];
    }

    if ($format eq 'csv') {
        while (my $row = $csv->getline($handles[$i])) {
            $code_parse_row->($row);
        }
    } else {
        my $fh = $handles[$i];
        while (my $line = <$fh>) {
            chomp($line);
            $code_parse_row->([split /\t/, $line]);
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
transaction detail report (2015 and earlier). Multiple files are supported. Both
the tab-separated format and comma-separated (CSV) format are supported.


=head1 SEE ALSO

L<https://www.paypal.com>

L<Parse::PayPal::TxDetailReport>

L<Parse::PayPal::TxFinderReport>
