package C3VOC::Schedule;
use strict;
use XML::Twig;
use Time::Piece;

=head1 NAME

C3VOC::Schedule - reader for the c3voc schedule.xml format for event metadata

=cut

sub read_schedule_xml {
    my ($schedule) = @_;
    my $twig = XML::Twig->new();
    my $s = $twig->parsefile( $schedule )->simplify( forcearray => [qw[day room]] ); # sluuurp
    my $start = time + 15;
    # Maybe we should always renormalize the schedule to the current time?
    # Or have an offset-fudge so we can start late?
    my @talks = map { my $r = $_; map { +{ id => $_, %{$r->{event}->{$_}} } } keys %{ $r->{event}} }
                map { values %{ $_->{room}} }
                @{ $s->{day} };

    #if( scalar keys %only_ids ) {
    #    @talks = grep { exists $only_ids{ $_->{id}} } @talks;
    #};

    for my $t (@talks) {
        $t->{date} =~ s!\+(\d\d):!+$1!;
        if( $t->{date} =~ m!^(20\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d)$! ) {
            $t->{date} = "${1}T$2+0100";
        };
        if( !$t->{date}) {
            use Data::Dumper;
            die Dumper $t;
        };
        $t->{date} = Time::Piece->strptime( $t->{date},'%Y-%m-%dT%H:%M:%S%z' )->epoch;
        $t->{speaker} = join ", ", sort { $a cmp $b } map { $_->{content} } values %{ $t->{persons}->{person}};
        if( $t->{duration} !~ /^(?:\d\d:)?\d\d:\d\d$/) {
            use Data::Dumper;
            die "No duration in " . Dumper $t;
        } elsif ( $t->{duration} =~ /^\d\d:\d\d$/ ) {
            $t->{duration} = "$t->{duration}:00";
        };
        #$t->{slot_duration} = time_to_seconds( $t->{duration} );
    };
    return @talks;
}

1;
