#
# Copyright 2017 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package cloud::aws::custom::awscli;

use strict;
use warnings;
use DateTime;
use JSON::XS;

sub new {
    my ($class, %options) = @_;
    my $self  = {};
    bless $self, $class;

    if (!defined($options{output})) {
        print "Class Custom: Need to specify 'output' argument.\n";
        exit 3;
    }
    if (!defined($options{options})) {
        $options{output}->add_option_msg(short_msg => "Class Custom: Need to specify 'options' argument.");
        $options{output}->option_exit();
    }
    
    if (!defined($options{noptions})) {
        $options{options}->add_options(arguments => 
                    {                      
                    "aws-secret-key:s"  => { name => 'aws_secret_key' },
                    "aws-access-key:s"  => { name => 'aws_access_key' },
                    "timeout:s"           => { name => 'timeout', default => 50 },
                    "sudo"                => { name => 'sudo' },
                    "command:s"           => { name => 'command', default => 'aws' },
                    "command-path:s"      => { name => 'command_path' },
                    "command-options:s"   => { name => 'command_options', default => '' },
                    });
    }
    $options{options}->add_help(package => __PACKAGE__, sections => 'AWS OPTIONS', once => 1);

    $self->{output} = $options{output};
    $self->{mode} = $options{mode};
    
    return $self;
}

sub set_options {
    my ($self, %options) = @_;

    $self->{option_results} = $options{option_results};
}

sub set_defaults {
    my ($self, %options) = @_;

    foreach (keys %{$options{default}}) {
        if ($_ eq $self->{mode}) {
            for (my $i = 0; $i < scalar(@{$options{default}->{$_}}); $i++) {
                foreach my $opt (keys %{$options{default}->{$_}[$i]}) {
                    if (!defined($self->{option_results}->{$opt}[$i])) {
                        $self->{option_results}->{$opt}[$i] = $options{default}->{$_}[$i]->{$opt};
                    }
                }
            }
        }
    }
}

sub check_options {
    my ($self, %options) = @_;

    if (defined($self->{option_results}->{aws_secret_key}) && $self->{option_results}->{aws_secret_key} ne '') {
        $ENV{AWS_SECRET_ACCESS_KEY} = $self->{option_results}->{aws_secret_key};
    }
    if (defined($self->{option_results}->{aws_access_key}) && $self->{option_results}->{aws_access_key} ne '') {
        $ENV{AWS_ACCESS_KEY_ID} = $self->{option_results}->{aws_access_key};
    }

    return 0;
}

sub cloudwatch_get_metrics_set_cmd {
    my ($self, %options) = @_;
    
    return if (defined($self->{option_results}->{command_options}) && $self->{option_results}->{command_options} ne '');
    $self->{option_results}->{command_options} = 
        "cloudwatch get-metric-statistics --region $options{region} --namespace $options{namespace} --metric-name '$options{metric_name}' --start-time $options{start_time} --end-time $options{end_time} --period $options{period} --statistics " . join(' ', @{$options{statistics}}) . " --output json --dimensions";
    foreach my $entry (@{$options{dimensions}}) {
        $self->{option_results}->{command_options} .= " 'Name=$entry->{Name},Value=$entry->{Value}'";
    }    
}

sub cloudwatch_get_metrics {
    my ($self, %options) = @_;
    
    my $metric_results = {};
    my $start_time = DateTime->now->subtract(seconds => $options{timeframe})->iso8601;
    my $end_time = DateTime->now->iso8601;

    foreach my $metric_name (@{$options{metrics}}) {
        $self->cloudwatch_get_metrics_set_cmd(%options, metric_name => $metric_name, start_time => $start_time, end_time => $end_time);
        my ($response) = centreon::plugins::misc::execute(output => $self->{output},
                                                      options => $self->{option_results},
                                                      sudo => $self->{option_results}->{sudo},
                                                      command => $self->{option_results}->{command},
                                                      command_path => $self->{option_results}->{command_path},
                                                      command_options => $self->{option_results}->{command_options});
        my $metric_result;
        eval {
            $metric_result = JSON::XS->new->utf8->decode($response);
        };
        if ($@) {
            $self->{output}->add_option_msg(short_msg => "Cannot decode json response: $@");
            $self->{output}->option_exit();
        }

        $metric_results->{$metric_result->{Label}} = { points => 0 };
        foreach my $point (@{$metric_result->{Datapoints}}) {
            if (defined($point->{Average})) {
                $metric_results->{$metric_result->{Label}}->{average} = 0 if (!defined($metric_results->{$metric_result->{Label}}->{average}));
                $metric_results->{$metric_result->{Label}}->{average} += $point->{Average};
            }
            if (defined($point->{Minimum})) {
                $metric_results->{$metric_result->{Label}}->{minimum} = $point->{Minimum}
                    if (!defined($metric_results->{$metric_result->{Label}}->{minimum}) || $point->{Minimum} < $metric_results->{$metric_result->{Label}}->{minimum});
            }
            if (defined($point->{Maximum})) {
                $metric_results->{$metric_result->{Label}}->{maximum} = $point->{Maximum}
                    if (!defined($metric_results->{$metric_result->{Label}}->{maximum}) || $point->{Maximum} > $metric_results->{$metric_result->{Label}}->{maximum});
            }
            if (defined($point->{Sum})) {
                $metric_results->{$metric_result->{Label}}->{sum} = 0 if (!defined($metric_results->{$metric_result->{Label}}->{sum}));
                $metric_results->{$metric_result->{Label}}->{sum} += $point->{Sum};
            }
            
            $metric_results->{$metric_result->{Label}}->{points}++;
        }
        
        if (defined($metric_results->{$metric_result->{Label}}->{average})) {
            $metric_results->{$metric_result->{Label}}->{average} /= $metric_results->{$metric_result->{Label}}->{points};
        }
    }
    
    return $metric_results;
}

1;

__END__

=head1 NAME

Amazon AWS

=head1 SYNOPSIS

Amazon AWS

=head1 AWS OPTIONS

=over 8

=item B<--aws-secret-key>

Set AWS secret key.

=item B<--aws-access-key>

Set AWS access key.

=item B<--timeout>

Set timeout (Default: 50).

=item B<--sudo>

Use 'sudo' to execute the command.

=item B<--command>

Command to get information (Default: 'aws').
Can be changed if you have output in a file.

=item B<--command-path>

Command path (Default: none).

=item B<--command-options>

Command options (Default: none).

=back

=head1 DESCRIPTION

B<custom>.

=cut