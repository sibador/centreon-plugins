#
# Copyright 2019 Centreon (http://www.centreon.com/)
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

package storage::hp::p2000::xmlapi::mode::components::sensors;

use strict;
use warnings;

my @conditions = (
    ['^warning|not installed|unavailable$' => 'WARNING'],
    ['^error|unrecoverable$' => 'CRITICAL'],
    ['^unknown|unsupported$' => 'UNKNOWN'],
);

my %sensor_type = (
    # 2 it's other. Can be ok or '%'. Need to regexp
    3 => { unit => 'C' },
    6 => { unit => 'V' },
    9 => { unit => 'V' },
);

sub check {
    my ($self) = @_;

    $self->{output}->output_add(long_msg => "Checking sensors");
    $self->{components}->{sensor} = {name => 'sensors', total => 0, skip => 0};
    return if ($self->check_exclude(section => 'sensor'));
    
    # We don't use status-numeric. Values are buggy !!!???
    my $results = $self->{p2000}->get_infos(cmd => 'show sensor-status', 
                                            base_type => 'sensors',
                                            key => 'sensor-name', 
                                            properties_name => '^(value|sensor-type|status)$');

    #<OBJECT basetype="sensors" name="sensor" oid="22" format="rows">
    #  <PROPERTY name="sensor-name" key="true" type="string" size="33" draw="true" sort="string" display-name="Sensor Name">Capacitor Charge-Ctlr B</PROPERTY>
    #  <PROPERTY name="value" type="string" size="8" draw="true" sort="string" display-name="Value">100%</PROPERTY>
    #  <PROPERTY name="status" type="string" size="8" draw="true" sort="string" display-name="Status">OK</PROPERTY>
    #</OBJECT>
    #<OBJECT basetype="sensors" name="sensor" oid="23" format="rows">
    #  <PROPERTY name="sensor-name" key="true" type="string" size="33" draw="true" sort="string" display-name="Sensor Name">Overall Unit Status</PROPERTY>
    #  <PROPERTY name="value" type="string" size="8" draw="true" sort="string" display-name="Value">Warning</PROPERTY>
    #  <PROPERTY name="status" type="string" size="8" draw="true" sort="string" display-name="Status">Warning</PROPERTY>
    #</OBJECT>
    foreach my $sensor_id (keys %$results) {
        next if ($self->check_exclude(section => 'sensor', instance => $sensor_id));
        $self->{components}->{sensor}->{total}++;
        
        my $state = $results->{$sensor_id}->{status};
        
        my ($value, $unit);
        ($value, $unit) = ($1, $2) if ($results->{$sensor_id}->{value} =~ /\s*([0-9\.,]+)\s*(\S*)\s*/);
        if (defined($results->{$sensor_id}->{'sensor-type'}) && defined($sensor_type{$results->{$sensor_id}->{'sensor-type'}})) {
            $unit = $sensor_type{$results->{$sensor_id}->{'sensor-type'}}->{unit};
        }
        
        $self->{output}->output_add(long_msg => sprintf("sensor '%s' status is %s (value: %s %s).",
                                                        $sensor_id, $state, defined($value) ? $value : '-', defined($unit) ? $unit : '-')
                                    );
        foreach (@conditions) {
            if ($state =~ /$$_[0]/i) {
                $self->{output}->output_add(severity =>  $$_[1],
                                            short_msg => sprintf("sensor '%s' status is %s",
                                                        $sensor_id, $state));
                last;
            }
        }

        if (defined($value)) {
            $self->{output}->perfdata_add(
                label => $sensor_id, unit => $unit,
                value => $value
            );
        }
    }
}

1;
